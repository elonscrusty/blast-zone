--!strict
-- Draws every fighter's animation (move, aim and fire, reload, slide, hit, defeat, victory) from code.
-- Each client animates every body itself from what the server already shows everyone: position, the
-- Health and Alive attributes, and the ShotFx / SlideFx / Results events. Players and bots take the
-- same path. Nothing here decides anything; it is all cosmetic.
-- Known gap: a reload is only drawn for you (the server sends AmmoState to its owner alone).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Emotes = require(Shared.Character.Emotes)
local Pose = require(Shared.Character.Pose)
local Net = require(script.Parent.Parent.Core.Net)
local CharacterGun = require("./CharacterGun")
local CharacterRig = require("./CharacterRig")
local WinPose = require(script.Parent.Parent.Emotes.WinPose)

local CharacterAnimSystem = {}
CharacterAnimSystem.order = 130

local tuning = Config.Character
local emoteTuning = Config.Emotes
local MAX_RIG_TRIES = 20
local localId = "p" .. tostring(Players.LocalPlayer.UserId)

type Rec = {
	id: string,
	model: Model,
	root: BasePart,
	joints: CharacterRig.Joints,
	pose: Pose.Pose,
	flash: BasePart?,
	shotAt: number?,
	hitAt: number?,
	slideAt: number?,
	deadAt: number?,
	reloadAt: number?,
	reloadFor: number,
	lastHealth: number?,
	nextTrackSweep: number,
}

local recs: { [Model]: Rec } = {}
local byId: { [string]: Rec } = {}
local winnerId: string? = nil

local function isAlive(model: Model): boolean
	return model:GetAttribute("Alive") ~= false
end

-- Stops any stock animation that still plays (it would draw over ours).
local function sweepTracks(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator ~= nil then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

local function hookGun(rec: Rec)
	local function attach(gun: Instance)
		local hand = rec.model:FindFirstChild("RightHand")
		if
			gun.Name == "CombatGun"
			and gun:IsA("Model")
			and hand ~= nil
			and hand:IsA("BasePart")
		then
			rec.flash = CharacterGun.attach(gun, hand)
		end
	end
	local existing = rec.model:FindFirstChild("CombatGun")
	if existing ~= nil then
		attach(existing)
	end
	rec.model.ChildAdded:Connect(attach)
end

local function track(model: Model, attempt: number)
	if recs[model] ~= nil then
		return
	end
	local id = model:GetAttribute(Config.Attributes.ParticipantId)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if type(id) ~= "string" or humanoid == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local joints = CharacterRig.find(model)
	if joints == nil then
		-- Not a full R15 body yet (parts are still arriving): look again shortly.
		if attempt < MAX_RIG_TRIES then
			task.delay(0.5, function()
				if model.Parent ~= nil then
					track(model, attempt + 1)
				end
			end)
		end
		return
	end
	local rec: Rec = {
		id = id,
		model = model,
		root = root,
		joints = joints,
		pose = Pose.zero(),
		flash = nil,
		shotAt = nil,
		hitAt = nil,
		slideAt = nil,
		deadAt = if isAlive(model) then nil else os.clock(),
		reloadAt = nil,
		reloadFor = 1,
		lastHealth = model:GetAttribute("Health") :: number?,
		nextTrackSweep = 0,
	}
	recs[model] = rec
	byId[id] = rec

	local animate = model:FindFirstChild("Animate")
	if animate ~= nil then
		animate:Destroy()
	end

	model:GetAttributeChangedSignal("Health"):Connect(function()
		local health = model:GetAttribute("Health")
		if type(health) == "number" then
			if rec.lastHealth ~= nil and health < rec.lastHealth then
				rec.hitAt = os.clock()
			end
			rec.lastHealth = health
		end
	end)
	model:GetAttributeChangedSignal("Alive"):Connect(function()
		if isAlive(model) then
			rec.deadAt = nil
		elseif rec.deadAt == nil then
			rec.deadAt = os.clock()
		end
	end)
	hookGun(rec)
	model.AncestryChanged:Once(function(_, parent)
		if parent == nil then
			recs[model] = nil
			if byId[id] == rec then
				byId[id] = nil
			end
		end
	end)
end

local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local attribute = Config.Attributes.ParticipantId
	if inst:GetAttribute(attribute) ~= nil then
		track(inst, 1)
	else
		inst:GetAttributeChangedSignal(attribute):Once(function()
			track(inst, 1)
		end)
	end
end

local function inputFor(rec: Rec, now: number): Pose.Input
	local vel = rec.root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local forward = 0
	if speed > 0.01 then
		local look = rec.root.CFrame.LookVector
		local lookFlat = Vector3.new(look.X, 0, look.Z)
		if lookFlat.Magnitude > 0.01 then
			forward = flat.Unit:Dot(lookFlat.Unit)
		end
	end

	local slideAge: number? = nil
	if rec.slideAt ~= nil then
		local age = now - rec.slideAt
		if age < tuning.slideSeconds then
			slideAge = age
		else
			rec.slideAt = nil
		end
	end

	local reloadPhase: number? = nil
	if rec.reloadAt ~= nil then
		local phase = (now - rec.reloadAt) / rec.reloadFor
		if phase < 1 then
			reloadPhase = phase
		else
			rec.reloadAt = nil
		end
	end

	return {
		t = now,
		speed = speed,
		forward = forward,
		alive = isAlive(rec.model),
		won = winnerId ~= nil and winnerId == rec.id,
		deadAge = if rec.deadAt ~= nil then now - rec.deadAt else nil,
		slideAge = slideAge,
		reloadPhase = reloadPhase,
		shotAge = if rec.shotAt ~= nil then now - rec.shotAt else nil,
		hitAge = if rec.hitAt ~= nil then now - rec.hitAt else nil,
	}
end

-- The emote this body plays (server attributes, piece 29), or nil. Not while dead or moving.
local function emoteOf(model: Model): Pose.Pose?
	local id = model:GetAttribute(emoteTuning.attribute)
	local at = model:GetAttribute(emoteTuning.startedAttribute)
	if type(id) ~= "string" or type(at) ~= "number" or not isAlive(model) then
		return nil
	end
	local age = Workspace:GetServerTimeNow() - at
	if age > emoteTuning.maxSeconds then
		return nil
	end
	return Emotes.compute(id, age)
end

local function step(dt: number)
	local now = os.clock()
	for model, rec in recs do
		if model.Parent == nil then
			continue
		end
		if now >= rec.nextTrackSweep then
			rec.nextTrackSweep = now + 0.5
			sweepTracks(model)
		end
		local target = Pose.compute(inputFor(rec, now))
		if winnerId ~= nil and winnerId == rec.id and isAlive(model) then
			target = Emotes.win(WinPose.of(rec.id), now) -- the winner pose this player picked (piece 29)
		else
			local emote = emoteOf(model)
			if emote ~= nil then
				target = emote
			end
		end
		Pose.blend(rec.pose, target, dt, tuning.smoothing)
		CharacterRig.apply(rec.joints, rec.pose)
		local flash = rec.flash
		if flash ~= nil and flash.Parent ~= nil then
			flash.Transparency = 1 - math.clamp(rec.pose.flash, 0, 1)
		end
	end
end

function CharacterAnimSystem.start()
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)

	Net.on("ShotFx", function(p: any)
		local rec = if type(p) == "table" and type(p.shooterId) == "string"
			then byId[p.shooterId]
			else nil
		if rec ~= nil then
			rec.shotAt = os.clock()
		end
	end)
	Net.on("SlideFx", function(p: any)
		local rec = if type(p) == "table" and type(p.participantId) == "string"
			then byId[p.participantId]
			else nil
		if rec ~= nil then
			rec.slideAt = os.clock()
		end
	end)
	Net.on("AmmoState", function(p: any)
		local rec = byId[localId]
		if rec == nil or type(p) ~= "table" then
			return
		end
		local endsAt, serverNow = p.reloadEndsAt, p.serverNow
		if type(endsAt) == "number" and type(serverNow) == "number" and endsAt > serverNow then
			if rec.reloadAt == nil then
				rec.reloadAt = os.clock()
				rec.reloadFor = math.max(0.2, endsAt - serverNow)
			end
		else
			rec.reloadAt = nil
		end
	end)
	Net.on("Results", function(p: any)
		if type(p) == "table" and type(p.winnerId) == "string" and p.draw ~= true then
			winnerId = p.winnerId
			task.delay(tuning.winnerCheerSeconds, function()
				if winnerId == p.winnerId then
					winnerId = nil
				end
			end)
		end
	end)
	Net.on("MatchState", function(p: any)
		if type(p) == "table" and (p.phase == "Countdown" or p.phase == "Spawning") then
			winnerId = nil
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return CharacterAnimSystem

--!strict
-- First-time hints, drawn in the world so a 7-year-old needs no reading menus:
--   1. "Hold SWEEP!" floats above the character until the first swing.
--   2. When the backpack is half full: "Walk to the Trade Hut and SELL!" plus a glowing line on the
--      ground toward the hut.
--   3. After the first sale: Net.send("TutorialDone") (the server saves it) and everything goes away.
-- Skipped completely when Store.tutorialDone is already true. Call Tutorial.init() once.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Ash.Layout)
local StoreLogic = require(Shared.Client.StoreLogic)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local Tutorial = {}

local SHOW_AFTER = 1 -- seconds of play before the first hint
local SELL_FRACTION = 0.5
local POLL = 0.25

type Stage = "idle" | "sweep" | "wait" | "sell" | "done"

local stage: Stage = "idle"
local startedAt = 0
local started = false
local gui: BillboardGui? = nil
local label: TextLabel? = nil
local beam: Beam? = nil
local att0: Attachment? = nil
local targetPart: Part? = nil
local conns: { RBXScriptConnection } = {}
local sweptConn: any = nil -- a Shared/Signal connection (disconnect, lowercase)
local polled = 0

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function hutPosition(from: Vector3): Vector3
	local best: Vector3? = nil
	local bestD = math.huge
	for _, inst in CollectionService:GetTagged("VSSellPad") do
		if inst:IsA("BasePart") then
			local d = (inst.Position - from).Magnitude
			if d < bestD then
				bestD = d
				best = inst.Position
			end
		end
	end
	return best or Vector3.new(Layout.hubX, Config.World.groundY, Layout.hubZ)
end

local function ensureGui(): (BillboardGui?, TextLabel?)
	if gui ~= nil and gui.Parent ~= nil and label ~= nil then
		return gui, label
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil, nil
	end
	local g = Instance.new("BillboardGui")
	g.Name = "VSTutorialHint"
	g.Size = UDim2.fromOffset(300, 70)
	g.StudsOffset = Vector3.new(0, 5.5, 0)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Enabled = false
	g.Parent = pg
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 233, 120)
	l.Text = ""
	l.Parent = g
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.MinTextSize = 14
	limit.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 30, 20)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = l
	gui, label = g, l
	return g, l
end

local function ensureBeam(hrp: BasePart): Beam?
	if beam == nil or beam.Parent == nil or att0 == nil or targetPart == nil then
		local part = Instance.new("Part")
		part.Name = "VSTutorialTarget"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.Parent = workspace
		local a1 = Instance.new("Attachment")
		a1.Parent = part
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, -2.4, 0)
		a0.Parent = hrp
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Segments = 1
		b.Width0 = 0.9
		b.Width1 = 0.9
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Transparency = NumberSequence.new(0.25)
		b.Color = ColorSequence.new(Color3.fromRGB(255, 210, 63), Color3.fromRGB(255, 122, 89))
		b.Parent = part
		beam, att0, targetPart = b, a0, part
	end
	local a = att0 :: Attachment
	if a.Parent ~= hrp then
		a.Parent = hrp
	end
	return beam
end

local function hideBeam()
	if beam ~= nil then
		beam.Enabled = false
	end
end

local function cleanup()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if sweptConn ~= nil then
		sweptConn:disconnect()
		sweptConn = nil
	end
	if gui ~= nil then
		gui:Destroy()
	end
	if targetPart ~= nil then
		targetPart:Destroy()
	end
	if att0 ~= nil then
		att0:Destroy()
	end
	gui, label, beam, att0, targetPart = nil, nil, nil, nil, nil
end

local function showText(text: string, hrp: BasePart)
	local g, l = ensureGui()
	if g == nil or l == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	local adornee: Instance = if head ~= nil and head:IsA("BasePart") then head else hrp
	if g.Adornee ~= adornee then
		g.Adornee = adornee
	end
	l.Text = text
	g.Enabled = true
end

local function hideText()
	if gui ~= nil then
		gui.Enabled = false
	end
end

local function sweepHintText(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Hold SWEEP!"
	end
	return "Hold E or click to SWEEP!"
end

local function poll()
	local hrp = myRoot()
	if hrp == nil then
		hideText()
		hideBeam()
		return
	end
	local view = Store.view()
	if stage == "sweep" then
		if os.clock() - startedAt >= SHOW_AFTER then
			showText(sweepHintText(), hrp)
		end
	elseif stage == "wait" then
		hideText()
		if StoreLogic.backpackFraction(view) >= SELL_FRACTION then
			stage = "sell"
		end
	elseif stage == "sell" then
		local hut = hutPosition(hrp.Position)
		local flat = Vector3.new(hut.X - hrp.Position.X, 0, hut.Z - hrp.Position.Z).Magnitude
		if flat <= Config.World.sellRange then
			hideText()
			hideBeam()
		else
			showText("Walk to the Trade Hut and SELL!", hrp)
			local b = ensureBeam(hrp)
			if b ~= nil then
				(targetPart :: Part).Position =
					Vector3.new(hut.X, Config.World.groundY + 1.2, hut.Z)
				b.Enabled = true
			end
		end
	end
end

function Tutorial.init()
	if started then
		return
	end
	started = true
	Store.onReady(function()
		if Store.get("tutorialDone") == true then
			stage = "done"
			return
		end
		stage = "sweep"
		startedAt = os.clock()

		local controls = script.Parent:FindFirstChild("Controls")
		if controls ~= nil and controls:IsA("ModuleScript") then
			local ok, mod = pcall(require, controls)
			if ok and mod.swept ~= nil then
				sweptConn = mod.swept:connect(function()
					if stage == "sweep" then
						stage = "wait"
						hideText()
					end
				end)
			end
		end

		table.insert(
			conns,
			Net.on("Sold", function()
				if stage == "done" then
					return
				end
				stage = "done"
				Net.send("TutorialDone")
				cleanup()
			end)
		)
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				polled += dt
				if polled < POLL then
					return
				end
				polled = 0
				if stage ~= "done" then
					poll()
				end
			end)
		)
	end)
end

return Tutorial

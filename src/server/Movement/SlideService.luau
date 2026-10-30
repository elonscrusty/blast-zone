--!strict
-- The server's slide. One door (`request`) for players and bots, so both follow the same rules:
-- body must exist and be alive, the match must be live (or the player is not in a match yet),
-- the cooldown must be over, and the way must not be blocked. The server picks the distance;
-- the client only says which way.
--
-- Who moves the body: a player's own client (it owns its character), then the server checks where
-- the player ended up and pulls them back if that is too far. A bot has no client, so the server
-- moves it with the same SlideMotion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local SlideBook = require(Shared.Movement.SlideBook)
local SlideCast = require(Shared.Movement.SlideCast)
local SlideMotion = require(Shared.Movement.SlideMotion)
local SlideRules = require(Shared.Movement.SlideRules)
local Signal = require(Shared.Signal)

local Core = script.Parent.Parent.Core
local EffectiveStats = require(Core.EffectiveStats)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local SlideService = {}

-- A player's slide was accepted: (participantId, distance). The move watch (piece 27) lets that
-- much extra distance through.
SlideService.PlayerSlid = Signal.new()

export type Result = {
	ok: boolean,
	reason: string?, -- why not: nobody, dead, gate, active, cooldown, blocked
	fromPos: Vector3?,
	toPos: Vector3?,
	duration: number?,
}

type Body = { model: Model, root: BasePart, humanoid: Humanoid, player: Player? }

local book = SlideBook.new()
local botBodies: { [string]: Body } = {}
local botMotion: { [string]: SlideMotion.Handle } = {}

local function bodyOfModel(model: Model?, player: Player?): Body?
	if model == nil or model.Parent == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return nil
	end
	return { model = model, root = root, humanoid = humanoid, player = player }
end

local function bodyOf(id: string): Body?
	if Ids.isBot(id) then
		local body = botBodies[id]
		if body and body.model.Parent ~= nil then
			return body
		end
		return nil
	end
	local userId = Ids.userIdOf(id)
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	if player == nil then
		return nil
	end
	return bodyOfModel(player.Character, player)
end

-- Not in a match yet (lobby): free to practise. In a match: alive and the fight must be live.
local function gateFor(id: string, body: Body): (boolean, boolean)
	local alive = body.humanoid.Health > 0
	local participant = Participants:get(id)
	if participant == nil then
		return alive, true
	end
	return alive and participant.alive, MatchContext:isCombat()
end

local function arenaBounds(): SlideCast.Bounds
	local half = Config.Arena.size / 2
	return {
		minX = Config.Arena.centerX - half,
		maxX = Config.Arena.centerX + half,
		minZ = Config.Arena.centerZ - half,
		maxZ = Config.Arena.centerZ + half,
	}
end

local function deny(reason: string): Result
	return { ok = false, reason = reason }
end

-- Asks for a slide. `dirX/dirZ` is where the participant is moving (nil or zero = face direction).
function SlideService.request(id: string, dirX: number?, dirZ: number?): Result
	local body = bodyOf(id)
	if body == nil then
		return deny("nobody")
	end
	local now = Workspace:GetServerTimeNow()
	local alive, gateOpen = gateFor(id, body)
	local reason = book:check(id, now, alive, gateOpen)
	if reason then
		return deny(reason)
	end

	local root = body.root
	local look = root.CFrame.LookVector
	local dx, dz = SlideRules.direction(dirX, dirZ, look.X, look.Z)
	if dx == nil or dz == nil then
		return deny("blocked")
	end

	local stats = EffectiveStats:get(id)
	local bounds = if Participants:get(id) ~= nil then arenaBounds() else nil
	local distance = SlideCast.resolve(
		body.model,
		root,
		body.humanoid.HipHeight,
		dx,
		dz,
		stats.slideDistance,
		bounds
	)
	if distance < Config.Slide.minDistance then
		return deny("blocked") -- a wall right there: no slide and no cooldown spent
	end

	local duration = stats.slideDuration
	local cooldown = SlideRules.cooldown(stats.slideCooldown, Config.Slide.minCooldown)
	local token = book:commit(id, now, duration, cooldown, Config.Slide.charges)

	local from = root.Position
	local to = from + Vector3.new(dx, 0, dz) * distance

	if body.player then
		SlideService.PlayerSlid:fire(id, distance)
		SlideService.sendState(id, body.player, now)
		-- If the player is farther than a slide can explain once it is over, put them back.
		local walk = body.humanoid.WalkSpeed
		task.delay(duration + Config.Slide.endGrace, function()
			if not book:isCurrent(id, token) or root.Parent == nil then
				return
			end
			local here = root.Position
			if
				not SlideRules.endPlausible(
					from.X,
					from.Z,
					here.X,
					here.Z,
					distance,
					walk,
					Config.Slide.endGrace,
					Config.Slide.endTolerance
				)
			then
				root.CFrame = CFrame.new(to) * (root.CFrame - root.CFrame.Position)
			end
		end)
	else
		botMotion[id] = SlideMotion.run(root, dx, dz, distance, duration, function()
			botMotion[id] = nil
		end)
	end
	Net.fireAll("SlideFx", { participantId = id, fromPos = from, toPos = to, duration = duration })
	return { ok = true, fromPos = from, toPos = to, duration = duration }
end

-- Tells a player how many slides they have and when the next one is back. `cooldownEndsAt` is
-- "now" while a charge is ready, so the old HUD dial keeps working.
function SlideService.sendState(id: string, player: Player, now: number)
	local charges, max = book:charges(id, now, Config.Slide.charges)
	Net.fire("SlideState", player, {
		cooldownEndsAt = if charges > 0 then now else book:readyAt(id),
		serverNow = now,
		charges = charges,
		maxCharges = max,
	})
end

function SlideService.isReady(id: string): boolean
	local body = bodyOf(id)
	if body == nil then
		return false
	end
	local alive, gateOpen = gateFor(id, body)
	return alive and gateOpen and book:isReady(id, Workspace:GetServerTimeNow())
end

function SlideService.isSliding(id: string): boolean
	return book:isActive(id, Workspace:GetServerTimeNow())
end

-- A slide ends now (death, reset). The cooldown stays.
function SlideService.cancel(id: string)
	book:cancel(id, Workspace:GetServerTimeNow())
	local motion = botMotion[id]
	if motion then
		motion.cancel()
	end
end

function SlideService.registerBotBody(id: string, model: Model)
	local body = bodyOfModel(model, nil)
	if body then
		botBodies[id] = body
		book:reset(id)
		pcall(function()
			body.root:SetNetworkOwner(nil) -- the server moves bots
		end)
	end
end

function SlideService.start()
	Net.onRequest("SlideRequest", function(player: Player, dir: Vector3?)
		local id = Ids.player(player.UserId)
		local result =
			SlideService.request(id, if dir then dir.X else nil, if dir then dir.Z else nil)
		if result.ok then
			return
		end
		Net.fire("SlideDenied", player, {}) -- the client cancels the slide it started early
		if result.reason == "cooldown" or result.reason == "active" then
			-- Tell the client the truth about the cooldown so its dial agrees.
			SlideService.sendState(id, player, Workspace:GetServerTimeNow())
		end
	end)

	Participants.Eliminated:connect(function(p)
		SlideService.cancel(p.id)
	end)
	Participants.Removed:connect(function(p)
		SlideService.cancel(p.id)
		book:reset(p.id)
		botBodies[p.id] = nil
	end)
	MatchContext.MatchStarted:connect(function()
		for id in botMotion do
			SlideService.cancel(id)
		end
		book:clear()
	end)
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Waiting" or phase == "Resetting" then
			for id in botMotion do
				SlideService.cancel(id)
			end
			book:clear()
			table.clear(botBodies)
		end
	end)

	local function watchPlayer(player: Player)
		local id = Ids.player(player.UserId)
		local function onCharacter(character: Model)
			book:reset(id) -- a new body starts with a fresh slide
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					SlideService.cancel(id)
				end)
			end
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		book:reset(Ids.player(player.UserId))
	end)
end

return SlideService

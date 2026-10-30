--!strict
-- Test bots (brief section 18). Wires the pure bot code into the game:
--   * A lone player waiting gets a short count, then bots join (or they tap "Add bots now").
--     Bots are asked for through MatchSystem.requestBots; the match flow enrolls them.
--   * When the match flow hands a bot its spawn (MatchSystem.SpawnAssigned) a labeled Crash Dummy
--     is built there and starts thinking.
--   * Bots shoot, reload and slide only through the other pieces' BotPort doors (see BotPorts), so
--     every health, ammo, fire-rate and cooldown rule is the same as a player's.
-- The match flow owns who is in the match. This file owns what a bot does with its body.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)

local Server = ServerScriptService:WaitForChild("Server")
local Core = Server:WaitForChild("Core")
local CollisionGroups = require(Core.CollisionGroups)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)
local EffectiveStats = require(Core.EffectiveStats)
local SpawnShields = require(Core.SpawnShields)

local BotBrain = require("./BotBrain")
local BotPorts = require("./BotPorts")
local BotRoblox = require("./BotRoblox")
local BotRoster = require("./BotRoster")
local BotRunner = require("./BotRunner")
local BotTuning = require("./BotTuning")

local BotSystem = {}
BotSystem.order = 300 -- after the match flow and combat have started

local tuning = BotTuning.from(Config)
local rigs: { [string]: Model } = {}
local requested = 0 -- bots asked for in this wait
local fill = BotRoster.newFill()
local lastTap: { [Player]: number } = {}
local lastShown: number? = nil
local warned: { [string]: boolean } = {}
local runner: BotRunner.Runner? = nil
local sightParams: RaycastParams? = nil
local sightParamsAt = -10
local sightGroundY = 0
local pickupCache: { BotBrain.Pickup } = {}
local pickupCacheAt = -10
local PICKUP_CACHE_SECONDS = 0.1 -- every bot thinking in the same moment shares one scan
local STEP_SECONDS = 1 / 30 -- bots move and think at 30 Hz; thinkInterval is much longer anyway

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn("[bots] " .. text)
	end
end

local function humanCount(): number
	return #Players:GetPlayers()
end

local function isWaiting(): boolean
	return MatchContext:getPhase() == MatchPhase.Waiting
end

-- ===== the world the runner talks to =====

local function rootOf(id: string): BasePart?
	local rig = rigs[id]
	if rig then
		return BotRoblox.rootOf(rig)
	end
	local p = Participants:get(id)
	local player = p and p.player
	if player and player.Character then
		return BotRoblox.rootOf(player.Character)
	end
	return nil
end

local function groundY(): number
	for id in rigs do
		local root = rootOf(id)
		if root then
			return root.Position.Y - 3 -- an R15 root sits about 3 studs above the floor
		end
	end
	return 0
end

local function makeWorld(): BotRunner.World
	return {
		now = os.clock,
		isActive = function()
			return MatchContext:isCombat()
		end,
		fightSeconds = function()
			-- Calm start counts from the start of Active; FinalPressure means full strength.
			if MatchContext:getPhase() == MatchPhase.Active then
				return MatchContext:phaseElapsed()
			end
			return math.huge
		end,
		selfState = function(id)
			local root = rootOf(id)
			local combat = BotPorts.combat()
			if not root or not Participants:isAlive(id) then
				return nil
			end
			if not combat then
				warnOnce("combat", "Combat/BotPort not found: bots cannot fight yet")
				return nil
			end
			local st = combat.state(id)
			if not st then
				return nil
			end
			local movement = BotPorts.movement()
			return {
				id = id,
				pos = { x = root.Position.X, z = root.Position.Z },
				health = st.health,
				maxHealth = st.maxHealth,
				ammo = st.ammo,
				magazine = st.magazine,
				reloading = st.reloading,
				canFire = st.canFire,
				slideReady = movement ~= nil and movement.slideReady(id),
			}
		end,
		others = function(id)
			local out: { BotBrain.Body } = {}
			for _, p in Participants:aliveList() do
				if p.id ~= id then
					local root = rootOf(p.id)
					if root then
						table.insert(out, {
							id = p.id,
							pos = { x = root.Position.X, z = root.Position.Z },
							shielded = SpawnShields:isShielded(p.id),
						})
					end
				end
			end
			return out
		end,
		pickups = function()
			local clock = os.clock()
			if clock - pickupCacheAt < PICKUP_CACHE_SECONDS then
				return pickupCache
			end
			pickupCacheAt = clock
			local out: { BotBrain.Pickup } = {}
			local serverNow = Workspace:GetServerTimeNow()
			for _, part in CollectionService:GetTagged("Pickup") do
				local id = part:GetAttribute("PickupId")
				if type(id) == "string" and part:IsA("BasePart") then
					-- An orb held for someone else is not worth walking to yet.
					local reservedFor = part:GetAttribute("ReservedFor")
					local reservedUntil = part:GetAttribute("ReservedUntil")
					local held = type(reservedFor) == "string"
						and reservedFor ~= ""
						and type(reservedUntil) == "number"
						and reservedUntil > serverNow
					if not held then
						table.insert(
							out,
							{ id = id, pos = { x = part.Position.X, z = part.Position.Z } }
						)
					end
				end
			end
			pickupCache = out
			return out
		end,
		zone = function()
			local zoneSystem = BotPorts.zone()
			local sample = zoneSystem and zoneSystem.getSample()
			if sample then
				-- While it closes, head for where it is going to be.
				local radius = math.min(sample.radius, sample.toRadius)
				return { center = { x = sample.centerX, z = sample.centerZ }, radius = radius }
			end
			return nil
		end,
		weaponRange = function(id)
			return EffectiveStats:get(id).firearm.range
		end,
		canSee = function(a, b)
			-- Walls do not move, so one params object serves every look for a couple of seconds.
			local now = os.clock()
			if not sightParams or now - sightParamsAt > 2 then
				local combat = BotPorts.combat()
				sightParams = if combat and combat.shotParams
					then combat.shotParams()
					else BotRoblox.fallbackShotParams()
				sightParamsAt = now
				sightGroundY = groundY()
			end
			return BotRoblox.clearBetween(
				sightParams :: RaycastParams,
				sightGroundY,
				a.x,
				a.z,
				b.x,
				b.z
			)
		end,
		move = function(id, x, z)
			local rig = rigs[id]
			if rig then
				BotRoblox.move(rig, x, z)
			end
		end,
		fire = function(id, aimX, aimZ)
			local combat = BotPorts.combat()
			if combat then
				combat.fire(id, aimX, aimZ)
			end
		end,
		reload = function(id)
			local combat = BotPorts.combat()
			if combat then
				combat.reload(id)
			end
		end,
		slide = function(id, dirX, dirZ)
			local movement = BotPorts.movement()
			if movement then
				movement.slide(id, dirX, dirZ)
			end
		end,
	}
end

-- ===== bodies =====

local function clearRigs()
	if runner then
		runner:clear()
	end
	for id, rig in rigs do
		rig:Destroy()
		rigs[id] = nil
	end
end

local function placeBot(participant: any, pos: any, lookAt: any)
	local id: string = participant.id
	local matchId: number = participant.matchId
	local rig = rigs[id]
	if not rig then
		rig = BotRoblox.makeRig(id, participant.displayName, Workspace)
		-- Building the rig yields. If the match moved on in the meantime, throw it away.
		if not MatchContext:isCurrent(matchId) or not Participants:get(id) then
			rig:Destroy()
			return
		end
		rigs[id] = rig
		CollisionGroups.apply(rig)
		local combat = BotPorts.combat()
		if combat then
			combat.registerBotBody(id, rig)
		end
		local movement = BotPorts.movement()
		if movement then
			movement.registerBotBody(id, rig)
		end
	end
	rig:PivotTo(
		CFrame.lookAt(Vector3.new(pos.x, pos.y, pos.z), Vector3.new(lookAt.x, pos.y, lookAt.z))
	)
	if runner then
		runner:add(id)
	end
end

-- A bot picks up what it stands next to, like a player's client asking when close. The pickup piece
-- decides: distance, reservation and first-come claim are all checked there.
local function collectNearby()
	local pickupSystem = BotPorts.pickups()
	if not pickupSystem then
		return
	end
	local reach = Config.Pickups.collectRadius
	local orbs = CollectionService:GetTagged("Pickup") -- once for every bot, not once per bot
	if #orbs == 0 then
		return
	end
	for id in rigs do
		local root = rootOf(id)
		if root and Participants:isAlive(id) then
			for _, part in orbs do
				local pickupId = part:GetAttribute("PickupId")
				if
					type(pickupId) == "string"
					and part:IsA("BasePart")
					and (part.Position - root.Position).Magnitude <= reach
				then
					pickupSystem.tryClaim(id, root.Position, pickupId)
				end
			end
		end
	end
end

-- ===== asking for bots =====

local function askForBots(count: number): number
	if count <= 0 then
		return 0
	end
	local matchFolder = Server:FindFirstChild("Match")
	local matchModule = matchFolder and matchFolder:FindFirstChild("MatchSystem")
	if not matchModule then
		warnOnce("match", "Match/MatchSystem not found: cannot ask for bots yet")
		return 0
	end
	local ok, matchSystem = pcall(require, matchModule)
	if not ok or type(matchSystem) ~= "table" or type(matchSystem.requestBots) ~= "function" then
		warnOnce("match", "MatchSystem.requestBots is missing")
		return 0
	end
	local accepted = matchSystem.requestBots(count)
	if type(accepted) == "number" and accepted > 0 then
		requested += accepted
		return accepted
	end
	return 0
end

local function fillUp()
	askForBots(BotRoster.botsToAdd(tuning, humanCount(), requested))
end

local function showBanner(secondsLeft: number?)
	if secondsLeft == lastShown then
		return
	end
	lastShown = secondsLeft
	Net.fireAll("BotFillState", { secondsLeft = secondsLeft })
end

local function autoFillTick()
	local result = BotRoster.updateFill(tuning, fill, os.clock(), isWaiting(), humanCount())
	if result.action == "countdown" and result.alone then
		showBanner(result.secondsLeft)
	else
		showBanner(nil)
		if result.action == "fill" then
			fillUp()
		end
	end
end

local function onAddBotsRequest(player: Player)
	local ok, why =
		BotRoster.checkAddNow(tuning, isWaiting(), humanCount(), os.clock(), lastTap[player])
	lastTap[player] = os.clock()
	if not ok then
		Net.fire(
			"Notice",
			player,
			{ text = "Bots can only join while you wait alone (" .. why .. ")", kind = "info" }
		)
		return
	end
	fill.filled = true
	showBanner(nil)
	fillUp()
end

-- ===== start =====

function BotSystem.start()
	if not Config.Features.bots then
		return
	end
	local rng = Random.new()
	runner = BotRunner.new(makeWorld(), tuning, function()
		return rng:NextNumber()
	end, function(id, msg)
		warn(`[bots] {id} thinking failed: {msg}`)
	end)
	local activeRunner = runner :: BotRunner.Runner
	local sinceCollect = 0
	local sinceStep = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceStep += dt
		if sinceStep >= STEP_SECONDS then
			sinceStep = 0
			activeRunner:step()
		end
		sinceCollect += dt
		if sinceCollect >= 0.25 then
			sinceCollect = 0
			collectNearby()
		end
	end)

	Net.onRequest("AddBotsRequest", onAddBotsRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastTap[player] = nil
	end)

	MatchContext.PhaseChanged:connect(function(newPhase: string)
		if newPhase == MatchPhase.Resetting or newPhase == MatchPhase.Waiting then
			clearRigs()
			requested = 0
		end
	end)

	-- The match flow tells us where each participant spawns. Only bots are ours.
	task.spawn(function()
		local matchFolder = Server:WaitForChild("Match", 30)
		local matchModule = matchFolder and matchFolder:WaitForChild("MatchSystem", 30)
		if not matchModule then
			warnOnce("match", "Match/MatchSystem not found: bots will not appear")
			return
		end
		local matchSystem = require(matchModule :: ModuleScript) :: any
		matchSystem.SpawnAssigned:connect(function(participant: any, pos: any, lookAt: any)
			if participant.kind == "bot" then
				task.spawn(placeBot, participant, pos, lookAt)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(autoFillTick)
			if not ok then
				warn(`[bots] auto-fill failed: {err}`)
			end
		end
	end)
end

return BotSystem

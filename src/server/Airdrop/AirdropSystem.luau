--!strict
-- Airdrop (video 3 gap #3). The server picks the drops for each match, tells every client with
-- `AirdropState` (a beam and a falling crate are drawn from those times), and when a crate has
-- been shut long enough it puts the loot on the street: a found gun, heal packs and XP orbs.
--   * When: Config.Airdrop schedules a few drops after the fight starts (AirdropRules.schedule).
--   * Where: a random open spot inside the circle as it will be (it may be closing), checked with
--     a raycast, never on a roof, in a prop or near the last drop.
--   * What: loot uses the same pickups as everything else, so claiming is already checked there.
-- Clients never ask for a drop. A client that joined late asks for the running ones.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AirdropRules = require(Shared.Airdrop.AirdropRules)
local Config = require(Shared.Config)
local LootRules = require(Shared.Loot.LootRules)
local MatchPhase = require(Shared.MatchPhase)

local Core = script.Parent.Parent.Core
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)

local WeaponDrops = require(script.Parent.Parent.Combat.WeaponDrops)
local ContainerRules = require(script.Parent.Parent.Pickups.ContainerRules)
local PickupSystem = require(script.Parent.Parent.Pickups.PickupSystem)
local ZoneSystem = require(script.Parent.Parent.Zone.ZoneSystem)

local AirdropSystem = {}
AirdropSystem.order = 160 -- after loot (150) and pickups; the circle is only read when a drop launches

type Drop = {
	id: string,
	matchId: number,
	spot: AirdropRules.Spot,
	startedAt: number, -- server time
	landsAt: number,
	opensAt: number,
}

local rng = Random.new()
local drops: { Drop } = {}
local placed: { AirdropRules.Spot } = {} -- every drop this match, opened or not (so two never land together)
local schedule: { number } = {}
local nextIndex = 1
local fightStartedAt: number? = nil -- os.clock() when the fight began
local sinceCheck = 0
local nextNumber = 0

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function roll(): number
	return rng:NextNumber()
end

local function arenaParams(): RaycastParams?
	local arena = Workspace:FindFirstChild(Config.Workspace.ArenaFolder)
	if arena == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arena }
	return params
end

-- The floor height of the supply crate markers (the lowest one). Drops only land on ground that high.
local function referenceFloor(): number?
	local lowest: number? = nil
	for _, inst in CollectionService:GetTagged(Config.Tags.ContainerSpot) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
			local y = inst.Position.Y - inst.Size.Y / 2
			if lowest == nil or y < lowest then
				lowest = y
			end
		end
	end
	return lowest
end

-- Open street at (x, z) at the reference height, or nil (a wall, a prop, a roof or a hole is there).
local function openFloor(params: RaycastParams, floorY: number, x: number, z: number): number?
	local cfg = Config.Airdrop.spot
	local function probe(px: number, pz: number): number?
		local hit = Workspace:Raycast(
			Vector3.new(px, floorY + cfg.rayHeight, pz),
			Vector3.new(0, -(cfg.rayHeight + 20), 0),
			params
		)
		if hit == nil or not hit.Instance.CanCollide then
			return nil
		end
		if math.abs(hit.Position.Y - floorY) > cfg.floorTolerance then
			return nil
		end
		return hit.Position.Y
	end
	local y = probe(x, z)
	if y == nil then
		return nil
	end
	local r = cfg.clearStuds
	for _, o in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } } do
		if probe(x + o[1], z + o[2]) == nil then
			return nil
		end
	end
	return y
end

local function findSpot(): AirdropRules.Spot?
	local params = arenaParams()
	local floorY = referenceFloor()
	if params == nil or floorY == nil then
		return nil
	end
	local sample = ZoneSystem.getSample()
	local cx, cz = Config.Zone.centerX, Config.Zone.centerZ
	local radius = Config.Zone.initialRadius
	local closingTo = radius
	if sample ~= nil then
		cx, cz = sample.centerX, sample.centerZ
		radius = sample.radius
		closingTo = sample.toRadius
	end
	local cfg = Config.Airdrop.spot
	return AirdropRules.pickSpot(
		cx,
		cz,
		AirdropRules.safeRadius(radius, closingTo, cfg.insideMargin),
		cfg.tries,
		roll,
		function(x: number, z: number): number?
			return openFloor(params, floorY, x, z)
		end,
		placed,
		cfg.minApartStuds
	)
end

local function payload(drop: Drop, event: string): { [string]: any }
	return {
		event = event,
		dropId = drop.id,
		matchId = drop.matchId,
		pos = Vector3.new(drop.spot.x, drop.spot.y, drop.spot.z),
		startedAt = drop.startedAt,
		landsAt = drop.landsAt,
		opensAt = drop.opensAt,
		serverNow = serverNow(),
		look = Config.Airdrop.look,
	}
end

local function launch(matchId: number)
	local spot = findSpot()
	if spot == nil then
		warn("[airdrop] no open spot found; this drop is skipped")
		return
	end
	local cfg = Config.Airdrop
	nextNumber += 1
	local now = serverNow()
	local drop: Drop = {
		id = `a{matchId}_{nextNumber}`,
		matchId = matchId,
		spot = spot,
		startedAt = now,
		landsAt = now + cfg.fallSeconds,
		opensAt = now + cfg.fallSeconds + cfg.shutSeconds,
	}
	table.insert(drops, drop)
	table.insert(placed, spot)
	Net.fireAll("AirdropState", payload(drop, "incoming"))
end

-- Puts the loot on the street. Called once per drop, when it opens.
local function open(drop: Drop)
	local cfg = Config.Airdrop
	local floor = Vector3.new(drop.spot.x, drop.spot.y, drop.spot.z)
	local count = (if cfg.loot.gun then 1 else 0) + cfg.loot.packs
	local offsets = ContainerRules.scatter(
		math.max(count, 1),
		cfg.loot.ringStuds,
		rng:NextNumber() * 2 * math.pi
	)
	local slot = 0
	local function nextSpot(): Vector3
		slot += 1
		local o = offsets[slot] or offsets[1]
		return floor + Vector3.new(o.x, 0, o.z)
	end
	if cfg.loot.gun then
		local gunId = LootRules.pickGun(Config, rng:NextNumber())
		if gunId ~= nil then
			WeaponDrops.spawn(gunId, nextSpot(), drop.matchId, true)
		end
	end
	for _ = 1, cfg.loot.packs do
		PickupSystem.spawnHeal(nextSpot())
	end
	if cfg.loot.orbs > 0 then
		PickupSystem.spawnOrbs(floor, cfg.loot.orbs, nil)
	end
	Net.fireAll("AirdropState", payload(drop, "opened"))
end

local function reset(tellClients: boolean)
	local hadAny = #drops > 0
	table.clear(drops)
	table.clear(placed)
	table.clear(schedule)
	nextIndex = 1
	fightStartedAt = nil
	if tellClients and hadAny then
		Net.fireAll("AirdropState", { event = "clear", serverNow = serverNow() })
	end
end

local function step()
	if not MatchContext:isCombat() or fightStartedAt == nil then
		return
	end
	local matchId = MatchContext:getMatchId()
	local elapsed = os.clock() - fightStartedAt
	while nextIndex <= #schedule and elapsed >= schedule[nextIndex] do
		nextIndex += 1
		launch(matchId)
	end
	local now = serverNow()
	for i = #drops, 1, -1 do
		local drop = drops[i]
		if drop.matchId ~= matchId then
			table.remove(drops, i)
		elseif AirdropRules.stage(now, drop.landsAt, drop.opensAt) == "opened" then
			table.remove(drops, i)
			open(drop)
		end
	end
end

function AirdropSystem.start()
	if not Config.Airdrop.enabled then
		return
	end
	local cfg = Config.Airdrop

	Net.onRequest("AirdropRequest", function(player: Player)
		for _, drop in drops do
			Net.fire("AirdropState", player, payload(drop, "incoming"))
		end
	end)

	MatchContext.MatchStarted:connect(function()
		reset(true)
	end)
	MatchContext.PhaseChanged:connect(function(phase: string, _old: string, _matchId: number)
		if phase == MatchPhase.Active and fightStartedAt == nil then
			schedule = AirdropRules.schedule(
				cfg.count,
				cfg.firstAtSeconds,
				cfg.lastAtSeconds,
				cfg.jitterSeconds,
				cfg.minGapSeconds,
				roll
			)
			nextIndex = 1
			fightStartedAt = os.clock()
		elseif phase == MatchPhase.Resetting or phase == MatchPhase.Waiting then
			reset(true)
		elseif phase == MatchPhase.Finished then
			-- The fight is over: no new drops, and a shut crate does not open for nobody.
			fightStartedAt = nil
			if #drops > 0 then
				reset(true)
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck >= 0.25 then
			sinceCheck = 0
			step()
		end
	end)
end

return AirdropSystem

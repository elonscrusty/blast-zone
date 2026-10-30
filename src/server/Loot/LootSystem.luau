--!strict
-- Piece 42: loot on the street.
--   * When a match reaches Spawning, heal packs and found guns are put on open floor near supply
--     crate markers (the same markers the crates use, so every map gets loot without new art).
--   * A heal pack is taken through PickupSystem (walk close; the server checks) and used with
--     UseHealRequest. HealPacks.luau decides every use. Bots use theirs when hurt.
--   * A fighter who falls drops one pack if they carried any.
-- Floor guns use WeaponDrops (the same swap button as a crate gun), but never expire.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LootRules = require(Shared.Loot.LootRules)

local Core = script.Parent.Parent.Core
local Damage = require(Core.Damage)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local Combatants = require(script.Parent.Parent.Combat.Combatants)
local WeaponDrops = require(script.Parent.Parent.Combat.WeaponDrops)
local PickupSystem = require(script.Parent.Parent.Pickups.PickupSystem)
local HealPacks = require(script.Parent.HealPacks)

local LootSystem = {}
LootSystem.order = 150 -- after combat (WeaponDrops) and pickups

local rng = Random.new()
local sinceSweep = 0

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

-- Floor height under (x, z) if it is open ground at about `floorY`; nil if there is a wall, a prop
-- or a hole there.
local function openFloor(params: RaycastParams, x: number, z: number, floorY: number): number?
	local cfg = Config.Loot.spots
	local hit = Workspace:Raycast(
		Vector3.new(x, floorY + cfg.rayHeight, z),
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

-- Every open-floor spot near a crate marker.
local function candidates(): { LootRules.Spot }
	local params = arenaParams()
	local out: { LootRules.Spot } = {}
	if params == nil then
		return out
	end
	local cfg = Config.Loot.spots
	for _, inst in CollectionService:GetTagged(Config.Tags.ContainerSpot) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
			local floorY = inst.Position.Y - inst.Size.Y / 2
			local phase = rng:NextNumber() * 2 * math.pi
			for i = 1, cfg.angles do
				local c = LootRules.ringPoint(
					inst.Position.X,
					inst.Position.Z,
					cfg.offsetStuds,
					i,
					cfg.angles,
					phase
				)
				local y = openFloor(params, c.x, c.z, floorY)
				if y ~= nil then
					table.insert(out, { x = c.x, z = c.z, y = y })
				end
			end
		end
	end
	return out
end

-- Puts the match's floor loot out. Returns how many guns and packs were placed.
function LootSystem.spawnFloorLoot(matchId: number): (number, number)
	local loot = Config.Loot
	if not loot.enabled then
		return 0, 0
	end
	local cands = candidates()
	local roll = function()
		return rng:NextNumber()
	end
	local gunSpots =
		LootRules.pickSpots(cands, loot.floorGuns.count, loot.spots.minSeparation, roll)
	local packSpots =
		LootRules.pickSpots(cands, loot.heal.floorPacks, loot.spots.minSeparation, roll, gunSpots)
	local guns, packs = 0, 0
	for _, spot in gunSpots do
		local gunId = LootRules.pickGun(Config, rng:NextNumber())
		if gunId ~= nil then
			local drop =
				WeaponDrops.spawn(gunId, Vector3.new(spot.x, spot.y or 0, spot.z), matchId, true)
			if drop ~= nil then
				guns += 1
			end
		end
	end
	for _, spot in packSpots do
		if PickupSystem.spawnHeal(Vector3.new(spot.x, spot.y or 0, spot.z)) ~= nil then
			packs += 1
		end
	end
	return guns, packs
end

local function onEliminated(e: any)
	local n = HealPacks.take(e.victimId)
	if n <= 0 or not Config.Loot.heal.dropOnDeath then
		return
	end
	local root = Combatants.root(e.victimId)
	local params = arenaParams()
	if root == nil or params == nil then
		return
	end
	local hit =
		Workspace:Raycast(root.Position, Vector3.new(0, -Config.Loot.spots.rayHeight, 0), params)
	if hit ~= nil then
		PickupSystem.spawnHeal(hit.Position)
	end
end

-- Bots use a pack when they are hurt (same rules as a player: HealPacks.use decides).
local function botSweep()
	local frac = Config.Loot.heal.botUseBelowFraction
	for _, id in HealPacks.carriers() do
		local p = Participants:get(id)
		if p ~= nil and p.kind == "bot" then
			local hp = Combatants.health(id)
			local max = Combatants.book:max_(id)
			if hp ~= nil and max ~= nil and hp <= max * frac then
				HealPacks.use(id)
			end
		end
	end
end

function LootSystem.start()
	Net.onRequest("UseHealRequest", function(player: Player)
		local p = Participants:ofPlayer(player)
		if p ~= nil then
			HealPacks.use(p.id)
		end
	end)

	MatchContext.MatchStarted:connect(function()
		HealPacks.clear()
	end)
	MatchContext.PhaseChanged:connect(function(phase: string, _old: string, matchId: number)
		if phase == "Spawning" then
			HealPacks.clear()
			for _, p in Participants:list() do
				if p.kind == "player" then
					HealPacks.push(p.id, nil) -- everyone starts the match with an empty bag on screen
				end
			end
			LootSystem.spawnFloorLoot(matchId)
		elseif phase == "Resetting" or phase == "Waiting" then
			HealPacks.clear()
		end
	end)
	Damage.Eliminated:connect(onEliminated)

	RunService.Heartbeat:Connect(function(dt: number)
		sinceSweep += dt
		if sinceSweep >= Config.Loot.heal.sweepSeconds then
			sinceSweep = 0
			if MatchContext:isCombat() then
				botSweep()
			end
		end
	end)
end

return LootSystem

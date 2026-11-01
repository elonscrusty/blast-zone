--!strict
-- The Sweep remote. The client only says "I swing"; the server uses its OWN facts: where the
-- character's HumanoidRootPart is, which way it faces (flattened), that the Humanoid is alive,
-- that PlayerState says ready, which zones the profile opened, and how much room the backpack has.
-- All the rules live in Shared/Sweep/SweepRules (tested in Lune); this file only connects them.
--
--   SweepService.init()     once, after AshService.init (Main calls it)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rng = require(Shared.Rng)
local SweepRules = require(Shared.Sweep.SweepRules)
local Types = require(Shared.Types)
local Zones = require(Shared.Catalog.Zones)

local AshService = require(script.Parent.Parent.Ash.AshService)
local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local FX_RANGE = 160 -- studs: other players this close see your puffs
local FULL_TOAST_GAP = 3 -- seconds between "backpack full" messages
local LOCKED_TOAST_GAP = 4 -- seconds between "gate is locked" messages
local LOCKED_CHECK_GAP = 1 -- seconds between looking for locked ash after an empty swing

type Rec = {
	bucket: SweepRules.Bucket,
	allowed: { [number]: boolean }, -- reused every swing
	cleared: { [number]: number }, -- reused every swing
}

local SweepService = {}

local started = false
local rng = Rng.new(math.floor(os.time() * 7 + os.clock() * 1000))
local recs: { [Player]: Rec } = {}
local fullToastAt: { [any]: number } = {}
local lockedToastAt: { [any]: number } = {}
local lockedCheckAt: { [any]: number } = {}
local readyPlayers: { Player } = {} -- ready players, kept up to date by signals (no per-swing list)

local toolScratch = { reach = 0, arcDeg = 0, power = 0 } -- filled per swing; the grid only reads it
local zoneValues: { [number]: number } = {}
for _, z in Zones.list do
	zoneValues[z.id] = z.value
end

-- FindsService is written by another piece. A missing or broken module must never stop sweeping.
type FindsModule = { onCleared: (Player, number, number) -> () }
local finds: FindsModule? = nil
local findsTried = false

local function getFinds(): FindsModule?
	if findsTried then
		return finds
	end
	findsTried = true
	local ok, mod = pcall(function(): any
		local folder = script.Parent.Parent:FindFirstChild("Finds")
		local inst = if folder then folder:FindFirstChild("FindsService") else nil
		if inst == nil then
			error("FindsService not found")
		end
		return require(inst :: any)
	end)
	if ok and type(mod) == "table" and type((mod :: any).onCleared) == "function" then
		finds = mod :: any
	else
		warn("[SweepService] FindsService not available, sweeping without finds")
	end
	return finds
end

local function recOf(player: Player, now: number): Rec
	local rec = recs[player]
	if rec == nil then
		rec = { bucket = SweepRules.newBucket(now), allowed = {}, cleared = {} }
		recs[player] = rec
	end
	return rec :: Rec
end

local function toast(player: Player, text: string, kind: "info" | "good" | "warn" | "gold")
	Net.fire("Toast", player, { text = text, kind = kind } :: Types.ToastInfo)
end

local function removeReady(player: Player)
	local i = table.find(readyPlayers, player)
	if i then
		table.remove(readyPlayers, i)
	end
end

-- Tell other players nearby that a swing happened (for their puffs).
local function broadcastFx(
	player: Player,
	px: number,
	pz: number,
	dx: number,
	dz: number,
	tool: string
)
	if #readyPlayers < 2 then
		return
	end
	local fx: Types.SweepFxInfo = {
		userId = player.UserId,
		x = px,
		z = pz,
		dx = dx,
		dz = dz,
		tool = tool,
	}
	local range2 = FX_RANGE * FX_RANGE
	for _, other in readyPlayers do
		if other ~= player then
			local char = other.Character
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if hrp ~= nil and hrp:IsA("BasePart") then
				local p = hrp.Position
				local ox, oz = p.X - px, p.Z - pz
				if ox * ox + oz * oz <= range2 then
					Net.fire("SweepFx", other, fx)
				end
			end
		end
	end
end

local function onSweep(player: Player)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	-- server-only facts about the character
	local char = player.Character
	if char == nil then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum == nil or hum.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return
	end
	local hrp = root :: BasePart
	local pos = hrp.Position
	local px, pz = pos.X, pos.Z
	if not (SweepRules.isFinite(px) and SweepRules.isFinite(pz)) then
		return
	end
	local look = hrp.CFrame.LookVector
	local dx, dz, hasDir = SweepRules.flattenDir(look.X, look.Y, look.Z)
	if not hasDir then
		return
	end

	local derived = state.derived
	local now = os.clock()

	-- full backpack: no swing at all
	local room = derived.capacity - state.carried
	if room < 1 then
		if SweepRules.allowEvery(fullToastAt, player, now, FULL_TOAST_GAP) then
			toast(player, "Backpack full! Sell at the Trade Hut", "warn")
		end
		return
	end

	-- rate limit: too early = ignored silently
	local rec = recOf(player, now)
	if not SweepRules.allowSwing(rec.bucket, now, derived.interval) then
		return
	end
	state.lastSweepAt = now

	SweepRules.buildAllowed(state.profile.zones, rec.allowed)
	toolScratch.reach = derived.reach
	toolScratch.arcDeg = derived.arcDeg
	toolScratch.power = derived.power
	local grid = AshService.grid
	local result = grid:sweep(
		px,
		pz,
		dx,
		dz,
		toolScratch,
		rec.allowed,
		room,
		rng,
		derived.sweetChance,
		zoneValues
	)

	if result.removedUnits > 0 then
		PlayerState.addCarried(player, result.removedUnits, result.valueUnits)
		PlayerState.addStat(player, "ashSwept", result.removedUnits)
		AshService.noteSwept(result.removedUnits)
		local clearedCount = #result.clearedCells
		if clearedCount > 0 then
			PlayerState.addStat(player, "cleared", clearedCount)
			local mod = getFinds()
			if mod ~= nil then
				SweepRules.countByZone(result.clearedCells, grid.layout.zone, rec.cleared)
				for zoneId, count in rec.cleared do
					if count > 0 then
						local ok, err = pcall(mod.onCleared, player, zoneId, count)
						if not ok then
							warn(`[SweepService] Finds.onCleared failed: {err}`)
						end
					end
				end
			end
		end
	elseif
		not result.full and SweepRules.allowEvery(lockedCheckAt, player, now, LOCKED_CHECK_GAP)
	then
		-- nothing taken: is there ash within reach that this player has not unlocked yet?
		local cells = grid:queryCone(px, pz, dx, dz, derived.reach, derived.arcDeg)
		if
			SweepRules.hasLockedAsh(cells, grid.levels, grid.layout.zone, rec.allowed)
			and SweepRules.allowEvery(lockedToastAt, player, now, LOCKED_TOAST_GAP)
		then
			toast(player, "That gate is locked \u{2014} open it at the gate!", "warn")
		end
	end

	broadcastFx(player, px, pz, dx, dz, state.profile.tool)
end

function SweepService.init()
	if started then
		return
	end
	started = true

	for _, s in PlayerState.all() do
		table.insert(readyPlayers, s.player)
	end
	PlayerState.onReady:connect(function(player: Player)
		if table.find(readyPlayers, player) == nil then
			table.insert(readyPlayers, player)
		end
	end)
	PlayerState.onLeaving:connect(function(player: Player)
		removeReady(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeReady(player)
		recs[player] = nil
		fullToastAt[player] = nil
		lockedToastAt[player] = nil
		lockedCheckAt[player] = nil
	end)

	Net.onRequest("Sweep", onSweep)
end

return SweepService

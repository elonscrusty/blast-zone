--!strict
-- Owns THE ash grid of the island and everything that keeps clients in step with it:
--   AshService.grid                       the shared AshGrid (server is its only writer)
--   AshService.init()                     once, after World.init (Main calls it)
--   AshService.dropAround(x, z, units)    puts lost backpack ash back on the ground nearby; returns
--                                         how many units found room
--   AshService.zoneAt(x, z)               zone id 1..5, or nil outside the rings
--   AshService.noteSwept(units)           report units players AND helper bots removed (adaptive regrow)
--   AshService.flushNow()                 send the pending AshDelta right now (BurpService calls it
--                                         before `Golden`, so a gold cell is never drawn on bare ground)
--
-- What runs (one Heartbeat, three timers; each step is pcall'd so one bad step never stops the rest):
--   10 Hz  AshDelta   dirty cells -> every ready player, chunks of <= 400 pairs, nothing when empty
--   2 s    regrow     units back on the ground (in small piles): scaled by player count, boosted when
--                     a zone is nearly clean, fed by how fast players sweep AND by what their tools
--                     could sweep, capped per player (numbers: ProgressRules, balanced by pacing.test)
--   1 s    Progress   clean fractions when any moved >= 0.005, PlayerState.setClean, and milestone
--                     parties (25/50/75/100% of a zone or of the whole island; at most one party per
--                     ProgressRules.PARTY_COOLDOWN). A party: x2 coins for EVERY ready player for
--                     60 s x the best Spark "Long Buffs" here, and a coin gift for each player who swept
--                     in the last 2 minutes, never more than a party in their own best zone pays.
-- A player gets the full AshSnapshot (and the current Progress) when PlayerState says they are ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AshGrid = require(Shared.Ash.AshGrid)
local BurpGlue = require(Shared.Burp.BurpGlue)
local ProgressRules = require(Shared.Sweep.ProgressRules)
local Rng = require(Shared.Rng)
local SweepRules = require(Shared.Sweep.SweepRules)
local Types = require(Shared.Types)
local Zones = require(Shared.Catalog.Zones)

local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local START_FILL = 0.85 -- the island starts about 85% full of ash
local DELTA_STEP = 0.1 -- seconds between AshDelta batches
local REGROW_STEP = 2
local PROGRESS_STEP = 1
local PARTY_SECONDS = 60
local UNLOCKED_BIAS = 1 -- regrow weight of a zone somebody can sweep ...
local LOCKED_BIAS = 0.2 -- ... and of a zone nobody has opened yet
local DROP_RADII = { 12, 24, 48 } -- studs, tried in order when ash is dropped
local MAX_DROP = 400 -- units one drop may place (sanity)

local ISLAND = ProgressRules.ISLAND

local AshService = {}
AshService.grid = AshGrid.new("full")

local grid = AshService.grid
local layout = grid.layout
local rng = Rng.new(math.floor(os.time() + os.clock() * 1000))
local started = false

local ZONE_IDS: { number } = layout.zoneIds
local ZONE_KEYS: { [number]: string } = {}
for _, id in ZONE_IDS do
	ZONE_KEYS[id] = tostring(id)
end

local tracker = ProgressRules.newTracker()
local current: { [number]: number } = {} -- zone id (and ISLAND) -> clean fraction, rounded
local lastSent: { [number]: number } = {}
local regrowCarry = 0
local sweptSince = 0 -- units players removed since the last regrow step (see noteSwept)
local sweepRate = 0 -- smoothed units per second players remove
local allowedScratch: { [number]: boolean } = {}
local biasScratch: { [number]: number } = {}
local recipients: { Player } = {}

-- ===== helpers =====

local function readyPlayers(): { Player }
	table.clear(recipients)
	for _, s in PlayerState.all() do
		if s.player.Parent == Players then
			table.insert(recipients, s.player)
		end
	end
	return recipients
end

local function computeFractions()
	for _, id in ZONE_IDS do
		current[id] = ProgressRules.round3(grid:zoneClean(id))
	end
	current[ISLAND] = ProgressRules.round3(grid:totalClean())
end

local function progressPayload(): Types.ProgressInfo
	local zones: { [string]: number } = {}
	for _, id in ZONE_IDS do
		zones[ZONE_KEYS[id]] = current[id]
	end
	return { zones = zones, total = current[ISLAND] }
end

-- ===== steps =====

local function flushDelta()
	local flat = grid:takeDirty()
	if #flat == 0 then
		return
	end
	local players = readyPlayers()
	if #players == 0 then
		return -- nobody to tell; whoever joins later gets a full snapshot
	end
	for _, chunk in ProgressRules.chunkDelta(flat, ProgressRules.MAX_PAIRS) do
		Net.fireMany("AshDelta", players, chunk)
	end
end

local function regrowStep(elapsed: number)
	local states = PlayerState.all()
	if #states == 0 then
		return
	end
	-- how fast is the island being cleaned? feeds the adaptive budget (fast sweepers stay fed)
	sweepRate = ProgressRules.smooth(sweepRate, sweptSince / math.max(elapsed, 0.1))
	sweptSince = 0
	local cleanest = 0
	for _, id in ZONE_IDS do
		cleanest = math.max(cleanest, grid:zoneClean(id))
	end
	-- what the kids here COULD sweep (their stats): big tools in an emptied zone get fed
	local pace = 0
	for _, s in states do
		local ok, p = pcall(ProgressRules.pace, s.derived)
		if ok and p == p then
			pace += p
		end
	end
	local whole
	whole, regrowCarry = ProgressRules.regrowBudget(
		#states,
		elapsed,
		regrowCarry,
		grid:totalClean(),
		cleanest,
		sweepRate,
		pace
	)
	if whole <= 0 then
		return
	end
	-- more regrowth where somebody can actually sweep
	for _, id in ZONE_IDS do
		biasScratch[id] = LOCKED_BIAS
	end
	for _, s in states do
		SweepRules.buildAllowed(s.profile.zones, allowedScratch)
		for id, ok in allowedScratch do
			if ok then
				biasScratch[id] = UNLOCKED_BIAS
			end
		end
	end
	grid:regrow(rng, whole, biasScratch)
end

-- The longest party any ready player's Spark "Long Buffs" allows (1 .. BurpGlue.maxBuffMult).
local function partyStretch(): number
	local best = 1
	for _, s in PlayerState.all() do
		local m = s.derived.buffTime
		if type(m) == "number" and m == m and m > best then
			best = m
		end
	end
	return math.min(best, BurpGlue.maxBuffMult)
end

local function celebrate(zone: number, milestone: number)
	local players = readyPlayers()
	if #players == 0 then
		return
	end
	local percent = ProgressRules.percent(milestone)
	local what = "The island"
	local info = Zones.byId[zone]
	if info ~= nil then
		what = info.name
	end
	-- gifts first, each on its own: one odd player can never cancel the party for the others
	local now = os.clock()
	for _, s in PlayerState.all() do
		local ok, err = pcall(function()
			if s.player.Parent ~= Players then
				return
			end
			local text
			if ProgressRules.earnsGift(s.lastSweepAt, now) then
				local gift = ProgressRules.giftFor(zone, BurpGlue.bestZone(s.profile.zones))
				PlayerState.addCoins(s.player, gift)
				text = `Island Party! {what} is {percent}% clean! +{gift} coins!`
			else
				text = `Island Party! {what} is {percent}% clean! Sweep to join the fun!`
			end
			Net.fire("Toast", s.player, { text = text, kind = "gold" } :: Types.ToastInfo)
		end)
		if not ok then
			warn(`[AshService] party gift failed: {err}`)
		end
	end
	Net.fireAll("Party", { milestone = percent, zone = zone } :: Types.PartyInfo)
	local ok, err = pcall(function()
		local seconds = PARTY_SECONDS * partyStretch()
		local endsAt = workspace:GetServerTimeNow() + seconds
		-- a party during a party never shortens it
		if PlayerState.buffLeft("party") < seconds then
			PlayerState.setBuff("party", endsAt)
		end
	end)
	if not ok then
		warn(`[AshService] party buff failed: {err}`)
	end
end

local function progressStep()
	computeFractions()
	PlayerState.setClean(current[ISLAND])
	if ProgressRules.changedEnough(lastSent, current, ProgressRules.PROGRESS_STEP) then
		ProgressRules.copyInto(lastSent, current)
		Net.fireMany("Progress", readyPlayers(), progressPayload())
	end
	-- parties: zones first, then the whole island; the tracker keeps parties PARTY_COOLDOWN apart
	-- (a milestone reached during the cooldown waits for it, it is not lost)
	local now = os.clock()
	for _, id in ZONE_IDS do
		local m = ProgressRules.update(tracker, id, current[id], now)
		if m ~= nil then
			celebrate(id, m)
		end
	end
	local m = ProgressRules.update(tracker, ISLAND, current[ISLAND], now)
	if m ~= nil then
		celebrate(ISLAND, m)
	end
end

local function guarded(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[AshService] {name} failed: {err}`)
	end
end

-- ===== public =====

-- Tell the regrow loop that players just removed `units` of ash (SweepService and the helper bots
-- call this). Only used to measure how fast the island is being cleaned.
function AshService.noteSwept(units: number)
	if units == units and units > 0 and units < 1e6 then
		sweptSince += units
	end
end

function AshService.flushNow()
	guarded("delta", flushDelta)
end

function AshService.zoneAt(x: number, z: number): number?
	return layout.zoneAt(x, z)
end

-- Puts `units` of ash back on cells around (x, z): one unit per cell per pass, widening the circle
-- when the nearby cells are full. Returns how many units were placed.
function AshService.dropAround(x: number, z: number, units: number): number
	if x ~= x or z ~= z or units ~= units or units < 1 then
		return 0
	end
	local left = math.min(math.floor(units), MAX_DROP)
	local placed = 0
	for _, radius in DROP_RADII do
		local cells = layout.cellsInRadius(x, z, radius)
		local put = ProgressRules.spreadDrop(grid, cells, left, rng:int(0, 1000))
		placed += put
		left -= put
		if left <= 0 then
			break
		end
	end
	return placed
end

function AshService.init()
	if started then
		return
	end
	started = true

	-- start about 85% full, with some variety from cell to cell
	for i = 1, grid.N do
		grid:set(i, ProgressRules.startLevel(rng, START_FILL, grid.max))
	end
	grid:takeDirty()
	computeFractions()
	ProgressRules.copyInto(lastSent, current)
	-- the starting state is not a milestone: bring the tracker up to date without a party
	for _, id in ZONE_IDS do
		ProgressRules.update(tracker, id, current[id])
	end
	ProgressRules.update(tracker, ISLAND, current[ISLAND])

	local function welcome(player: Player)
		Net.fire("AshSnapshot", player, grid:encode())
		computeFractions()
		Net.fire("Progress", player, progressPayload())
	end
	PlayerState.onReady:connect(function(player: Player)
		welcome(player)
	end)
	for _, s in PlayerState.all() do
		welcome(s.player)
	end

	local accDelta, accRegrow, accProgress = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		accDelta += dt
		accRegrow += dt
		accProgress += dt
		if accDelta >= DELTA_STEP then
			accDelta = 0
			guarded("delta", flushDelta)
		end
		if accRegrow >= REGROW_STEP then
			local elapsed = accRegrow
			accRegrow = 0
			guarded("regrow", function()
				regrowStep(elapsed)
			end)
		end
		if accProgress >= PROGRESS_STEP then
			accProgress = 0
			guarded("progress", progressStep)
		end
	end)
end

return AshService

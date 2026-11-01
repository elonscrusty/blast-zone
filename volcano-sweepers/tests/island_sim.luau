--!strict
-- A supply-aware island simulation for the balance tests. It runs the REAL shared rules, not a
-- model of them: the AshGrid cone and levels, ProgressRules regrow + parties (with cooldown and
-- gift rules), the BurpDirector (storms scaled by BurpGlue.stormFraction, golden cells, perfect
-- dodge, geysers), FindRoller with its per-player roll budget, helper bots via HelperRules, and
-- StatsCalc / Pricing / Economy for every number. Only the PLAYER is a model:
--   * sweeps non-stop at the tool interval where they stand (the swing goes through AshGrid:sweep);
--   * when nothing is left in reach, walks to the nearest ash of the zone they work in (walking
--     time = distance / walk speed);
--   * when the backpack is full, walks to the Trade Hut, sells, buys, and starts again from the hut;
--   * works in the richest zone they own that still has a fair amount of ash;
--   * buys whatever raises income the most per coin (same policy the old sim used);
--   * dodges most lava bombs (HIT_CHANCE per bomb that lands near them), grabs one gem per geyser
--     wave, never chases golden cells (a real kid does: bonus income the sim does not count).

local AshGrid = require("../src/shared/Ash/AshGrid")
local BurpDirector = require("../src/shared/Burp/BurpDirector")
local BurpGlue = require("../src/shared/Burp/BurpGlue")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Rules/Economy")
local FindRoller = require("../src/shared/Finds/FindRoller")
local Finds = require("../src/shared/Catalog/Finds")
local HelperRules = require("../src/shared/Player/HelperRules")
local Helpers = require("../src/shared/Catalog/Helpers")
local Pricing = require("../src/shared/Rules/Pricing")
local ProgressRules = require("../src/shared/Sweep/ProgressRules")
local Rng = require("../src/shared/Rng")
local StatsCalc = require("../src/shared/Rules/StatsCalc")
local Tools = require("../src/shared/Catalog/Tools")
local Types = require("../src/shared/Types")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")

local Sim = {}

Sim.DT = 0.25 -- world tick
Sim.HIT_CHANCE = 0.15 -- share of nearby landing bombs that hit a careless kid
Sim.SELL_SECONDS = 1.5 -- standing at the counter
Sim.MIN_FILL = 0.12 -- a zone with less ash than this is not worth working in
Sim.REGROW_STEP = 2
Sim.BURP_STEP = 0.5
Sim.PARTY_SECONDS = 60

local L = AshGrid.new("empty").layout
local HUB_X, HUB_Z = L.hubX, L.hubZ
local HUB_ANGLE = math.atan2(HUB_Z, HUB_X)

export type SimPlayer = {
	id: number,
	p: Types.Profile,
	carried: number,
	carriedValue: number,
	x: number,
	z: number,
	dx: number,
	dz: number,
	busyUntil: number, -- walking (or selling) until this time
	selling: boolean, -- the busy time ends at the counter
	swingAt: number,
	zone: number,
	lastSweepAt: number,
	budget: FindRoller.Budget,
	helperCarry: number,
	helperAcc: number,
	times: { [string]: number },
	log: { string },
	income: { [string]: number }, -- coins by source: sell, finds, party, helpers, gems
	handUnits: number,
	spent: { walk: number, trip: number, wait: number, swings: number, empty: number },
	atCoolDown: Types.Profile?,
	done: boolean, -- stopWhen said stop / nothing left to buy
}

export type World = {
	grid: AshGrid.AshGrid,
	rng: Rng.Rng,
	director: BurpDirector.BurpDirector,
	tracker: ProgressRules.Tracker,
	players: { SimPlayer },
	t: number,
	buffs: { [string]: number },
	regrowCarry: number,
	sweptSince: number,
	sweepRate: number,
	parties: number,
	storms: number,
	opts: { storms: boolean, parties: boolean, finds: boolean },
	nextRegrow: number,
	nextBurp: number,
	nextProgress: number,
	stormUnits: number,
	regrowUnits: number,
}

local zoneValues: { [number]: number } = {}
for _, z in Zones.list do
	zoneValues[z.id] = z.value
end

-- ===== analytic income (only to RANK purchases; the run itself uses the real grid) =====

local coneCache: { [string]: number } = {}

-- Mean cells per swing for a tool shape, measured on the real grid (cached).
function Sim.coneCells(reach: number, arcDeg: number): number
	local key = string.format("%.1f/%d", reach, arcDeg)
	local hit = coneCache[key]
	if hit then
		return hit
	end
	local g = AshGrid.new("full")
	local rng = Rng.new(17)
	local total, n = 0, 300
	for _ = 1, n do
		local r = rng:range(196, 244)
		local a = rng:range(0, math.pi * 2)
		local f = rng:range(0, math.pi * 2)
		total += #g:queryCone(
			r * math.cos(a),
			r * math.sin(a),
			math.cos(f),
			math.sin(f),
			reach,
			arcDeg
		)
	end
	coneCache[key] = total / n
	return total / n
end

-- E[min(p, X)] for X uniform on 1..9.
local function perCell(p: number): number
	local total, rem = 0, p
	local seg = math.min(rem, 1)
	total += seg
	rem -= seg
	for k = 1, 8 do
		if rem <= 0 then
			break
		end
		seg = math.min(rem, 1)
		total += seg * (9 - k) / 9
		rem -= seg
	end
	return total
end

-- Units per second while sweeping fresh ash, from the real cone size.
function Sim.handRate(d: StatsCalc.Full): number
	local cells = Sim.coneCells(d.reach, d.arcDeg)
	local s = d.sweetChance
	local per = (1 - s) * perCell(d.power) + s * perCell(d.power * 2)
	if d.melt > 0 then
		per += d.melt / 9 * 0.5
	end
	local powerRate = cells * per / d.interval
	local width = math.max(
		Config.World.cellSize,
		2 * d.reach * math.sin(math.rad(math.min(d.arcDeg, 180) / 2))
	)
	local moveRate = 0.5 * d.walkSpeed * width * (6 / 64)
	return 0.9 / (1 / powerRate + 1 / moveRate)
end

local function bestZoneValue(p: Types.Profile): number
	return Zones.valueOf(BurpGlue.bestZone(p.zones))
end

local function tripFor(p: Types.Profile, d: StatsCalc.Full): number
	-- the hut is about 170 studs from the Lava Heart, 40 from the beach ash
	local best = BurpGlue.bestZone(p.zones)
	local dist = ({ 40, 70, 110, 140, 170 })[best] or 40
	return 2 * dist / d.walkSpeed + Sim.SELL_SECONDS
end

function Sim.income(p: Types.Profile): number
	local d = StatsCalc.compute(p, {}, 0)
	local fill = d.capacity / Sim.handRate(d)
	local sale = d.capacity * bestZoneValue(p) * d.sellMult * (1 + d.luckyChance)
	local bots =
		Helpers.coinsPerSecond(p.helpers, p.helperLevel, bestZoneValue(p), d.sellMult, d.helperMult)
	return sale / (fill + tripFor(p, d)) + bots
end

local function copyProfile(p: Types.Profile): Types.Profile
	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end
	return deep(p)
end
Sim.copyProfile = copyProfile

function Sim.applyBuy(p: Types.Profile, kind: string, id: string | number)
	if kind == "upgrade" then
		p.upgrades[id :: string] = (p.upgrades[id :: string] or 0) + 1
	elseif kind == "tool" then
		p.toolsOwned[id :: string] = true
		local new, cur = Tools.byId[id :: string], Tools.byId[p.tool]
		if new.tier > cur.tier then
			p.tool = new.id
		end
	elseif kind == "zone" then
		p.zones[tostring(id)] = true
	elseif kind == "helper" then
		p.helpers += 1
	elseif kind == "helperUp" then
		p.helperLevel += 1
	elseif kind == "sparkPerk" then
		p.sparkPerks[id :: string] = (p.sparkPerks[id :: string] or 0) + 1
	end
end

type Candidate = { kind: string, id: string | number, price: number, ratio: number }

local function candidates(p: Types.Profile): { Candidate }
	local out: { Candidate } = {}
	local base = Sim.income(p)
	local function consider(kind: string, id: string | number)
		local price = Pricing.priceOf(kind, id, p)
		if price == nil then
			return
		end
		local trial = copyProfile(p)
		Sim.applyBuy(trial, kind, id)
		local gain = Sim.income(trial) - base
		table.insert(
			out,
			{ kind = kind, id = id, price = price, ratio = gain / math.max(1, price) }
		)
	end
	for _, up in Upgrades.list do
		consider("upgrade", up.id)
	end
	for _, tool in Tools.list do
		consider("tool", tool.id)
	end
	for _, zone in Zones.list do
		consider("zone", zone.id)
	end
	consider("helper", 0)
	consider("helperUp", 0)
	return out
end

local function clock(s: number?): string
	if s == nil then
		return "never"
	end
	local m = math.floor(s / 60)
	if m >= 60 then
		return string.format("%dh%02dm", math.floor(m / 60), m % 60)
	end
	return string.format("%d:%02d", m, math.floor(s % 60))
end
Sim.clock = clock

local function mark(sp: SimPlayer, name: string, t: number)
	if sp.times[name] == nil then
		sp.times[name] = t
	end
end

local function earn(sp: SimPlayer, coins: number, source: string)
	if coins <= 0 then
		return
	end
	sp.p.coins += coins
	sp.p.runCoins += coins
	sp.p.lifetimeCoins += coins
	sp.income[source] = (sp.income[source] or 0) + coins
end

local function buyAll(sp: SimPlayer, t: number)
	local p = sp.p
	for _ = 1, 200 do
		local list = candidates(p)
		if #list == 0 then
			sp.done = true
			return
		end
		local best = list[1]
		for _, c in list do
			if c.ratio > best.ratio then
				best = c
			end
		end
		local pick: Candidate? = nil
		if best.price <= p.coins then
			pick = best
		else
			for _, c in list do
				local eager = #sp.log == 0
				if c.price <= p.coins and (eager or c.ratio >= 0.5 * best.ratio) then
					if pick == nil or c.ratio > pick.ratio then
						pick = c
					end
				end
			end
		end
		if pick == nil then
			return
		end
		p.coins -= pick.price
		table.insert(sp.log, `{clock(t)} {pick.kind} {pick.id} for {pick.price}`)
		Sim.applyBuy(p, pick.kind, pick.id)
		if pick.kind == "upgrade" then
			mark(sp, "first_upgrade", t)
		elseif pick.kind == "tool" then
			mark(sp, pick.id :: string, t)
		elseif pick.kind == "zone" then
			mark(sp, "zone_" .. tostring(pick.id), t)
		end
	end
end

-- ===== the world =====

function Sim.newPlayer(id: number, profile: Types.Profile?): SimPlayer
	return {
		id = id,
		p = copyProfile(profile or Economy.blankProfile()),
		carried = 0,
		carriedValue = 0,
		x = HUB_X,
		z = HUB_Z,
		dx = 0,
		dz = -1,
		busyUntil = 0,
		selling = false,
		swingAt = 0,
		zone = 1,
		lastSweepAt = -1e9,
		budget = FindRoller.newBudget(0),
		helperCarry = 0,
		helperAcc = 0,
		times = {},
		log = {},
		income = {},
		handUnits = 0,
		spent = { walk = 0, trip = 0, wait = 0, swings = 0, empty = 0 },
		atCoolDown = nil,
		done = false,
	}
end

function Sim.newWorld(
	players: { SimPlayer },
	seed: number,
	opts: { storms: boolean?, parties: boolean?, finds: boolean? }?
): World
	local o = opts or {}
	local rng = Rng.new(seed)
	local grid = AshGrid.new("full")
	for i = 1, grid.N do
		grid:set(i, ProgressRules.startLevel(rng, 0.85, grid.max))
	end
	grid:takeDirty()
	local tracker = ProgressRules.newTracker()
	for _, id in L.zoneIds do
		ProgressRules.update(tracker, id, ProgressRules.round3(grid:zoneClean(id)))
	end
	ProgressRules.update(tracker, ProgressRules.ISLAND, ProgressRules.round3(grid:totalClean()))
	return {
		grid = grid,
		rng = rng,
		director = BurpDirector.new(Rng.new(seed + 1)),
		tracker = tracker,
		players = players,
		t = 0,
		buffs = {},
		regrowCarry = 0,
		sweptSince = 0,
		sweepRate = 0,
		parties = 0,
		storms = 0,
		opts = {
			storms = o.storms ~= false,
			parties = o.parties ~= false,
			finds = o.finds ~= false,
		},
		nextRegrow = Sim.REGROW_STEP,
		nextBurp = Sim.BURP_STEP,
		nextProgress = 1,
		stormUnits = 0,
		regrowUnits = 0,
	}
end

local function derivedOf(w: World, sp: SimPlayer): StatsCalc.Full
	return StatsCalc.compute(sp.p, w.buffs, w.t)
end

local function allowedOf(p: Types.Profile): { [number]: boolean }
	return HelperRules.allowedZones(p.zones)
end

-- The richest owned zone that still has a fair amount of ash.
local function pickZone(w: World, sp: SimPlayer): number
	local best, bestScore = 1, -1
	for _, z in Zones.list do
		if z.id == 1 or sp.p.zones[tostring(z.id)] == true then
			local cells = L.zoneCount[z.id]
			local fill = w.grid.zoneUnits[z.id] / (cells * w.grid.max)
			local score = z.value * math.min(1, fill / 0.3)
			if fill < Sim.MIN_FILL then
				score *= 0.05
			end
			if score > bestScore then
				best, bestScore = z.id, score
			end
		end
	end
	return best
end

-- Mean distance from the island centre of each zone's cells: where a kid's "own patch" lies.
local zoneRadius: { [number]: number } = {}
for _, id in L.zoneIds do
	local sum = 0
	for _, j in L.zoneCells[id] do
		sum += math.sqrt(L.cx[j] * L.cx[j] + L.cz[j] * L.cz[j])
	end
	zoneRadius[id] = sum / math.max(1, #L.zoneCells[id])
end

-- Walk to the nearest cell with ash in the zone being worked. Returns false if the zone is bare.
-- Leaving the hut (`fromHut`), each kid heads for their own patch of the ring (spread by id) instead
-- of the same nearest pile (patches fan out on the hut's side): real friends spread out, they do not queue behind each other.
local function walkToAsh(w: World, sp: SimPlayer, d: StatsCalc.Full, fromHut: boolean?): boolean
	local grid = w.grid
	local levels, zoneOf = grid.levels, L.zone
	local target = 0
	local ox, oz = sp.x, sp.z
	if fromHut and #w.players > 1 then
		-- patches fan out over about 80 degrees on the hut's side of the ring
		local spread = (sp.id - 1) / (#w.players - 1) - 0.5
		local angle = HUB_ANGLE + 1.4 * spread + w.rng:range(-0.15, 0.15)
		local r = zoneRadius[sp.zone] or 0
		ox, oz = r * math.cos(angle), r * math.sin(angle)
	end
	for _, radius in { 20, 48, 110 } do
		local bestD2 = math.huge
		for _, j in L.cellsInRadius(ox, oz, radius) do
			if levels[j] > 0 and zoneOf[j] == sp.zone then
				local ddx, ddz = L.cx[j] - ox, L.cz[j] - oz
				local d2 = ddx * ddx + ddz * ddz
				if d2 < bestD2 and d2 > 1 then
					bestD2, target = d2, j
				end
			end
		end
		if target ~= 0 then
			break
		end
	end
	if target == 0 then
		local list = L.zoneCells[sp.zone]
		for _ = 1, 60 do
			local j = list[w.rng:int(1, #list)]
			if levels[j] > 0 then
				target = j
				break
			end
		end
	end
	if target == 0 then
		return false
	end
	local tx, tz = L.cx[target], L.cz[target]
	local ddx, ddz = tx - sp.x, tz - sp.z
	local dist = math.sqrt(ddx * ddx + ddz * ddz)
	if dist > 1e-6 then
		sp.dx, sp.dz = ddx / dist, ddz / dist
	end
	-- stop a little before the cell so the fan covers it and what lies beyond
	local stop = math.max(0, dist - math.min(d.reach * 0.5, 4))
	sp.x += sp.dx * stop
	sp.z += sp.dz * stop
	sp.busyUntil = w.t + stop / d.walkSpeed
	sp.spent.walk += stop / d.walkSpeed
	return true
end

local function startTrip(w: World, sp: SimPlayer, d: StatsCalc.Full)
	local ddx, ddz = HUB_X - sp.x, HUB_Z - sp.z
	local dist = math.sqrt(ddx * ddx + ddz * ddz)
	sp.busyUntil = w.t + dist / d.walkSpeed + Sim.SELL_SECONDS
	sp.spent.trip += dist / d.walkSpeed + Sim.SELL_SECONDS
	sp.selling = true
	sp.x, sp.z = HUB_X, HUB_Z
end

local function finishSale(w: World, sp: SimPlayer, stopWhen: ((Types.Profile) -> boolean)?)
	sp.selling = false
	local d = derivedOf(w, sp)
	local coins, _, _ = Economy.sellValue(sp.carriedValue, d, w.rng)
	sp.carried, sp.carriedValue = 0, 0
	earn(sp, coins, "sell")
	mark(sp, "first_sale", w.t)
	if sp.atCoolDown == nil and Economy.canCoolDown(sp.p) then
		mark(sp, "cool_down", w.t)
		sp.atCoolDown = copyProfile(sp.p)
	end
	buyAll(sp, w.t)
	if stopWhen and stopWhen(sp.p) then
		sp.done = true
	end
	sp.zone = pickZone(w, sp)
end

local function rollFinds(w: World, sp: SimPlayer, d: StatsCalc.Full, cleared: { number })
	if not w.opts.finds or #cleared == 0 then
		return
	end
	local rolls = FindRoller.takeRolls(sp.budget, w.t, BurpGlue.rollCount(#cleared))
	local luck = BurpGlue.luckBonus(d.luck)
	for k = 1, rolls do
		local zoneId = L.zone[cleared[k]]
		local found = FindRoller.roll(w.rng, luck, zoneId, Finds.list :: any, Finds.rarities :: any)
		local def = if found ~= nil then Finds.byId[found.id] else nil
		if def ~= nil then
			BurpGlue.recordFind(sp.p.finds, def.id)
			earn(sp, BurpGlue.findCoins(def.coins, d.sellMult), "finds")
			local set = Finds.setById[def.set]
			if set and not sp.p.setsClaimed[set.id] then
				local all = true
				for _, f in Finds.inSet(set.id) do
					if (sp.p.finds[f.id] or 0) <= 0 then
						all = false
						break
					end
				end
				if all then
					sp.p.setsClaimed[set.id] = true
					mark(sp, "set_" .. set.id, w.t)
				end
			end
		end
	end
end

local function swing(w: World, sp: SimPlayer, d: StatsCalc.Full)
	local room = d.capacity - sp.carried
	local res = w.grid:sweep(
		sp.x,
		sp.z,
		sp.dx,
		sp.dz,
		{ reach = d.reach, arcDeg = d.arcDeg, power = d.power, melt = d.melt },
		allowedOf(sp.p),
		room,
		w.rng,
		d.sweetChance,
		zoneValues
	)
	sp.spent.swings += 1
	if res.removedUnits <= 0 then
		sp.spent.empty += 1
	end
	if res.removedUnits > 0 then
		sp.carried += res.removedUnits
		sp.carriedValue += res.valueUnits
		sp.handUnits += res.removedUnits
		sp.lastSweepAt = w.t
		w.sweptSince += res.removedUnits
		rollFinds(w, sp, d, res.clearedCells)
	end
	if sp.carried >= d.capacity - 0.5 then
		startTrip(w, sp, d)
	elseif res.removedUnits == 0 then
		if not walkToAsh(w, sp, d) then
			sp.zone = pickZone(w, sp)
			if not walkToAsh(w, sp, d) then
				if sp.carried > 0 then
					startTrip(w, sp, d)
				else
					sp.busyUntil = w.t + 2 -- nothing anywhere: wait for regrow
					sp.spent.wait += 2
				end
			end
		end
	end
end

local function stepPlayer(w: World, sp: SimPlayer, stopWhen: ((Types.Profile) -> boolean)?)
	if sp.done then
		return
	end
	local d = derivedOf(w, sp)
	-- helper bots: once a second, around the owner, coins straight to the owner
	if sp.p.helpers > 0 then
		sp.helperAcc += Sim.DT
		if sp.helperAcc >= 1 then
			local elapsed = sp.helperAcc
			sp.helperAcc = 0
			local whole, carry =
				HelperRules.accrue(sp.helperCarry, sp.p.helperLevel, elapsed * sp.p.helpers)
			sp.helperCarry = carry
			if whole > 0 then
				local r = HelperRules.sweepAround(w.grid, sp.x, sp.z, whole, allowedOf(sp.p), w.rng)
				w.sweptSince += r.units
				earn(sp, HelperRules.coinsFor(r.valueUnits, d.helperMult, d.sellMult), "helpers")
			end
		end
	end
	if w.t < sp.busyUntil then
		return
	end
	if sp.selling then
		finishSale(w, sp, stopWhen)
		if sp.done then
			return
		end
		d = derivedOf(w, sp)
		sp.swingAt = w.t
		if not walkToAsh(w, sp, d, true) then
			sp.busyUntil = w.t + 1
			sp.spent.wait += 1
		end
		return
	end
	local guard = 0
	while sp.swingAt <= w.t and w.t >= sp.busyUntil and not sp.selling and guard < 8 do
		guard += 1
		sp.swingAt += d.interval
		swing(w, sp, d)
	end
	if sp.swingAt < w.t - 1 then
		sp.swingAt = w.t -- walking: no swings piled up for later
	end
end

local function partyNow(w: World, zone: number)
	w.parties += 1
	local stretch = 1
	for _, sp in w.players do
		stretch = math.max(stretch, StatsCalc.compute(sp.p, {}, 0).buffTime)
	end
	local endsAt = w.t + Sim.PARTY_SECONDS * math.min(stretch, BurpGlue.maxBuffMult)
	w.buffs.party = math.max(w.buffs.party or 0, endsAt)
	for _, sp in w.players do
		if ProgressRules.earnsGift(sp.lastSweepAt, w.t) then
			earn(sp, ProgressRules.giftFor(zone, BurpGlue.bestZone(sp.p.zones)), "party")
		end
	end
end

local function worldStep(w: World)
	local grid = w.grid
	-- burps
	if w.t >= w.nextBurp then
		w.nextBurp += Sim.BURP_STEP
		local positions = {}
		for _, sp in w.players do
			table.insert(
				positions,
				{ userId = sp.id, x = sp.x, z = sp.z, zone = BurpGlue.zoneOf(sp.x, sp.z) }
			)
		end
		local events = w.director:step(w.t, {
			playerPositions = positions,
			cleanTotal = grid:totalClean(),
			playerCount = #w.players,
		})
		for _, e in events do
			if e.kind == "rain" and w.opts.storms then
				local before = grid.totalUnits
				grid:rain(w.rng, BurpGlue.stormFraction(e.fraction :: number, #w.players))
				w.stormUnits += grid.totalUnits - before
				w.storms += 1
			elseif e.kind == "golden" then
				local share = BurpGlue.goldenShare(e.cells :: number, #w.players)
				for i, sp in w.players do
					grid:spawnGolden(w.rng, share[i], { [BurpGlue.bestZone(sp.p.zones)] = true })
				end
				w.buffs.golden = e.untilAt :: number
			elseif e.kind == "land" then
				for _, sp in w.players do
					if
						not BurpGlue.inHub(sp.x, sp.z)
						and w.rng:chance(Sim.HIT_CHANCE / math.max(1, #w.players))
					then
						local d = derivedOf(w, sp)
						local frac = BurpGlue.dropFraction(d.armor)
						local lost = math.floor(sp.carried * frac)
						if lost > 0 then
							sp.carriedValue *= (sp.carried - lost) / sp.carried
							sp.carried -= lost
						end
						w.director:reportHit(sp.id, w.t)
					end
				end
			elseif e.kind == "perfect" then
				w.buffs.perfect = e.untilAt :: number
			elseif e.kind == "geysers" then
				for _, sp in w.players do
					local d = derivedOf(w, sp)
					local best = BurpGlue.bestZone(sp.p.zones)
					local coins =
						BurpGlue.geyserCoins(best, sp.p.zones, Finds.rarityById.common.coinMult)
					earn(sp, BurpGlue.findCoins(coins, d.sellMult), "gems")
				end
			end
		end
		if w.buffs.golden and w.t >= w.buffs.golden then
			grid:clearGolden()
			w.buffs.golden = nil
		end
	end
	-- regrow
	if w.t >= w.nextRegrow then
		w.nextRegrow += Sim.REGROW_STEP
		w.sweepRate = ProgressRules.smooth(w.sweepRate, w.sweptSince / Sim.REGROW_STEP)
		w.sweptSince = 0
		local cleanest = 0
		for _, id in L.zoneIds do
			cleanest = math.max(cleanest, grid:zoneClean(id))
		end
		local pace = 0
		for _, sp in w.players do
			pace += ProgressRules.pace(derivedOf(w, sp))
		end
		local whole
		whole, w.regrowCarry = ProgressRules.regrowBudget(
			#w.players,
			Sim.REGROW_STEP,
			w.regrowCarry,
			grid:totalClean(),
			cleanest,
			w.sweepRate,
			pace
		)
		if whole > 0 then
			local bias: { [number]: number } = {}
			for _, id in L.zoneIds do
				bias[id] = 0.2
			end
			for _, sp in w.players do
				for id, ok in allowedOf(sp.p) do
					if ok then
						bias[id] = 1
					end
				end
			end
			w.regrowUnits += grid:regrow(w.rng, whole, bias)
		end
	end
	-- parties
	if w.t >= w.nextProgress then
		w.nextProgress += 1
		if w.opts.parties then
			for _, id in L.zoneIds do
				local m = ProgressRules.update(
					w.tracker,
					id,
					ProgressRules.round3(grid:zoneClean(id)),
					w.t
				)
				if m ~= nil then
					partyNow(w, id)
				end
			end
			local m = ProgressRules.update(
				w.tracker,
				ProgressRules.ISLAND,
				ProgressRules.round3(grid:totalClean()),
				w.t
			)
			if m ~= nil then
				partyNow(w, ProgressRules.ISLAND)
			end
		end
	end
end

-- Runs until `seconds` of sim time passed or every player is done.
function Sim.run(w: World, seconds: number, stopWhen: ((Types.Profile) -> boolean)?)
	local stopAt = w.t + seconds
	while w.t < stopAt do
		w.t += Sim.DT
		worldStep(w)
		local anyLeft = false
		for _, sp in w.players do
			stepPlayer(w, sp, stopWhen)
			if not sp.done then
				anyLeft = true
			end
		end
		if not anyLeft then
			break
		end
	end
end

return Sim

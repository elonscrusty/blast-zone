--!strict
-- The bench rules (video 3 gap 14). Pure functions on a saved State, so Lune tests them and the server only
-- connects them to the profile. Every function that changes a State returns ok, reason? and changes nothing
-- when ok is false.
--
-- State (saved in data.bench of the profile):
--   parts: { ["bolt_1"] = 3, ... }   how many of each kind + tier
--   built: { ["spark_cap"] = true }  gear that was built (looks only)
--   merges, builds: counters for the player's own card

local BenchDefs = require("./BenchDefs")

export type State = {
	parts: { [string]: number },
	built: { [string]: boolean },
	merges: number,
	builds: number,
}

local BenchRules = {}

BenchRules.MAX_PILE = 9999 -- more than this of one part is dropped, so a number can never grow forever

function BenchRules.empty(): State
	return { parts = {}, built = {}, merges = 0, builds = 0 }
end

local function count(state: State, kind: string, tier: number): number
	return state.parts[BenchDefs.partKey(kind, tier)] or 0
end
BenchRules.count = count

-- Repairs a State read from a profile: unknown ids are KEPT (an item removed later must not erase a save),
-- but anything that is not a whole, positive number is dropped.
function BenchRules.fill(raw: any): State
	local s = BenchRules.empty()
	if type(raw) ~= "table" then
		return s
	end
	if type(raw.parts) == "table" then
		for key, n in raw.parts do
			if
				type(key) == "string"
				and type(n) == "number"
				and n == n
				and n >= 1
				and n <= BenchRules.MAX_PILE
			then
				s.parts[key] = math.floor(n)
			end
		end
	end
	if type(raw.built) == "table" then
		for id, v in raw.built do
			if type(id) == "string" and v == true then
				s.built[id] = true
			end
		end
	end
	s.merges = if type(raw.merges) == "number" and raw.merges >= 0
		then math.floor(raw.merges)
		else 0
	s.builds = if type(raw.builds) == "number" and raw.builds >= 0
		then math.floor(raw.builds)
		else 0
	return s
end

local function setCount(state: State, kind: string, tier: number, n: number)
	local key = BenchDefs.partKey(kind, tier)
	if n <= 0 then
		state.parts[key] = nil
	else
		state.parts[key] = math.min(n, BenchRules.MAX_PILE)
	end
end

function BenchRules.add(state: State, kind: string, tier: number, n: number): boolean
	if BenchDefs.kind(kind) == nil or not BenchDefs.isTier(tier) or n < 1 or n ~= math.floor(n) then
		return false
	end
	setCount(state, kind, tier, count(state, kind, tier) + n)
	return true
end

-- Three of the same part make one of the next tier. Prime parts do not merge.
function BenchRules.canMerge(state: State, kind: any, tier: any): (boolean, string?)
	if BenchDefs.kind(kind) == nil or not BenchDefs.isTier(tier) then
		return false, "badPart"
	end
	if tier >= BenchDefs.maxTier then
		return false, "maxTier"
	end
	if count(state, kind, tier) < BenchDefs.mergeCount then
		return false, "notEnough"
	end
	return true, nil
end

function BenchRules.merge(state: State, kind: any, tier: any): (boolean, string?)
	local ok, reason = BenchRules.canMerge(state, kind, tier)
	if not ok then
		return false, reason
	end
	setCount(state, kind, tier, count(state, kind, tier) - BenchDefs.mergeCount)
	setCount(state, kind, tier + 1, count(state, kind, tier + 1) + 1)
	state.merges += 1
	return true, nil
end

-- How many of this part a merge-everything would turn into the next tier (for the MERGE ALL button).
function BenchRules.mergesAvailable(state: State, kind: string, tier: number): number
	if tier >= BenchDefs.maxTier then
		return 0
	end
	return count(state, kind, tier) // BenchDefs.mergeCount
end

function BenchRules.canBuild(state: State, blueprintId: any): (boolean, string?)
	local bp = BenchDefs.blueprint(blueprintId)
	if bp == nil then
		return false, "badBlueprint"
	end
	if state.built[bp.id] then
		return false, "alreadyBuilt"
	end
	for _, need in bp.needs do
		if count(state, need.kind, need.tier) < need.count then
			return false, "notEnough"
		end
	end
	return true, nil
end

function BenchRules.build(state: State, blueprintId: any): (boolean, string?)
	local ok, reason = BenchRules.canBuild(state, blueprintId)
	if not ok then
		return false, reason
	end
	local bp = BenchDefs.blueprint(blueprintId) :: BenchDefs.Blueprint
	for _, need in bp.needs do
		setCount(state, need.kind, need.tier, count(state, need.kind, need.tier) - need.count)
	end
	state.built[bp.id] = true
	state.builds += 1
	return true, nil
end

-- ===== drops =====

-- How many parts a finished match pays. `table` is Config.Bench.drops ({ win, podium, middle, other }).
function BenchRules.dropCount(
	place: number,
	won: boolean?,
	drops: { [string]: number },
	fieldSize: number?
): number
	if won == true then
		return drops.win
	end
	if place >= 1 and place <= 3 then
		return drops.podium
	end
	local half = math.ceil((fieldSize or 8) / 2)
	if place >= 1 and place <= half then
		return drops.middle
	end
	return drops.other
end

export type Drop = { kind: string, tier: number }

-- Picks `n` parts at random. `rng` returns a whole number 1..max, so tests can pick the numbers.
-- Every part comes in at tier 1, and every kind has the same chance.
function BenchRules.roll(n: number, rng: (max: number) -> number): { Drop }
	local out: { Drop } = {}
	for _ = 1, n do
		local i = rng(#BenchDefs.kinds)
		local kind = BenchDefs.kinds[math.clamp(i, 1, #BenchDefs.kinds)]
		table.insert(out, { kind = kind.id, tier = 1 })
	end
	return out
end

function BenchRules.addDrops(state: State, drops: { Drop })
	for _, d in drops do
		BenchRules.add(state, d.kind, d.tier, 1)
	end
end

-- ===== what the screen needs =====

export type PartView = { kind: string, tier: number, count: number, canMerge: boolean }
export type NeedView = { kind: string, tier: number, count: number, have: number }
export type BlueprintView = {
	id: string,
	name: string,
	slot: string,
	needs: { NeedView },
	built: boolean,
	ready: boolean,
}
export type View = {
	parts: { PartView },
	blueprints: { BlueprintView },
	built: number,
	total: number,
}

-- Every pile that has something in it (kind order, then tier), and every blueprint with how close it is.
function BenchRules.view(state: State): View
	local parts: { PartView } = {}
	for _, k in BenchDefs.kinds do
		for t = 1, BenchDefs.maxTier do
			local n = count(state, k.id, t)
			if n > 0 then
				table.insert(parts, {
					kind = k.id,
					tier = t,
					count = n,
					canMerge = (BenchRules.canMerge(state, k.id, t)),
				})
			end
		end
	end
	local blueprints: { BlueprintView } = {}
	local built = 0
	for _, bp in BenchDefs.blueprints do
		local needs: { NeedView } = {}
		for _, need in bp.needs do
			table.insert(needs, {
				kind = need.kind,
				tier = need.tier,
				count = need.count,
				have = count(state, need.kind, need.tier),
			})
		end
		local isBuilt = state.built[bp.id] == true
		if isBuilt then
			built += 1
		end
		table.insert(blueprints, {
			id = bp.id,
			name = bp.name,
			slot = bp.slot,
			needs = needs,
			built = isBuilt,
			ready = (BenchRules.canBuild(state, bp.id)),
		})
	end
	return { parts = parts, blueprints = blueprints, built = built, total = #BenchDefs.blueprints }
end

return BenchRules

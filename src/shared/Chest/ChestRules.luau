--!strict
-- Pure rules for chests (gap 19). The saved table is data.chests next to data.progression in the profile:
--   owned   chests waiting to be opened, by kind
--   meter   finished matches counted toward the next free Street Chest
--   opened  chests opened so far
-- Earning and opening are server only. Every function checks first and only then changes anything, and
-- returns a reason when it refuses, leaving the data as it was. Pure Luau so Lune tests it.

local ChestDefs = require("./ChestDefs")
local ProgressRules = require("../Progression/ProgressRules")
local TrackDefs = require("../Progression/TrackDefs")

local ChestRules = {}

export type State = {
	owned: { [string]: number },
	meter: number,
	opened: number,
}

export type Prize = {
	rowId: string,
	kind: string, -- "scrap" | "look"
	rarity: string,
	name: string, -- "Scrap" or the look's name
	amount: number?, -- Scrap given (also the Scrap a repeated look turned into)
	itemId: string?, -- the look
	dupe: boolean, -- true = you already had this look, so you got Scrap instead
}

export type OpenResult = {
	ok: boolean,
	reason: string?,
	kind: string,
	prizes: { Prize },
}

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < 1e9 and n == math.floor(n)
end

function ChestRules.new(): State
	return { owned = {}, meter = 0, opened = 0 }
end

-- Fills in anything missing or the wrong type, in place. Unknown chest kinds are kept (a newer game may own them).
function ChestRules.fill(raw: any): State
	local s = raw :: any
	if type(s.owned) ~= "table" then
		s.owned = {}
	end
	for kind, n in s.owned do
		if not isCount(n) then
			s.owned[kind] = 0
		end
	end
	if not isCount(s.meter) then
		s.meter = 0
	end
	if not isCount(s.opened) then
		s.opened = 0
	end
	return s :: State
end

function ChestRules.count(state: State, kind: string): number
	return state.owned[kind] or 0
end

function ChestRules.total(state: State): number
	local n = 0
	for _, kind in ChestDefs.kinds do
		n += ChestRules.count(state, kind)
	end
	return n
end

-- Gives one chest. Refused for an unknown kind or when the player already holds `maxStored` of that kind.
function ChestRules.award(state: State, kind: string, maxStored: number): (boolean, string?)
	if ChestDefs.get(kind) == nil then
		return false, "badKind"
	end
	if ChestRules.count(state, kind) >= maxStored then
		return false, "full"
	end
	state.owned[kind] = ChestRules.count(state, kind) + 1
	return true, nil
end

-- A finished match: first place gives a Neon Chest, top 3 a Street Chest, and every `meterGoal`th match a
-- Street Chest as well (so a bad day still pays). Returns the kinds given, in order. A full kind is skipped
-- and the meter waits at its goal until there is room.
function ChestRules.forMatch(
	state: State,
	place: number,
	won: boolean,
	meterGoal: number,
	maxStored: number
): { string }
	local given: { string } = {}
	if won then
		if ChestRules.award(state, "neon", maxStored) then
			table.insert(given, "neon")
		end
	elseif place >= 1 and place <= 3 then
		if ChestRules.award(state, "street", maxStored) then
			table.insert(given, "street")
		end
	end
	state.meter = math.min(state.meter + 1, meterGoal)
	if state.meter >= meterGoal and ChestRules.award(state, "street", maxStored) then
		state.meter = 0
		table.insert(given, "street")
	end
	return given
end

-- One weighted pick. `rng` returns a number from 0 up to (not including) 1.
function ChestRules.pick(chest: ChestDefs.Chest, rng: () -> number): ChestDefs.Row
	local total = 0
	for _, row in chest.rows do
		total += row.weight
	end
	local roll = math.clamp(rng(), 0, 0.999999) * total
	for _, row in chest.rows do
		roll -= row.weight
		if roll < 0 then
			return row
		end
	end
	return chest.rows[#chest.rows]
end

local function nameOf(row: ChestDefs.Row): string
	if row.kind == "look" and row.itemId ~= nil then
		local def = TrackDefs.get(row.itemId)
		if def ~= nil then
			return def.name
		end
	end
	return "Scrap"
end

-- Opens one chest of `kind`: takes the chest, rolls the prizes and pays them, in one change. `data` is the
-- whole profile data ({ chests, progression }). All or nothing: any refusal leaves `data` untouched.
function ChestRules.open(
	data: { [string]: any },
	kind: any,
	rng: () -> number,
	maxGrant: number
): OpenResult
	local function refuse(reason: string): OpenResult
		return {
			ok = false,
			reason = reason,
			kind = if type(kind) == "string" then kind else "",
			prizes = {},
		}
	end
	local chest = ChestDefs.get(kind)
	if chest == nil then
		return refuse("badKind")
	end
	if type(data.chests) ~= "table" then
		data.chests = {}
	end
	if type(data.progression) ~= "table" then
		data.progression = {}
	end
	local state = ChestRules.fill(data.chests)
	local p = ProgressRules.fill(data.progression)
	if ChestRules.count(state, chest.id) < 1 then
		return refuse("none")
	end

	-- Work on a scratch copy of the money and looks; write it back only when every prize went through.
	local scratch: ProgressRules.Progression = {
		coins = p.coins,
		totalEarned = p.totalEarned,
		unlocked = table.clone(p.unlocked),
		equipped = p.equipped,
		grantedKeys = p.grantedKeys,
		accountXp = p.accountXp,
		claimedLevels = p.claimedLevels,
	}
	local prizes: { Prize } = {}
	for _ = 1, chest.items do
		local row = ChestRules.pick(chest, rng)
		local prize: Prize = {
			rowId = row.id,
			kind = row.kind,
			rarity = row.rarity,
			name = nameOf(row),
			amount = nil,
			itemId = row.itemId,
			dupe = false,
		}
		local scrapAmount: number? = nil
		if row.kind == "look" and row.itemId ~= nil and TrackDefs.get(row.itemId) ~= nil then
			if ProgressRules.owns(scratch, row.itemId) then
				prize.dupe = true
				prize.kind = "scrap"
				scrapAmount = ChestDefs.dupeScrap[row.rarity]
			else
				scratch.unlocked[row.itemId] = true
			end
		else
			scrapAmount = row.amount or 0
			prize.kind = "scrap"
		end
		if scrapAmount ~= nil then
			local paid = ProgressRules.addCoins(scratch, scrapAmount, maxGrant)
			if not paid.ok then
				return refuse(paid.reason or "full")
			end
			prize.amount = scrapAmount
		end
		table.insert(prizes, prize)
	end

	p.coins = scratch.coins
	p.totalEarned = scratch.totalEarned
	p.unlocked = scratch.unlocked
	state.owned[chest.id] = ChestRules.count(state, chest.id) - 1
	state.opened += 1
	return { ok = true, reason = nil, kind = chest.id, prizes = prizes }
end

return ChestRules

--!strict
-- The upgrade catalogue and its maths (piece 08). Pure: no Roblox calls, so Lune tests it.
--
-- Effective stats are ALWAYS computed from the base sheet plus the stack counts, in one fixed order:
--   value = (base + sum of add) * (1 + sum of pct) * product of (mult ^ stacks), then limits.
-- That makes the result independent of the order upgrades were picked, and a reset is just
-- "clear the stacks". Nothing here ever multiplies a running value.
--
-- Groups: "firearm" and "explosive" are the two weapon blocks of the StatSheet, "self" is the
-- sheet's top-level fields (moveSpeed, slideCooldown, ...). An upgrade whose groups are not in
-- the player's build (the explosive group while the mortar is off) is never offered.
-- `icon` is only a name that the card art maps; no asset ids are made up here.

local Config = require("./Config")
local Types = require("./Types")

export type Sheet = Types.StatSheet
export type Option = Types.UpgradeOption

export type Op = "add" | "pct" | "mult"

export type Effect = {
	groups: { string }, -- "firearm" | "explosive" | "self"
	stat: string, -- field name inside the group
	op: Op,
	value: number, -- add: +value. pct: +value as a fraction. mult: value ^ stacks.
}

export type Upgrade = {
	id: string,
	name: string,
	description: string,
	feedback: string, -- what the player should see change (for the card art / effects)
	icon: string,
	kind: string, -- "weapon" or "move": picks the card accent
	maxStacks: number,
	weight: number, -- selection weight; higher shows up more often
	effects: { Effect },
	requires: { [string]: number }?, -- upgrade id -> stacks needed first
	incompatible: { string }?, -- cannot be offered once any of these is owned (and vice versa)
}

export type Limit = {
	min: number?,
	max: number?,
	minRatio: number?, -- of the base value
	maxRatio: number?,
}

export type Stacks = { [string]: number }

-- What the maths needs to know about the player's build.
export type Ctx = {
	base: Sheet, -- the unupgraded sheet (StatBook.base(Config))
	hasExplosive: boolean,
	weaponNames: { firearm: string, explosive: string }?,
}

local UpgradeDefs = {}

local EPSILON = 1e-9

local list: { Upgrade } = {
	{
		id = "quick_hands",
		name = "Quick Hands",
		description = "Reload takes 20% less time.",
		feedback = "The reload bar fills faster.",
		icon = "reload",
		kind = "weapon",
		maxStacks = 3,
		weight = 10,
		effects = {
			{
				groups = { "firearm", "explosive" },
				stat = "reloadSeconds",
				op = "mult",
				value = 0.8,
			},
		},
	},
	{
		id = "slick_soles",
		name = "Slick Soles",
		description = "Slide comes back 1 second sooner.",
		feedback = "The slide ring refills sooner.",
		icon = "slide",
		kind = "move",
		maxStacks = 3,
		weight = 8,
		effects = { { groups = { "self" }, stat = "slideCooldown", op = "add", value = -1 } },
	},
	{
		id = "light_feet",
		name = "Light Feet",
		description = "Run 8% faster.",
		feedback = "Your trail stretches out a little.",
		icon = "feet",
		kind = "move",
		maxStacks = 3,
		weight = 8,
		effects = { { groups = { "self" }, stat = "moveSpeed", op = "pct", value = 0.08 } },
	},
	{
		id = "twin_shot",
		name = "Twin Shot",
		description = "Fire 1 more bullet. Each hits 30% softer and sprays wider.",
		feedback = "Two tracers leave the gun.",
		icon = "twin",
		kind = "weapon",
		maxStacks = 1,
		weight = 7,
		effects = {
			{ groups = { "firearm" }, stat = "pellets", op = "add", value = 1 },
			{ groups = { "firearm" }, stat = "damage", op = "mult", value = 0.7 },
			{ groups = { "firearm" }, stat = "spreadDegrees", op = "add", value = 4 },
		},
	},
	{
		id = "fan_fire",
		name = "Fan Fire",
		description = "Fire 1 more bullet in a wide fan. Each hits 15% softer.",
		feedback = "Three tracers fan out.",
		icon = "fan",
		kind = "weapon",
		maxStacks = 1,
		weight = 5,
		effects = {
			{ groups = { "firearm" }, stat = "pellets", op = "add", value = 1 },
			{ groups = { "firearm" }, stat = "damage", op = "mult", value = 0.85 },
			{ groups = { "firearm" }, stat = "spreadDegrees", op = "add", value = 6 },
		},
		requires = { twin_shot = 1 },
		incompatible = { "steady_aim" },
	},
	{
		id = "steady_aim",
		name = "Steady Aim",
		description = "Bullets spread half as much.",
		feedback = "The aim cone gets tighter.",
		icon = "steady",
		kind = "weapon",
		maxStacks = 1,
		weight = 6,
		effects = { { groups = { "firearm" }, stat = "spreadDegrees", op = "mult", value = 0.5 } },
		incompatible = { "fan_fire" },
	},
	{
		id = "long_sight",
		name = "Long Sight",
		description = "Shots reach 20% farther.",
		feedback = "Tracers fly farther before they fade.",
		icon = "range",
		kind = "weapon",
		maxStacks = 3,
		weight = 7,
		effects = {
			{ groups = { "firearm", "explosive" }, stat = "range", op = "pct", value = 0.2 },
		},
	},
	{
		id = "bigger_boom",
		name = "Bigger Boom",
		description = "Blasts are 25% wider.",
		feedback = "The landing circle grows.",
		icon = "boom",
		kind = "weapon",
		maxStacks = 3,
		weight = 8,
		effects = { { groups = { "explosive" }, stat = "radius", op = "pct", value = 0.25 } },
	},
	{
		id = "hard_rounds",
		name = "Hard Rounds",
		description = "Hit 15% harder.",
		feedback = "Hit numbers get bigger.",
		icon = "damage",
		kind = "weapon",
		maxStacks = 4,
		weight = 9,
		effects = {
			{ groups = { "firearm", "explosive" }, stat = "damage", op = "pct", value = 0.15 },
		},
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	byId[upgrade.id] = upgrade
end

UpgradeDefs.list = list
UpgradeDefs.byId = byId

-- Hard limits behind maxStacks: no build can leave these. Keys are "group.stat".
UpgradeDefs.limits = {
	["firearm.damage"] = { minRatio = 0.25, maxRatio = 1.75 },
	["firearm.reloadSeconds"] = { min = 0.3, minRatio = 0.4 },
	["firearm.range"] = { maxRatio = 1.6 },
	["firearm.pellets"] = { min = 1, max = 5 },
	["firearm.spreadDegrees"] = { min = 0, max = 25 },
	["explosive.damage"] = { minRatio = 0.25, maxRatio = 1.75 },
	["explosive.reloadSeconds"] = { min = 0.3, minRatio = 0.4 },
	["explosive.range"] = { maxRatio = 1.6 },
	["explosive.radius"] = { maxRatio = 1.8 },
	["self.moveSpeed"] = { maxRatio = Config.Movement.maxSpeedUpgradeMultiplier },
	["self.slideCooldown"] = { min = 1.5 },
} :: { [string]: Limit }

-- Words for the "change" line on a card.
UpgradeDefs.statLabels = {
	reloadSeconds = { label = "Reload", unit = "s" },
	damage = { label = "Damage", unit = "" },
	range = { label = "Range", unit = " studs" },
	pellets = { label = "Bullets", unit = "" },
	spreadDegrees = { label = "Spread", unit = "°" },
	radius = { label = "Blast size", unit = " studs" },
	moveSpeed = { label = "Run speed", unit = "" },
	slideCooldown = { label = "Slide wait", unit = "s" },
} :: { [string]: { label: string, unit: string } }

local function groupTable(sheet: Sheet, group: string): { [string]: number }
	if group == "self" then
		return sheet :: any
	end
	return (sheet :: any)[group]
end

local function cloneSheet(sheet: Sheet): Sheet
	local copy: any = table.clone(sheet :: any)
	copy.firearm = table.clone((sheet :: any).firearm)
	copy.explosive = table.clone((sheet :: any).explosive)
	return copy :: Sheet
end

UpgradeDefs.cloneSheet = cloneSheet

local function applyLimit(value: number, base: number, limit: Limit?): number
	if limit == nil then
		return value
	end
	local lo: number? = limit.min
	local hi: number? = limit.max
	if limit.minRatio ~= nil then
		local r = base * limit.minRatio
		lo = if lo == nil then r else math.max(lo, r)
	end
	if limit.maxRatio ~= nil then
		local r = base * limit.maxRatio
		hi = if hi == nil then r else math.min(hi, r)
	end
	if lo ~= nil and value < lo then
		value = lo
	end
	if hi ~= nil and value > hi then
		value = hi
	end
	return value
end

-- A fresh sheet: base plus every owned upgrade. Stack counts are clamped to maxStacks and
-- unknown ids are ignored, so a bad stack table can never push a stat past the limits.
function UpgradeDefs.resolve(base: Sheet, stacks: Stacks): Sheet
	local add: { [string]: number } = {}
	local pct: { [string]: number } = {}
	local mult: { [string]: number } = {}
	local touched: { [string]: { group: string, stat: string } } = {}

	for _, upgrade in list do
		local n = stacks[upgrade.id]
		if n ~= nil and n > 0 then
			n = math.min(math.floor(n), upgrade.maxStacks)
			for _, effect in upgrade.effects do
				for _, group in effect.groups do
					local key = group .. "." .. effect.stat
					touched[key] = { group = group, stat = effect.stat }
					if effect.op == "add" then
						add[key] = (add[key] or 0) + effect.value * n
					elseif effect.op == "pct" then
						pct[key] = (pct[key] or 0) + effect.value * n
					else
						mult[key] = (mult[key] or 1) * effect.value ^ n
					end
				end
			end
		end
	end

	local out = cloneSheet(base)
	for key, info in touched do
		local baseValue = groupTable(base, info.group)[info.stat]
		local value = (baseValue + (add[key] or 0)) * (1 + (pct[key] or 0)) * (mult[key] or 1)
		groupTable(out, info.group)[info.stat] =
			applyLimit(value, baseValue, UpgradeDefs.limits[key])
	end
	return out
end

local function groupPresent(group: string, ctx: Ctx): boolean
	return group ~= "explosive" or ctx.hasExplosive
end

-- Can this upgrade be offered right now? Second result is the reason when not.
function UpgradeDefs.canOffer(id: string, stacks: Stacks, ctx: Ctx): (boolean, string?)
	local upgrade = byId[id]
	if upgrade == nil then
		return false, "unknown"
	end
	local have = stacks[id] or 0
	if have >= upgrade.maxStacks then
		return false, "maxed"
	end
	if upgrade.requires ~= nil then
		for reqId, need in upgrade.requires do
			if (stacks[reqId] or 0) < need then
				return false, "needs_prereq"
			end
		end
	end
	if upgrade.incompatible ~= nil then
		for _, other in upgrade.incompatible do
			if (stacks[other] or 0) > 0 then
				return false, "incompatible"
			end
		end
	end
	for otherId, count in stacks do
		local other = byId[otherId]
		if
			count > 0
			and other ~= nil
			and other.incompatible ~= nil
			and table.find(other.incompatible, id)
		then
			return false, "incompatible"
		end
	end

	-- Must change at least one stat of a weapon or ability the player really has.
	local nextStacks = table.clone(stacks)
	nextStacks[id] = have + 1
	local before = UpgradeDefs.resolve(ctx.base, stacks)
	local after = UpgradeDefs.resolve(ctx.base, nextStacks)
	for _, effect in upgrade.effects do
		for _, group in effect.groups do
			if
				groupPresent(group, ctx)
				and math.abs(
						groupTable(after, group)[effect.stat]
							- groupTable(before, group)[effect.stat]
					)
					> EPSILON
			then
				return true, nil
			end
		end
	end
	return false, "no_effect"
end

function UpgradeDefs.eligible(stacks: Stacks, ctx: Ctx): { Upgrade }
	local out: { Upgrade } = {}
	for _, upgrade in list do
		if UpgradeDefs.canOffer(upgrade.id, stacks, ctx) then
			table.insert(out, upgrade)
		end
	end
	return out
end

-- Picks up to `count` different upgrades by weight. `rand` returns a number in [0, 1).
-- Fewer than `count` come back only when fewer are eligible.
function UpgradeDefs.roll(stacks: Stacks, ctx: Ctx, rand: () -> number, count: number?): { string }
	local pool = UpgradeDefs.eligible(stacks, ctx)
	local picks: { string } = {}
	for _ = 1, math.min(count or Config.Upgrades.offerSize, #pool) do
		local total = 0
		for _, upgrade in pool do
			total += upgrade.weight
		end
		local roll = rand() * total
		local chosen = #pool
		for i, upgrade in pool do
			roll -= upgrade.weight
			if roll < 0 then
				chosen = i
				break
			end
		end
		table.insert(picks, pool[chosen].id)
		table.remove(pool, chosen)
	end
	return picks
end

local function fmt(n: number): string
	local s = string.format("%.2f", n)
	return (string.gsub(s, "%.?0+$", ""))
end

-- "Reload 1.2s → 0.96s" for the stats this pick would change. With the mortar on, each weapon
-- gets its own entry, named, so the player can see which gun changes.
local function changeText(upgrade: Upgrade, stacks: Stacks, ctx: Ctx): string
	local nextStacks = table.clone(stacks)
	nextStacks[upgrade.id] = (stacks[upgrade.id] or 0) + 1
	local before = UpgradeDefs.resolve(ctx.base, stacks)
	local after = UpgradeDefs.resolve(ctx.base, nextStacks)
	local parts: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, effect in upgrade.effects do
		for _, group in effect.groups do
			local key = group .. "." .. effect.stat
			if not seen[key] and groupPresent(group, ctx) then
				seen[key] = true
				local from = groupTable(before, group)[effect.stat]
				local to = groupTable(after, group)[effect.stat]
				if math.abs(to - from) > EPSILON then
					local info = UpgradeDefs.statLabels[effect.stat]
					local label = if info then info.label else effect.stat
					local unit = if info then info.unit else ""
					local owner = ""
					if ctx.hasExplosive and group ~= "self" and ctx.weaponNames ~= nil then
						owner = (ctx.weaponNames :: any)[group] .. " "
					end
					table.insert(parts, `{owner}{label} {fmt(from)}{unit} → {fmt(to)}{unit}`)
				end
			end
		end
	end
	return table.concat(parts, ", ")
end

-- The card data the client draws. Server builds it; the client never decides what an upgrade does.
function UpgradeDefs.option(id: string, stacks: Stacks, ctx: Ctx): Option
	local upgrade = byId[id]
	assert(upgrade ~= nil, "UpgradeDefs.option: unknown upgrade " .. tostring(id))
	return {
		id = upgrade.id,
		name = upgrade.name,
		description = upgrade.description,
		icon = upgrade.icon,
		stacks = stacks[id] or 0,
		maxStacks = upgrade.maxStacks,
		change = changeText(upgrade, stacks, ctx),
		kind = upgrade.kind,
	}
end

return UpgradeDefs

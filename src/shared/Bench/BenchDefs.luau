--!strict
-- The bench (video 3 gap 14): parts you collect, merge into better parts, and build into gear from blueprints.
-- Gear is looks only: no stats, no Robux, no prices. Ids are saved forever, so never rename one (use
-- ProfileSchema.itemRenames if you must). Pure data so Lune can test it.

export type Kind = { id: string, name: string }
export type Tier = { tier: number, name: string }
export type Need = { kind: string, tier: number, count: number }
export type Blueprint = {
	id: string,
	name: string,
	slot: string, -- hint for the gear slots piece: "head" | "body" | "feet"
	needs: { Need },
}

local BenchDefs = {}

-- Three families of parts. The same chance for each (shown to the player: BenchText.odds).
BenchDefs.kinds = {
	{ id = "bolt", name = "Bolt" },
	{ id = "plate", name = "Plate" },
	{ id = "coil", name = "Coil" },
} :: { Kind }

BenchDefs.tiers = {
	{ tier = 1, name = "Rough" },
	{ tier = 2, name = "Tuned" },
	{ tier = 3, name = "Polished" },
	{ tier = 4, name = "Prime" },
} :: { Tier }

BenchDefs.maxTier = #BenchDefs.tiers
BenchDefs.mergeCount = 3 -- this many of one part make one part of the next tier

BenchDefs.blueprints = {
	{
		id = "spark_cap",
		name = "Spark Cap",
		slot = "head",
		needs = { { kind = "bolt", tier = 1, count = 2 }, { kind = "plate", tier = 1, count = 1 } },
	},
	{
		id = "street_vest",
		name = "Street Vest",
		slot = "body",
		needs = { { kind = "plate", tier = 1, count = 2 }, { kind = "coil", tier = 1, count = 1 } },
	},
	{
		id = "dash_kicks",
		name = "Dash Kicks",
		slot = "feet",
		needs = { { kind = "coil", tier = 1, count = 2 }, { kind = "bolt", tier = 1, count = 1 } },
	},
	{
		id = "night_visor",
		name = "Night Visor",
		slot = "head",
		needs = {
			{ kind = "bolt", tier = 2, count = 1 },
			{ kind = "plate", tier = 2, count = 1 },
			{ kind = "coil", tier = 2, count = 1 },
		},
	},
	{
		id = "bulwark_coat",
		name = "Bulwark Coat",
		slot = "body",
		needs = { { kind = "plate", tier = 3, count = 1 }, { kind = "coil", tier = 2, count = 1 } },
	},
	{
		id = "prime_halo",
		name = "Prime Halo",
		slot = "head",
		needs = {
			{ kind = "bolt", tier = 4, count = 1 },
			{ kind = "coil", tier = 3, count = 1 },
			{ kind = "plate", tier = 2, count = 1 },
		},
	},
} :: { Blueprint }

local kindIndex: { [string]: Kind } = {}
for _, k in BenchDefs.kinds do
	kindIndex[k.id] = k
end
local blueprintIndex: { [string]: Blueprint } = {}
for _, b in BenchDefs.blueprints do
	blueprintIndex[b.id] = b
end

function BenchDefs.kind(id: any): Kind?
	return if type(id) == "string" then kindIndex[id] else nil
end

function BenchDefs.blueprint(id: any): Blueprint?
	return if type(id) == "string" then blueprintIndex[id] else nil
end

function BenchDefs.isTier(tier: any): boolean
	return type(tier) == "number"
		and tier >= 1
		and tier <= BenchDefs.maxTier
		and tier == math.floor(tier)
end

function BenchDefs.tierName(tier: number): string
	local t = BenchDefs.tiers[tier]
	return if t then t.name else "?"
end

-- The saved key for a part pile: "bolt_2". Lowercase letters, digits and "_" only.
function BenchDefs.partKey(kind: string, tier: number): string
	return kind .. "_" .. tostring(tier)
end

return BenchDefs

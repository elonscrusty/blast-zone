--!strict
-- The eight sweeping tools, in tier order. Buy once with coins, equip any owned tool.
-- power = ash units removed per cell per swing (may be fractional: the server rolls the fraction).
-- reach = studs (measured to the near part of a cell, see AshGrid); arcDeg = width of the sweep fan;
-- interval = seconds between swings. Each tool has one shape or trait you can feel:
--   Twig small fan | Push wide fan | Leaf long narrow jet | Dust Vac big gulps (power jump) |
--   Turbo very fast swings | Lava Mop melts the leftovers (melt 3) | Dragon all round you (360) |
--   Volcano Vacuum huge reach + 270 fan + melt.
-- Prices climb about x4-x12 a tier. Tuned with tests/pacing.test.luau, which measures the REAL
-- AshGrid cone and the real ash supply (not the estimate below).

export type Tool = {
	id: string,
	name: string,
	tier: number,
	price: number,
	reach: number,
	arcDeg: number,
	power: number,
	interval: number,
	capacityBonus: number,
	melt: number?, -- trait: a cell left with this many units or fewer after a swing melts away
	trait: string,
	color: string,
	blurb: string,
}

local Tools = {}

Tools.list = {
	{
		id = "twig_broom",
		name = "Twig Broom",
		tier = 1,
		price = 0,
		reach = 7,
		arcDeg = 90,
		power = 1,
		interval = 0.34,
		capacityBonus = 0,
		trait = "Tiny but trusty",
		color = "#A9805B",
		blurb = "Your very first broom. Swish swish!",
	},
	{
		id = "push_broom",
		name = "Push Broom",
		tier = 2,
		price = 260,
		reach = 8,
		arcDeg = 110,
		power = 1.2,
		interval = 0.36,
		capacityBonus = 40,
		trait = "Wide sweep",
		color = "#E0B040",
		blurb = "A big wide brush that clears a whole row at once.",
	},
	{
		id = "leaf_blower",
		name = "Leaf Blower",
		tier = 3,
		price = 1200,
		reach = 15,
		arcDeg = 50,
		power = 1.5,
		interval = 0.32,
		capacityBonus = 60,
		trait = "Long reach",
		color = "#4FB3E8",
		blurb = "Whoosh! Blows ash from far, far away.",
	},
	{
		id = "dust_vac",
		name = "Dust Vac",
		tier = 4,
		price = 6000,
		reach = 10,
		arcDeg = 120,
		power = 2.8,
		interval = 0.42,
		capacityBonus = 100,
		trait = "Big gulps",
		color = "#6BCB77",
		blurb = "Slurp! Each gulp empties a deep pile.",
	},
	{
		id = "turbo_vac",
		name = "Turbo Vac",
		tier = 5,
		price = 30000,
		reach = 12,
		arcDeg = 140,
		power = 2.8,
		interval = 0.24,
		capacityBonus = 170,
		trait = "Super fast",
		color = "#FF7A59",
		blurb = "Zoom zoom! It spins so fast it hums.",
	},
	{
		id = "lava_mop",
		name = "Lava Mop",
		tier = 6,
		price = 250000,
		reach = 13,
		arcDeg = 150,
		power = 3,
		interval = 0.26,
		capacityBonus = 300,
		melt = 3,
		trait = "Melts leftovers",
		color = "#FF5A36",
		blurb = "A glowing mop. Little bits of ash melt away! (Safe to touch.)",
	},
	{
		id = "dragon_vac",
		name = "Dragon Vac",
		tier = 7,
		price = 3000000,
		reach = 12,
		arcDeg = 360,
		power = 3.2,
		interval = 0.26,
		capacityBonus = 500,
		trait = "Sweeps all around",
		color = "#9B5DE5",
		blurb = "A friendly dragon that gobbles ash all around you!",
	},
	{
		id = "volcano_vac",
		name = "Volcano Vacuum",
		tier = 8,
		price = 28000000,
		reach = 22,
		arcDeg = 270,
		power = 4.0,
		interval = 0.22,
		capacityBonus = 900,
		melt = 2,
		trait = "Pulls in everything",
		color = "#FFD23F",
		blurb = "The ultimate sweeper. The volcano itself is jealous!",
	},
} :: { Tool }

Tools.byId = {} :: { [string]: Tool }
Tools.order = {} :: { string }
for _, tool in Tools.list do
	Tools.byId[tool.id] = tool
	table.insert(Tools.order, tool.id)
end

-- The tool one tier above `id`, or nil for the last tool / an unknown id.
function Tools.next(id: string): Tool?
	local tool = Tools.byId[id]
	if not tool then
		return nil
	end
	return Tools.list[tool.tier + 1]
end

-- Rough number of ash cells a swing covers (fits the real AshGrid cone within ~10%): the cell you
-- stand in plus the fan's area out to reach + a quarter cell, over one cell's area.
function Tools.cellsHit(reach: number, arcDeg: number, cellSize: number): number
	local r = reach + cellSize * 0.25
	local area = math.pi * r * r * (math.min(arcDeg, 360) / 360)
	return 1 + 0.85 * area / (cellSize * cellSize)
end

return Tools

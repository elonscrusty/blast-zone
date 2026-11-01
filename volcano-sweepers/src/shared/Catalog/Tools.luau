--!strict
-- The eight sweeping tools, in tier order. Buy once with coins, equip any owned tool.
-- power = ash units removed per cell per swing (may be fractional: the server rolls the fraction).
-- reach = studs; arcDeg = width of the sweep fan; interval = seconds between swings.
-- Price curve is roughly x4-x5 per tier. Tuned together with tests/pacing.test.luau.

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
		arcDeg = 80,
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
		price = 130,
		reach = 9,
		arcDeg = 110,
		power = 1.2,
		interval = 0.38,
		capacityBonus = 40,
		trait = "Wide sweep",
		color = "#E0B040",
		blurb = "A big wide brush that clears a whole row at once.",
	},
	{
		id = "leaf_blower",
		name = "Leaf Blower",
		tier = 3,
		price = 600,
		reach = 13,
		arcDeg = 70,
		power = 1.5,
		interval = 0.34,
		capacityBonus = 60,
		trait = "Long reach",
		color = "#4FB3E8",
		blurb = "Whoosh! Blows ash from far away.",
	},
	{
		id = "dust_vac",
		name = "Dust Vac",
		tier = 4,
		price = 3200,
		reach = 11,
		arcDeg = 130,
		power = 1.8,
		interval = 0.34,
		capacityBonus = 100,
		trait = "Slurps it up",
		color = "#6BCB77",
		blurb = "Slurp! A hungry little vacuum for big piles.",
	},
	{
		id = "turbo_vac",
		name = "Turbo Vac",
		tier = 5,
		price = 16000,
		reach = 13,
		arcDeg = 150,
		power = 2.0,
		interval = 0.32,
		capacityBonus = 170,
		trait = "Super fast",
		color = "#FF7A59",
		blurb = "Zoom zoom! It spins so fast it hums.",
	},
	{
		id = "lava_mop",
		name = "Lava Mop",
		tier = 6,
		price = 120000,
		reach = 13,
		arcDeg = 150,
		power = 2.1,
		interval = 0.30,
		capacityBonus = 300,
		trait = "Melts mess",
		color = "#FF5A36",
		blurb = "A glowing mop that is safe to touch. Promise!",
	},
	{
		id = "dragon_vac",
		name = "Dragon Vac",
		tier = 7,
		price = 1500000,
		reach = 14,
		arcDeg = 170,
		power = 2.3,
		interval = 0.28,
		capacityBonus = 500,
		trait = "Roaring power",
		color = "#9B5DE5",
		blurb = "A friendly dragon that loves to gobble ash.",
	},
	{
		id = "volcano_vac",
		name = "Volcano Vacuum",
		tier = 8,
		price = 45000000,
		reach = 22,
		arcDeg = 270,
		power = 4.0,
		interval = 0.24,
		capacityBonus = 900,
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

-- Rough number of ash cells a swing covers: the fan's area over one cell's area (at least 1).
function Tools.cellsHit(reach: number, arcDeg: number, cellSize: number): number
	local area = math.pi * reach * reach * (math.min(arcDeg, 360) / 360)
	return math.max(1, area / (cellSize * cellSize))
end

return Tools

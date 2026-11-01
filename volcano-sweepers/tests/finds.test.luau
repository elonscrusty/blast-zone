--!strict
local FindRoller = require("../src/shared/Finds/FindRoller")
local Harness = require("./harness")
local Rng = require("../src/shared/Rng")

-- small fake catalog, same shape the real Catalog/Finds and rarity list use
local rarities: { FindRoller.Rarity } = {
	{ id = "common", weight = 60 },
	{ id = "uncommon", weight = 28 },
	{ id = "rare", weight = 10 },
	{ id = "legendary", weight = 2 },
}
local finds: { FindRoller.Find } = {}
for zone = 0, 5 do
	local per = zone == 0 and { "rare", "rare", "legendary", "legendary", "legendary" }
		or { "common", "common", "common", "uncommon", "uncommon", "rare", "legendary" }
	for k, rarity in per do
		table.insert(finds, { id = `z{zone}_{k}`, rarity = rarity, zone = zone })
	end
end

local function sample(luck: number, zone: number, n: number, seed: number)
	local rng = Rng.new(seed)
	local hits = 0
	local byRarity: { [string]: number } = { common = 0, uncommon = 0, rare = 0, legendary = 0 }
	local rainbow = 0
	for _ = 1, n do
		local f = FindRoller.roll(rng, luck, zone, finds, rarities)
		if f then
			hits += 1
			byRarity[f.rarity] += 1
			if f.zone == 0 then
				rainbow += 1
			else
				Harness.eq(f.zone, zone, "a find belongs to the zone it was found in")
			end
		end
	end
	return hits, byRarity, rainbow
end

Harness.test("finds: chance() is ~3% base, grows with luck, is capped", function()
	Harness.near(FindRoller.chance(0), 0.03, 1e-9)
	Harness.truthy(FindRoller.chance(1) > FindRoller.chance(0))
	Harness.truthy(FindRoller.chance(3) > FindRoller.chance(1))
	Harness.near(FindRoller.chance(1), 0.06, 1e-9)
	Harness.truthy(FindRoller.chance(1e9) <= FindRoller.maxChance)
	Harness.near(FindRoller.chance(-5), 0.03, 1e-9, "negative luck is ignored")
	Harness.near(FindRoller.chance(0 / 0), 0.03, 1e-9, "nan luck is ignored")
end)

Harness.test("finds: base rate matches chance(), luck raises it", function()
	local n = 200000
	local base = sample(0, 2, n, 1)
	Harness.near(base / n, 0.03, 0.002, "luck 0 rate")
	local lucky = sample(1, 2, n, 2)
	Harness.near(lucky / n, 0.06, 0.003, "luck 1 rate")
	local luckier = sample(3, 2, n, 3)
	Harness.truthy(luckier > lucky and lucky > base)
end)

Harness.test("finds: rarity order and luck shifts toward rare", function()
	local _, a = sample(0, 3, 600000, 4)
	Harness.truthy(
		a.common > a.uncommon and a.uncommon > a.rare and a.rare > a.legendary,
		"common most, legendary least"
	)
	Harness.truthy(a.legendary > 0)
	local _, b = sample(4, 3, 600000, 5)
	local shareA = a.legendary / (a.common + a.uncommon + a.rare + a.legendary)
	local shareB = b.legendary / (b.common + b.uncommon + b.rare + b.legendary)
	Harness.truthy(shareB > shareA * 1.2, `legendary share {shareA} -> {shareB}`)
	local odds0 = FindRoller.rarityOdds(0, rarities)
	local odds4 = FindRoller.rarityOdds(4, rarities)
	Harness.near(odds0.common + odds0.uncommon + odds0.rare + odds0.legendary, 1, 1e-9)
	Harness.near(odds4.common + odds4.uncommon + odds4.rare + odds4.legendary, 1, 1e-9)
	Harness.truthy(odds4.legendary > odds0.legendary and odds4.common < odds0.common)
	Harness.near(odds0.legendary, 2 / 100, 1e-9)
end)

Harness.test("finds: rainbow finds are very rare but possible in any zone", function()
	local n = 1000000
	local hits, _, rainbow = sample(0, 4, n, 6)
	Harness.truthy(rainbow > 0, "they can drop")
	Harness.truthy(rainbow / n < 0.001, "very rare")
	Harness.truthy(rainbow < hits * 0.05, "a tiny share of all finds")
	local _, _, rainbowLucky = sample(4, 1, n, 7)
	Harness.truthy(rainbowLucky >= rainbow * 0.9, "luck does not hurt")
	Harness.truthy(FindRoller.rainbowChanceFor(100) <= FindRoller.rainbowMaxChance)
end)

Harness.test("finds: empty zones, no rainbow finds, deterministic", function()
	local only: { FindRoller.Find } = { { id = "a", rarity = "common", zone = 1 } }
	local rng = Rng.new(8)
	for _ = 1, 5000 do
		Harness.eq(FindRoller.roll(rng, 5, 2, only, rarities), nil, "zone 2 has nothing")
	end
	local got = 0
	for _ = 1, 20000 do
		local f = FindRoller.roll(rng, 5, 1, only, rarities)
		if f then
			got += 1
			Harness.eq(f.id, "a")
		end
	end
	Harness.truthy(got > 0)
	Harness.eq(FindRoller.roll(rng, 1, 1, {}, rarities), nil)
	local r1, r2 = Rng.new(99), Rng.new(99)
	for _ = 1, 3000 do
		local a = FindRoller.roll(r1, 2, 3, finds, rarities)
		local b = FindRoller.roll(r2, 2, 3, finds, rarities)
		Harness.eq(a and a.id, b and b.id)
	end
end)

Harness.test("finds: rolls are rationed per player (burst, then ~1.5 a second)", function()
	local b = FindRoller.newBudget(0)
	Harness.eq(FindRoller.takeRolls(b, 0, 40), FindRoller.ROLL_BURST, "a big swing gets the burst")
	Harness.eq(FindRoller.takeRolls(b, 0, 5), 0)
	local total = 0
	local t = 0
	for _ = 1, 600 do -- 60 s of huge swings every 0.1 s
		t += 0.1
		total += FindRoller.takeRolls(b, t, 20)
	end
	Harness.near(total, 60 * FindRoller.ROLLS_PER_SECOND, 2)
	Harness.eq(FindRoller.takeRolls(b, t - 50, 5), 0, "a clock going backwards mints nothing")
	Harness.eq(FindRoller.takeRolls(b, t + 100, 0 / 0), 0)
	Harness.eq(FindRoller.takeRolls(b, t + 100, 2), 2, "small swings are never cut")
end)

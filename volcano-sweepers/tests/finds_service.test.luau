--!strict
-- FindsService itself is Roblox glue, so these tests run its rules the way the service chains them:
-- roll (FindRoller) -> record (BurpGlue.recordFind) -> pay (BurpGlue.findCoins) -> set check.
local BurpGlue = require("../src/shared/Burp/BurpGlue")
local FindRoller = require("../src/shared/Finds/FindRoller")
local Finds = require("../src/shared/Catalog/Finds")
local Harness = require("./harness")
local Rng = require("../src/shared/Rng")

local NAN = 0 / 0

type Sim = {
	finds: { [string]: number },
	coins: number,
	hits: number,
	newOnes: number,
	rolls: number,
}

-- Same steps as FindsService.onCleared, minus the Instances.
local function onCleared(
	sim: Sim,
	rng: Rng.Rng,
	zoneId: number,
	cleared: number,
	derivedLuck: number,
	sellMult: number
)
	local luck = BurpGlue.luckBonus(derivedLuck)
	for _ = 1, BurpGlue.rollCount(cleared) do
		sim.rolls += 1
		local find = FindRoller.roll(rng, luck, zoneId, Finds.list :: any, Finds.rarities :: any)
		if find ~= nil then
			local def = Finds.byId[find.id]
			sim.hits += 1
			if BurpGlue.recordFind(sim.finds, find.id) then
				sim.newOnes += 1
			end
			sim.coins += BurpGlue.findCoins(def.coins, sellMult)
		end
	end
end

local function newSim(): Sim
	return { finds = {}, coins = 0, hits = 0, newOnes = 0, rolls = 0 }
end

Harness.test("finds service: roll count is capped at 40 and safe", function()
	Harness.eq(BurpGlue.rollCount(1), 1)
	Harness.eq(BurpGlue.rollCount(7.9), 7)
	Harness.eq(BurpGlue.rollCount(40), 40)
	Harness.eq(BurpGlue.rollCount(41), 40)
	Harness.eq(BurpGlue.rollCount(1e12), 40)
	Harness.eq(BurpGlue.rollCount(0), 0)
	Harness.eq(BurpGlue.rollCount(-5), 0)
	Harness.eq(BurpGlue.rollCount(NAN), 0)
	Harness.eq(BurpGlue.rollCount(math.huge), 0)
	local sim = newSim()
	onCleared(sim, Rng.new(1), 1, 100000, 1, 1)
	Harness.eq(sim.rolls, 40, "one call never rolls more than 40 times")
end)

Harness.test("finds service: luck multiplier becomes a bonus fraction", function()
	Harness.near(BurpGlue.luckBonus(1), 0)
	Harness.near(BurpGlue.luckBonus(1.5), 0.5, 1e-9)
	Harness.near(BurpGlue.luckBonus(0.2), 0, 1e-9)
	Harness.near(BurpGlue.luckBonus(NAN), 0)
end)

Harness.test("finds service: payout is catalog coins x sell multiplier", function()
	Harness.eq(BurpGlue.findCoins(20, 1), 20)
	Harness.eq(BurpGlue.findCoins(20, 2.5), 50)
	Harness.eq(BurpGlue.findCoins(20, 1.26), 25)
	Harness.eq(BurpGlue.findCoins(20, 0), 1, "a real find always pays something")
	Harness.eq(BurpGlue.findCoins(20, NAN), 20)
	Harness.eq(BurpGlue.findCoins(0, 5), 0)
	Harness.eq(BurpGlue.findCoins(NAN, 5), 0)
	Harness.eq(BurpGlue.findCoins(-3, 5), 0)
end)

Harness.test("finds service: first of each kind is new, repeats count up", function()
	local finds: { [string]: number } = {}
	Harness.eq(BurpGlue.recordFind(finds, "shiny_shell"), true)
	Harness.eq(finds.shiny_shell, 1)
	Harness.eq(BurpGlue.recordFind(finds, "shiny_shell"), false)
	Harness.eq(finds.shiny_shell, 2)
	finds.bogus = 0
	Harness.eq(BurpGlue.recordFind(finds, "bogus"), true, "a saved 0 counts as never found")
	Harness.eq(finds.bogus, 1)
	finds.broken = NAN
	Harness.eq(BurpGlue.recordFind(finds, "broken"), true)
	Harness.eq(finds.broken, 1)
end)

Harness.test(
	"finds service: sweeping a zone finds only that zone's items (plus rainbow)",
	function()
		local sim = newSim()
		local rng = Rng.new(21)
		for _ = 1, 20000 do
			onCleared(sim, rng, 3, 5, 1, 1)
		end
		Harness.truthy(sim.hits > 1000, "finds do happen")
		for id in sim.finds do
			local def = Finds.byId[id]
			Harness.truthy(def ~= nil, `known find {id}`)
			Harness.truthy(def.zone == 3 or def.zone == 0, `{id} belongs to zone 3 or rainbow`)
		end
		-- rate: 100k cleared cells at ~3% (plus a sliver of rainbow)
		Harness.near(sim.hits / sim.rolls, FindRoller.chance(0), 0.003)
		Harness.eq(sim.rolls, 100000)
	end
)

Harness.test("finds service: luck and sell multiplier raise the payout", function()
	local a, b, c = newSim(), newSim(), newSim()
	local n = 400
	for k = 1, n do
		onCleared(a, Rng.new(k), 4, 40, 1, 1)
		onCleared(b, Rng.new(k), 4, 40, 3, 1)
		onCleared(c, Rng.new(k), 4, 40, 1, 2)
	end
	Harness.truthy(b.hits > a.hits * 1.5, `luck 3 hits {b.hits} vs {a.hits}`)
	Harness.near(c.coins / a.coins, 2, 0.02, "same finds, double multiplier")
	Harness.eq(c.hits, a.hits, "multiplier does not change what is found")
end)

Harness.test("finds service: finding everything in a zone makes its set claimable once", function()
	local setById = Finds.setById :: { [string]: any }
	local list = Finds.list :: { { id: string, set: string } }
	local sim = newSim()
	local rng = Rng.new(33)
	local claimed: { [string]: boolean } = {}
	local ok = BurpGlue.claimCheck("beach", sim.finds, claimed, setById, list)
	Harness.eq(ok, false, "nothing found yet")

	local sweeps = 0
	while not (BurpGlue.claimCheck("beach", sim.finds, claimed, setById, list)) do
		onCleared(sim, rng, 1, 40, 4, 1)
		sweeps += 1
		Harness.truthy(sweeps < 100000, "a lucky player completes the beach set eventually")
	end
	-- the claim the ClaimSet handler would make
	local reward = (Finds.setById.beach :: any).reward
	claimed.beach = true
	local ok2, why = BurpGlue.claimCheck("beach", sim.finds, claimed, setById, list)
	Harness.eq(ok2, false)
	Harness.eq(why, "claimed", "second claim is refused")
	Harness.eq(BurpGlue.setClaimText(reward), "Set complete! +2% coins forever")
end)

Harness.test("finds service: odds are the catalog's, every find is reachable", function()
	local seen: { [string]: boolean } = {}
	local rng = Rng.new(77)
	local sim = newSim()
	for zone = 1, 5 do
		for _ = 1, 4000 do
			onCleared(sim, rng, zone, 40, 8, 1) -- big luck so rare things show up quickly
		end
	end
	for id in sim.finds do
		seen[id] = true
	end
	local missingNormal = {}
	for _, f in Finds.list do
		if f.zone ~= 0 and not seen[f.id] then
			table.insert(missingNormal, f.id)
		end
	end
	Harness.eq(#missingNormal, 0, `never found: {table.concat(missingNormal, ",")}`)
end)

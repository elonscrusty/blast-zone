--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RunXp = require("../src/shared/RunXp")
local ContainerRules = require("../src/server/Pickups/ContainerRules")
local PickupRules = require("../src/server/Pickups/PickupRules")

local tiers = Config.Containers.tiers
local order = Config.Containers.tierOrder

local function weight(id: string): number
	return tiers[id].weight
end

Harness.test(
	"every tier has a color, health, orbs and a weight, and better tiers give more",
	function()
		local lastHealth, lastOrbs = 0, 0
		local seenColors: { [string]: boolean } = {}
		for _, id in order do
			local t = tiers[id]
			Harness.truthy(t ~= nil, id .. " exists")
			Harness.truthy(string.match(t.color, "^#%x%x%x%x%x%x$") ~= nil, id .. " color is hex")
			Harness.truthy(not seenColors[t.color], id .. " has its own color")
			seenColors[t.color] = true
			Harness.truthy(
				t.health > lastHealth and t.orbs > lastOrbs,
				id .. " beats the tier before"
			)
			Harness.truthy(t.weight > 0, id .. " can be rolled")
			lastHealth, lastOrbs = t.health, t.orbs
		end
		Harness.eq(tiers.common.health, Config.Containers.health, "common is the plain container")
		Harness.eq(tiers.common.orbs, Config.Containers.orbsPerContainer)
	end
)

Harness.test("tier roll follows the weights", function()
	-- 50 / 35 / 15: the cut points are 0.50 and 0.85.
	Harness.eq(ContainerRules.pickTier(order, weight, 0), "common")
	Harness.eq(ContainerRules.pickTier(order, weight, 0.499), "common")
	Harness.eq(ContainerRules.pickTier(order, weight, 0.5), "rare")
	Harness.eq(ContainerRules.pickTier(order, weight, 0.849), "rare")
	Harness.eq(ContainerRules.pickTier(order, weight, 0.85), "epic")
	Harness.eq(ContainerRules.pickTier(order, weight, 0.9999999), "epic")
	Harness.eq(ContainerRules.pickTier(order, weight, 5), "epic", "roll above 1 is clamped")
	Harness.eq(
		ContainerRules.pickTier(order, weight, 0 / 0),
		"common",
		"bad roll is the first tier"
	)
end)

Harness.test("a tier with no weight is never rolled", function()
	local only: { [string]: number } = { a = 0, b = 3 }
	for _, roll in { 0, 0.3, 0.99 } do
		Harness.eq(
			ContainerRules.pickTier({ "a", "b" }, function(id: string): number
				return only[id]
			end, roll),
			"b"
		)
	end
end)

Harness.test("a container takes exactly its health in hits, then breaks once", function()
	for _, id in order do
		local health = tiers[id].health
		local broke = false
		local hits = 0
		while health > 0 do
			health, broke = ContainerRules.applyDamage(health, Config.Weapons.Firearm.damage)
			hits += 1
		end
		Harness.eq(broke, true, id .. " broke on the last hit")
		Harness.eq(hits, math.ceil(tiers[id].health / Config.Weapons.Firearm.damage), id .. " hits")
		local again, brokeAgain = ContainerRules.applyDamage(health, 100)
		Harness.eq(again, 0)
		Harness.eq(brokeAgain, false, id .. " cannot break twice")
	end
end)

Harness.test("bad damage numbers change nothing", function()
	for _, bad in { 0, -10, 0 / 0, math.huge } do
		local health, broke = ContainerRules.applyDamage(40, bad)
		Harness.eq(health, 40)
		Harness.eq(broke, false)
	end
end)

Harness.test("drops sit evenly on the ring", function()
	local spots = ContainerRules.scatter(3, 3.5, 0.7)
	Harness.eq(#spots, 3)
	for _, s in spots do
		Harness.near(math.sqrt(s.x * s.x + s.z * s.z), 3.5, 1e-9, "distance from the container")
	end
	Harness.truthy(
		math.abs(spots[1].x - spots[2].x) > 0.1 or math.abs(spots[1].z - spots[2].z) > 0.1
	)
	Harness.eq(#ContainerRules.scatter(0, 3.5, 0), 0)
end)

local function orb(): PickupRules.Pickup
	return {
		id = "o1_1",
		matchId = 1,
		expiresAt = 100,
		reservedFor = "p7",
		reservedUntil = 11.5,
		claimed = false,
	}
end
local R = Config.Pickups.collectRadius
local SLACK = Config.Pickups.claimSlack

local function check(
	p: PickupRules.Pickup,
	who: string,
	now: number,
	distance: number
): (boolean, string?)
	return PickupRules.check(p, who, now, distance, R, SLACK, 1)
end

Harness.test("the breaker gets first claim, then anyone may", function()
	local p = orb()
	Harness.eq(check(p, "p7", 10, 2), true)
	local ok, why = check(p, "p8", 10, 2)
	Harness.eq(ok, false)
	Harness.eq(why, "reserved")
	Harness.eq(check(p, "p8", 11.5, 2), true, "reserve is over")
end)

Harness.test("an orb with nobody reserved is free for everyone", function()
	local p = orb()
	p.reservedFor = nil
	Harness.eq(check(p, "p8", 10, 2), true)
end)

Harness.test("claimed, expired and stale-match orbs cannot be taken", function()
	local claimed = orb()
	claimed.claimed = true
	local _, why1 = check(claimed, "p7", 10, 1)
	Harness.eq(why1, "claimed")
	local _, why2 = check(orb(), "p7", 100, 1)
	Harness.eq(why2, "expired")
	local _, why3 = PickupRules.check(orb(), "p7", 10, 1, R, SLACK, 2)
	Harness.eq(why3, "stale-match")
end)

Harness.test("distance: the radius plus the lag slack counts, farther does not", function()
	local p = orb()
	p.reservedFor = nil
	Harness.eq(check(p, "p1", 10, R + SLACK), true)
	local ok, why = check(p, "p1", 10, R + SLACK + 0.01)
	Harness.eq(ok, false)
	Harness.eq(why, "too-far")
	Harness.eq(check(p, "p1", 10, 0 / 0), false, "a bad distance never counts")
end)

Harness.test("two claims on one orb: only the first wins", function()
	-- The server marks the orb claimed the moment a claim passes, so the second claim finds it taken.
	local p = orb()
	p.reservedFor = nil
	local first = check(p, "p1", 10, 1)
	if first then
		p.claimed = true
	end
	local second, why = check(p, "p2", 10, 1)
	Harness.eq(first, true)
	Harness.eq(second, false)
	Harness.eq(why, "claimed")
end)

Harness.test("an average match of crates and kills gives about three upgrade offers", function()
	local xp = RunXp.new(Config.Xp :: any)
	xp:reset("p1")
	local totalWeight = 0
	for _, id in order do
		totalWeight += tiers[id].weight
	end
	-- Average orbs per crate, by the weights. Four crates and one elimination, in the numbers of Config.
	local averageOrbs = 0
	for _, id in order do
		averageOrbs += tiers[id].orbs * tiers[id].weight / totalWeight
	end
	local crates = 4
	for _ = 1, crates do
		xp:award("p1", "containerBreak")
	end
	for _ = 1, math.round(crates * averageOrbs) do
		xp:award("p1", "orbPickup")
	end
	xp:award("p1", "elimination")
	local state = xp:get("p1")
	Harness.truthy(
		state ~= nil and state.offersGranted >= 2 and state.offersGranted <= 4,
		"2 to 4 offers"
	)
	-- A single crate can never be a whole level on its own (even an epic one).
	local epic = Config.Xp.rewards.containerBreak + tiers.epic.orbs * Config.Xp.rewards.orbPickup
	Harness.truthy(epic < Config.Xp.levelCosts[2], "one epic crate is less than level 2 to 3")
end)

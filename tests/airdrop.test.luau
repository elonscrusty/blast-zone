--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local AirdropRules = require("../src/shared/Airdrop/AirdropRules")
local RemoteDefs = require("../src/shared/RemoteDefs")

local cfg: any = Config.Airdrop

-- A roll that walks through a fixed list, then repeats it.
local function rolls(list: { number }): () -> number
	local i = 0
	return function(): number
		i = i % #list + 1
		return list[i]
	end
end

-- A repeatable pseudo-random roll (so a test can try many points).
local function lcg(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

Harness.test("airdrop: drops spread over the fight, in order, never too close in time", function()
	for _, r in { 0, 0.3, 0.5, 0.99 } do
		local t = AirdropRules.schedule(3, 40, 120, 10, 25, rolls({ r, 1 - r, r }))
		Harness.eq(#t, 3)
		for i = 1, #t do
			Harness.truthy(t[i] >= 0)
			if i > 1 then
				Harness.truthy(t[i] - t[i - 1] >= 25 - 1e-9, `gap {i} at roll {r}`)
			end
		end
	end
	local one = AirdropRules.schedule(1, 40, 120, 0, 25, rolls({ 0.5 }))
	Harness.eq(#one, 1)
	Harness.near(one[1], 80)
	Harness.eq(#AirdropRules.schedule(0, 40, 120, 10, 25, rolls({ 0.5 })), 0)
end)

Harness.test("airdrop: a drop never goes before the fight starts", function()
	local t = AirdropRules.schedule(2, 2, 20, 30, 0, rolls({ 0 }))
	for _, v in t do
		Harness.truthy(v >= 0)
	end
end)

Harness.test("airdrop: lands inside the circle as it will be, with a margin", function()
	Harness.near(AirdropRules.safeRadius(100, 100, 14), 86)
	Harness.near(AirdropRules.safeRadius(100, 60, 14), 46) -- the circle is closing to 60
	Harness.near(AirdropRules.safeRadius(10, 10, 14), 0)
	Harness.near(AirdropRules.safeRadius(100, 150, 14), 86) -- never bigger than the circle now
end)

Harness.test("airdrop: pickSpot stays inside the circle and finds only open street", function()
	local roll = lcg(3)
	for _ = 1, 50 do
		local spot = AirdropRules.pickSpot(
			10,
			-5,
			40,
			20,
			roll,
			function(_x: number, _z: number): number?
				return 3
			end,
			{},
			0
		)
		Harness.truthy(spot ~= nil)
		if spot then
			local dx, dz = spot.x - 10, spot.z + 5
			Harness.truthy(dx * dx + dz * dz <= 40 * 40 + 1e-6)
			Harness.eq(spot.y, 3)
		end
	end
	-- Street is open only east of x = 30: every spot found must be there.
	local east = AirdropRules.pickSpot(
		0,
		0,
		50,
		200,
		lcg(7),
		function(x: number, _z: number): number?
			return if x > 30 then 0 else nil
		end,
		{},
		0
	)
	Harness.truthy(east ~= nil and east.x > 30)
	-- Never open: gives up (nil), does not loop forever.
	Harness.eq(
		AirdropRules.pickSpot(0, 0, 50, 10, rolls({ 0.5 }), function(): number?
			return nil
		end, {}, 0),
		nil
	)
	-- No room at all.
	Harness.eq(
		AirdropRules.pickSpot(0, 0, 0, 10, rolls({ 0.5 }), function(): number?
			return 0
		end, {}, 0),
		nil
	)
end)

Harness.test("airdrop: a second drop keeps away from the first", function()
	local first: AirdropRules.Spot = { x = 0, z = 0, y = 0 }
	local roll = lcg(11)
	for _ = 1, 30 do
		local spot = AirdropRules.pickSpot(0, 0, 60, 60, roll, function(): number?
			return 0
		end, { first }, 40)
		Harness.truthy(spot ~= nil)
		if spot then
			Harness.truthy(spot.x * spot.x + spot.z * spot.z >= 40 * 40 - 1e-6)
		end
	end
end)

Harness.test("airdrop: falling, landed (shut), opened", function()
	Harness.eq(AirdropRules.stage(0, 7, 11), "falling")
	Harness.eq(AirdropRules.stage(6.99, 7, 11), "falling")
	Harness.eq(AirdropRules.stage(7, 7, 11), "landed")
	Harness.eq(AirdropRules.stage(10.99, 7, 11), "landed")
	Harness.eq(AirdropRules.stage(11, 7, 11), "opened")
end)

Harness.test("airdrop: the crate comes down smoothly and sits on the street", function()
	Harness.near(AirdropRules.crateHeight(0, 0, 7, 90), 90)
	Harness.near(AirdropRules.crateHeight(7, 0, 7, 90), 0)
	Harness.near(AirdropRules.crateHeight(20, 0, 7, 90), 0)
	Harness.near(AirdropRules.crateHeight(-5, 0, 7, 90), 90)
	local last = 91
	for i = 0, 70 do
		local h = AirdropRules.crateHeight(i / 10, 0, 7, 90)
		Harness.truthy(h <= last + 1e-9, `never goes back up at {i}`)
		last = h
	end
	Harness.near(AirdropRules.crateHeight(1, 1, 1, 90), 0) -- a zero-length fall lands at once
end)

Harness.test("airdrop: the beam stays full while shut, then fades out", function()
	Harness.near(AirdropRules.beamStrength(5, 11, 1.5), 1)
	Harness.near(AirdropRules.beamStrength(11, 11, 1.5), 1)
	Harness.near(AirdropRules.beamStrength(11.75, 11, 1.5), 0.5)
	Harness.near(AirdropRules.beamStrength(12.5, 11, 1.5), 0)
	Harness.near(AirdropRules.beamStrength(30, 11, 1.5), 0)
	Harness.near(AirdropRules.beamStrength(12, 11, 0), 0)
end)

Harness.test("airdrop: the arrow points to the drop as seen from the camera", function()
	-- Camera looks down -Z (Roblox forward). +X is to the right.
	Harness.eq(AirdropRules.arrow(0, -50, 0, -1), "↑")
	Harness.eq(AirdropRules.arrow(50, 0, 0, -1), "→")
	Harness.eq(AirdropRules.arrow(0, 50, 0, -1), "↓")
	Harness.eq(AirdropRules.arrow(-50, 0, 0, -1), "←")
	Harness.eq(AirdropRules.arrow(40, -40, 0, -1), "↗")
	Harness.eq(AirdropRules.arrow(40, 40, 0, -1), "↘")
	Harness.eq(AirdropRules.arrow(-40, 40, 0, -1), "↙")
	Harness.eq(AirdropRules.arrow(-40, -40, 0, -1), "↖")
	-- Turn the camera to face +X: the drop that was "ahead" (-Z) is now on the left.
	Harness.eq(AirdropRules.arrow(0, -50, 1, 0), "←")
	-- Standing on it, or no camera: no arrow.
	Harness.eq(AirdropRules.arrow(0, 0, 0, -1), "")
	Harness.eq(AirdropRules.arrow(5, 5, 0, 0), "")
	Harness.eq(AirdropRules.distanceText(120.4), "120")
	Harness.eq(AirdropRules.distanceText(-3), "0")
end)

Harness.test("airdrop: config is sane (looks, times, loot)", function()
	Harness.truthy(cfg.looks[cfg.look] ~= nil, "the chosen look exists")
	for id, look in cfg.looks do
		for _, key in
			{
				"name",
				"color",
				"coreColor",
				"outerDiameter",
				"coreDiameter",
				"outerTransparency",
				"coreTransparency",
				"ringDiameter",
				"fallProp",
			}
		do
			Harness.truthy(look[key] ~= nil, `look {id} has {key}`)
		end
		Harness.truthy(
			look.coreDiameter < look.outerDiameter,
			`look {id}: core is thinner than the beam`
		)
		Harness.truthy(
			look.fallProp == "chute" or look.fallProp == "flame" or look.fallProp == "smoke",
			`look {id} prop`
		)
	end
	Harness.truthy(cfg.firstAtSeconds <= cfg.lastAtSeconds)
	Harness.truthy(cfg.count >= 1)
	-- The last drop (even with the most jitter) opens before final pressure and well before the match is cut off.
	local lastOpens = cfg.lastAtSeconds + cfg.jitterSeconds + cfg.fallSeconds + cfg.shutSeconds
	Harness.truthy(lastOpens < Config.Match.finalPressureAtSeconds, "opens before final pressure")
	Harness.truthy(cfg.fallSeconds > 0 and cfg.shutSeconds > 0 and cfg.beamFadeSeconds >= 0)
	Harness.truthy(cfg.loot.packs >= 0 and cfg.loot.orbs >= 0)
	Harness.truthy(cfg.spot.minApartStuds < Config.Zone.initialRadius, "two drops can fit")
end)

Harness.test("airdrop: remotes exist (a client may ask, only the server tells)", function()
	local ask = RemoteDefs.byName["AirdropRequest"]
	Harness.truthy(ask ~= nil and ask.direction == "toServer" and ask.rate ~= nil)
	local tell = RemoteDefs.byName["AirdropState"]
	Harness.truthy(tell ~= nil and tell.direction == "toClient")
end)

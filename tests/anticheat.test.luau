--!strict
-- Piece 27: pretend to be a cheating client and check the server says no.

local Harness = require("./harness")
local roblox = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Guard = require("../src/shared/Guard")
local RemoteDefs = require("../src/shared/RemoteDefs")
local StatBook = require("../src/shared/StatBook")
local UpgradeDefs = require("../src/shared/UpgradeDefs")
local MoveCheck = require("../src/server/AntiCheat/MoveCheck")
local PickupRules = require("../src/server/Pickups/PickupRules")
local RunUpgrades = require("../src/server/Upgrades/RunUpgrades")
local WeaponState = require("../src/server/Combat/WeaponState")

local V3 = roblox.Vector3
local WALK = Config.Movement.walkSpeed
local FRAME = 1 / 60

-- ===== remotes: junk arguments =====

local junk: { any } = {
	0 / 0,
	math.huge,
	-math.huge,
	1e300,
	"",
	string.rep("x", 5000),
	"../../evil",
	"a b",
	true,
	{},
	{ 1, 2, 3 },
	setmetatable({}, {
		__index = function()
			error("trap")
		end,
	}),
	function() end,
	V3.new(0 / 0, 0, 0),
	V3.new(math.huge, 0, 0),
	V3.new(1e9, 0, 0),
}

local function argOk(field: Guard.Field, v: any): boolean
	if v == nil then
		return field.optional == true
	end
	local k = field.kind
	if k == "number" or k == "integer" then
		return type(v) == "number"
			and v == v
			and math.abs(v) < 1e6
			and (field.min == nil or v >= field.min)
			and (field.max == nil or v <= field.max)
			and (k ~= "integer" or v == math.floor(v))
	elseif k == "boolean" then
		return type(v) == "boolean"
	elseif k == "string" or k == "id" then
		return type(v) == "string" and #v <= (field.maxLen or 64)
	elseif k == "vector3" or k == "unit3" then
		return typeof(v) == "Vector3" and v.Magnitude == v.Magnitude and v.Magnitude < 1e6
	end
	return false
end

Harness.test("bad client: every ask-remote has a shape check and a rate limit", function()
	local asks = 0
	for _, def in RemoteDefs.list do
		if def.direction == "toServer" then
			asks += 1
			Harness.truthy(def.schema ~= nil, def.name .. " has no schema")
			local rate = def.rate
			Harness.truthy(rate ~= nil, def.name .. " has no rate")
			if rate then
				Harness.truthy(rate.perSecond > 0 and rate.perSecond <= 30, def.name .. " rate")
				Harness.truthy(rate.burst >= 1 and rate.burst <= 10, def.name .. " burst")
			end
		end
	end
	Harness.truthy(asks >= 10, "found the ask-remotes")
end)

Harness.test("bad client: junk in any argument of any remote is refused", function()
	for _, def in RemoteDefs.list do
		local schema = def.schema
		if def.direction == "toServer" and schema ~= nil and #schema > 0 then
			for slot = 1, #schema do
				for _, bad in junk do
					local args = table.create(#schema)
					for i, field in schema do
						-- good filler for the other slots
						if field.kind == "vector3" then
							args[i] = V3.new(1, 0, 0)
						elseif field.kind == "unit3" then
							args[i] = V3.new(0, 0, 1)
						elseif field.kind == "id" or field.kind == "string" then
							args[i] = "ok_1"
						elseif field.kind == "boolean" then
							args[i] = true
						else
							args[i] = field.min or 1
						end
					end
					args[slot] = bad
					local packed = table.pack(table.unpack(args, 1, #schema))
					local ok, clean = Guard.validate(schema, packed)
					if ok then
						-- Only allowed if the value really fits the field (e.g. a fine-looking string).
						Harness.truthy(
							argOk(schema[slot], clean[slot]),
							`{def.name} let {tostring(bad)} through as {schema[slot].name}`
						)
					end
				end
			end
		end
	end
end)

Harness.test("bad client: extra arguments on any remote are refused", function()
	for _, def in RemoteDefs.list do
		local schema = def.schema
		if def.direction == "toServer" and schema ~= nil then
			local packed: any = { n = #schema + 1 }
			for i = 1, #schema + 1 do
				packed[i] = 1
			end
			Harness.eq((Guard.validate(schema, packed)), false, def.name)
		end
	end
end)

Harness.test("bad client: a flood of requests is cut to the rate limit", function()
	for _, def in RemoteDefs.list do
		local rate = def.rate
		if def.direction == "toServer" and rate ~= nil then
			local limiter = Guard.newLimiter(rate.perSecond, rate.burst)
			local let = 0
			-- 1000 requests in one second, from one player
			for i = 1, 1000 do
				if limiter:allow(42, i / 1000) then
					let += 1
				end
			end
			Harness.truthy(
				let <= rate.burst + math.ceil(rate.perSecond),
				`{def.name} let {let} through`
			)
			-- another player is not slowed down by the flood
			Harness.eq(limiter:allow(7, 1), true, def.name .. " other player")
		end
	end
end)

-- ===== fire rate =====

Harness.test("bad client: spamming the trigger never beats the fire rate", function()
	local fa = Config.Weapons.Firearm
	local stats =
		{ fireInterval = 1 / fa.fireRate, magazine = 1e6, reloadSeconds = fa.reloadSeconds }
	local w = WeaponState.new({ 1e6, 3 }, Config.Combat.fireTolerance)
	local shots = 0
	-- a cheat sends a shot every frame for 10 seconds
	for frame = 0, 600 do
		if w:tryFire(frame * FRAME, stats).ok then
			shots += 1
		end
	end
	Harness.truthy(shots <= math.floor(10 * fa.fireRate) + 2, `{shots} shots in 10s`)
end)

Harness.test("bad client: no shots while reloading, after a switch, or once out", function()
	local fa = Config.Weapons.Firearm
	local stats = { fireInterval = 1 / fa.fireRate, magazine = 2, reloadSeconds = 1 }
	local w = WeaponState.new({ 2, 3 }, Config.Combat.fireTolerance)
	Harness.eq(w:tryFire(0, stats).ok, true)
	Harness.eq(w:tryFire(1, stats).ok, true) -- last round: reload starts
	Harness.eq(w:tryFire(1.2, stats).ok, false, "reloading")
	w:update(2.1, function()
		return stats
	end)
	Harness.eq(w:equip(2, 2.1, 0.3), true)
	Harness.eq(w:tryFire(2.2, stats).ok, false, "still switching")
	w:lock()
	Harness.eq(w:tryFire(10, stats).ok, false, "knocked out")
end)

-- ===== pickups (XP) =====

local function orb(): PickupRules.Pickup
	return {
		id = "o1_1",
		matchId = 3,
		expiresAt = 100,
		reservedFor = nil,
		reservedUntil = 0,
		claimed = false,
	}
end

Harness.test(
	"bad client: XP orbs from far away, twice, or from an old match are refused",
	function()
		local r, s = Config.Pickups.collectRadius, Config.Pickups.claimSlack
		local o = orb()
		Harness.eq((PickupRules.check(o, "p1", 1, 500, r, s, 3)), false, "far")
		Harness.eq((PickupRules.check(o, "p1", 1, 0 / 0, r, s, 3)), false, "NaN distance")
		Harness.eq((PickupRules.check(o, "p1", 1, 0, r, s, 4)), false, "old match")
		Harness.eq((PickupRules.check(o, "p1", 1, 0, r, s, 3)), true)
		o.claimed = true
		Harness.eq((PickupRules.check(o, "p2", 1, 0, r, s, 3)), false, "taken")
	end
)

-- ===== upgrades =====

Harness.test(
	"bad client: upgrade picks that are fake, repeated or out of range do nothing",
	function()
		local t = { now = 0 }
		local ctx = {
			base = StatBook.base(Config),
			hasExplosive = false,
			weaponNames = { firearm = "Volt Pistol", explosive = "Arc Mortar" },
		}
		local run = RunUpgrades.new(UpgradeDefs, ctx, function()
			return 0.5
		end, function()
			return t.now
		end, Config.Upgrades.selectionLockSeconds)
		run:enroll("p1", 1)
		local offer = run:issue("p1")
		t.now = 5
		Harness.eq(run:choose("p1", 1, "u1-p1-999", 1).ok, false, "made-up offer")
		Harness.eq(run:choose("p1", 1, offer.offerId, 0).ok, false, "option 0")
		Harness.eq(run:choose("p1", 1, offer.offerId, 99).ok, false, "option 99")
		Harness.eq(run:choose("p1", 1, offer.offerId, 1.5).ok, false, "option 1.5")
		Harness.eq(run:choose("p1", 2, offer.offerId, 1).ok, false, "other match")
		Harness.eq(run:choose("p2", 1, offer.offerId, 1).ok, false, "someone else's offer")
		Harness.eq(run:choose("p1", 1, offer.offerId, 1).ok, true)
		Harness.eq(run:choose("p1", 1, offer.offerId, 1).ok, false, "same pick twice")
	end
)

-- ===== movement: teleport, speed, fly =====

local function newCheck(): any
	return MoveCheck.new(Config.AntiCheat)
end

-- Walks in +X at `speed` for `seconds`, stepping every frame. Returns how many snaps happened.
local function walk(
	check: any,
	id: string,
	startX: number,
	speed: number,
	seconds: number,
	t0: number
)
	local snaps = 0
	local x = startX
	local t = t0
	for _ = 1, math.floor(seconds / FRAME) do
		t += FRAME
		x += speed * FRAME
		local verdict, gx = check:step(id, x, 0, 0, t, WALK)
		if verdict == "snap" then
			snaps += 1
			x = gx
		end
	end
	return snaps, x, t
end

Harness.test("move: an honest walk is never put back", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	local snaps, x = walk(check, "p1", 0, WALK, 10, 0)
	Harness.eq(snaps, 0)
	Harness.near(x, WALK * 10, 1)
end)

Harness.test("move: a phone lag lump (half a second of walking at once) is fine", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	check:step("p1", 0, 0, 0, 2, WALK) -- stood still
	Harness.eq((check:step("p1", WALK * 0.5, 0, 0, 2.05, WALK)), "ok")
end)

Harness.test("bad client: a teleport is held, then put back", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	check:step("p1", 0, 0, 0, 1, WALK)
	local verdict = check:step("p1", 80, 0, 0, 1 + FRAME, WALK)
	Harness.eq(verdict, "hold")
	Harness.eq(check:isHeld("p1"), true, "shots and pickups wait")
	local gx = check:good("p1")
	Harness.eq(gx, 0, "trusted spot stays put")
	local final, sx = check:step("p1", 80, 0, 0, 1 + Config.AntiCheat.graceSeconds + 0.1, WALK)
	Harness.eq(final, "snap")
	Harness.eq(sx, 0, "back where it was")
end)

Harness.test("bad client: a speed hack (double speed) gets put back", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	local snaps = walk(check, "p1", 0, WALK * 2, 10, 0)
	Harness.truthy(snaps >= 2, `only {snaps} snaps`)
end)

Harness.test("bad client: a small speed hack (1.5x) still loses", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	local snaps, x = walk(check, "p1", 0, WALK * 1.5, 20, 0)
	Harness.truthy(snaps >= 1, "caught")
	Harness.truthy(x <= WALK * (1 + Config.AntiCheat.speedSlack) * 20 + 40, `got to {x}`)
end)

Harness.test("bad client: flying straight up is put back; walking up a ramp is not", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	local t = 0
	local verdict = "ok"
	for i = 1, 60 do
		t += FRAME
		verdict = check:step("p1", 0, i * 0.5, 0, t, WALK)
		if verdict ~= "ok" then
			break
		end
	end
	Harness.truthy(verdict ~= "ok", "fly noticed")

	local ramp = newCheck()
	ramp:reset("p2", 0, 0, 0, 0)
	t = 0
	for i = 1, 120 do
		t += FRAME
		local x = i * WALK * FRAME
		Harness.eq((ramp:step("p2", x, x * 0.9, 0, t, WALK)), "ok", "ramp " .. i)
	end
end)

Harness.test(
	"move: a slide the server accepted goes through, even if the move arrives first",
	function()
		local check = newCheck()
		check:reset("p1", 0, 0, 0, 0)
		check:step("p1", 0, 0, 0, 0.1, WALK)
		local cap = WALK * (1 + Config.AntiCheat.speedSlack) * Config.AntiCheat.burstSeconds
			+ Config.AntiCheat.leeway
		-- The body lands a slide further than walking explains, before the slide request is read.
		local far = cap + Config.Slide.distance - 2
		Harness.eq(
			(check:step("p1", far, 0, 0, 0.12, WALK)),
			"hold",
			"too far before the slide is known"
		)
		check:addCredit("p1", Config.Slide.distance + Config.Slide.endTolerance, 0.15)
		Harness.eq((check:step("p1", far, 0, 0, 0.2, WALK)), "ok", "slide explains it")
		Harness.eq(check:isHeld("p1"), false)
	end
)

Harness.test("bad client: slide credit runs out, it cannot be saved up", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	check:step("p1", 0, 0, 0, 1, WALK)
	check:addCredit("p1", 18, 1)
	-- wait long past the credit, then try to use it
	check:step("p1", 0, 0, 0, 10, WALK)
	local cap = WALK * (1 + Config.AntiCheat.speedSlack) * Config.AntiCheat.burstSeconds
		+ Config.AntiCheat.leeway
	Harness.eq((check:step("p1", cap + 10, 0, 0, 10 + FRAME, WALK)), "hold")
end)

Harness.test("bad client: NaN or huge positions never count as good", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	Harness.eq((check:step("p1", 0 / 0, 0, 0, 0.1, WALK)), "hold")
	Harness.eq((check:step("p1", 1e9, 0, 0, 1, WALK)), "snap")
	Harness.eq((check:good("p1")), 0)
end)

Harness.test("move: the server placing a body (spawn) is trusted", function()
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	check:reset("p1", 500, 10, -300, 1)
	Harness.eq((check:step("p1", 500, 10, -300, 1 + FRAME, WALK)), "ok")
end)

Harness.test("move: a raised WalkSpeed on the client does not raise the server's limit", function()
	-- The server always passes its own WalkSpeed; a cheat moving at 100 is held.
	local check = newCheck()
	check:reset("p1", 0, 0, 0, 0)
	local snaps = walk(check, "p1", 0, 100, 3, 0)
	Harness.truthy(snaps >= 1)
end)

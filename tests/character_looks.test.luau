--!strict
local Harness = require("./harness")
local Looks = require("../src/shared/Character/Looks")
local RemoteDefs = require("../src/shared/RemoteDefs")

local test, eq, near, truthy = Harness.test, Harness.eq, Harness.near, Harness.truthy

local function isHex(text: any): boolean
	return type(text) == "string" and string.match(text, "^#%x%x%x%x%x%x$") ~= nil
end

for _, name in Looks.NAMES do
	local def = Looks.get(name)

	test(`{name}: every part sits on a real R15 part with a color that exists`, function()
		eq(def.name, name)
		for i, part in def.parts do
			truthy(Looks.R15_PARTS[part.on], `part {i} is on '{part.on}'`)
			truthy(
				def.palette[part.role] ~= nil,
				`part {i} uses role '{part.role}' that the palette lacks`
			)
			eq(#part.size, 3)
			eq(#part.pos, 3)
			for _, n in part.size do
				truthy(n > 0 and n < 6, `part {i} size {n}`)
			end
		end
	end)

	test(`{name}: palette colors are valid hex, and the body roles are all set`, function()
		for role, hex in def.palette do
			truthy(isHex(hex), `{role} = {hex}`)
		end
		for partName, role in Looks.BODY_ROLES do
			truthy(def.palette[role] ~= nil, `{partName} needs role {role}`)
		end
	end)

	test(`{name}: limited glow and a sane part count`, function()
		local glow, total = 0, #def.parts
		for _, part in def.parts do
			if part.role == "glow" then
				glow += 1
			end
		end
		truthy(glow >= 1 and glow <= 6, `glow parts: {glow}`)
		truthy(total >= 12 and total <= 60, `parts: {total}`)
	end)

	test(`{name}: the head and shoulders have their own shape`, function()
		local onHead, onTorso = 0, 0
		for _, part in def.parts do
			if part.on == "Head" then
				onHead += 1
			elseif part.on == "UpperTorso" then
				onTorso += 1
			end
		end
		truthy(onHead >= 6, `head parts {onHead}`)
		truthy(onTorso >= 6, `torso parts {onTorso}`)
		truthy(def.headScale >= 1.2 and def.headScale <= 1.6, "a big but allowed head")
	end)

	test(`{name}: bots leave the chest clear for the target and keep the rest`, function()
		local bot = Looks.partsFor(def, true)
		local player = Looks.partsFor(def, false)
		truthy(#bot < #player, "something is left off bots")
		truthy(#bot > #player / 2, "most of the look stays")
		for _, part in bot do
			truthy(part.skipBot ~= true)
		end
	end)
end

test("an unknown or missing look name falls back to Runner", function()
	eq(Looks.get("Nope").name, "Runner")
	eq(Looks.get(nil).name, "Runner")
	eq(Looks.get("Spark").name, "Spark")
end)

test("the three looks are different fighters", function()
	local a, b, c = Looks.get("Runner"), Looks.get("Courier"), Looks.get("Spark")
	truthy(
		a.palette.body ~= b.palette.body
			and b.palette.body ~= c.palette.body
			and a.palette.body ~= c.palette.body
	)
	eq(c.hideHead, true)
	eq(a.hideHead, nil)
end)

test("bots wear the Crash Dummy body and legs, the trim stays", function()
	local def = Looks.get("Runner")
	local palette = Looks.paletteFor(def, { body = "#FFC44D", legs = "#2A2A2E" })
	eq(palette.body, "#FFC44D")
	eq(palette.head, "#FFC44D")
	eq(palette.legs, "#2A2A2E")
	eq(palette.coral, def.palette.coral)
	eq(def.palette.body, "#14243A") -- the look itself is untouched
	eq(Looks.paletteFor(def, nil).body, "#14243A")
end)

test("Spark's shoulder spikes mirror each other and lean outward", function()
	local spikes = {}
	for _, part in Looks.get("Spark").parts do
		if part.on == "UpperTorso" and part.rot ~= nil and math.abs(part.rot[3]) == 54 then
			table.insert(spikes, part)
		end
	end
	eq(#spikes, 6)
	for _, s in spikes do
		if (s.rot :: { number })[3] > 0 then
			truthy(s.pos[1] < -1.4 + 0.01, "left spike tip leans to -X")
		else
			truthy(s.pos[1] > 1.4 - 0.01, "right spike tip leans to +X")
		end
	end
	local tipL, tipR = spikes[3], spikes[6]
	near(tipL.pos[1], -tipR.pos[1], 1e-9)
	near(tipL.pos[2], tipR.pos[2], 1e-9)
end)

test("the look request is a guarded, rate limited ask that names a short string", function()
	local def = RemoteDefs.byName["SetLookRequest"]
	truthy(def ~= nil)
	eq(def.direction, "toServer")
	eq(#(def.schema :: { any }), 1)
	truthy((def.rate :: any).perSecond <= 3)
	for _, name in Looks.NAMES do
		truthy(#name <= (def.schema :: any)[1].maxLen)
	end
end)

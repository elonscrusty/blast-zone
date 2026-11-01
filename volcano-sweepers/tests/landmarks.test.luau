--!strict
-- Checks the pure part lists of the big landmarks (volcano, lava pool, hot spring, lighthouse).
-- Only the pure files are loaded here; ModelBuild and Landmarks need Roblox and are not.

local Harness = require("./harness")
local Parts = require("../src/server/World/Models/Parts")
local BigVolcano = require("../src/server/World/Models/BigVolcano")
local HotSpring = require("../src/server/World/Models/HotSpring")
local LavaPool = require("../src/server/World/Models/LavaPool")
local Lighthouse = require("../src/server/World/Models/Lighthouse")

type Model = { variants: { string }, spec: (string, number?) -> Parts.List }

local MODELS: { [string]: Model } = {
	volcano = BigVolcano,
	lava = LavaPool,
	spring = HotSpring,
	lighthouse = Lighthouse,
}
-- phone-light budgets: parts per landmark
local BUDGET: { [string]: number } = { volcano = 110, lava = 70, spring = 60, lighthouse = 70 }
local SET_BUDGET = 300 -- all four of one look together

local function each(fn: (kind: string, variant: string, list: Parts.List) -> ())
	for kind, m in MODELS do
		for _, v in m.variants do
			fn(kind, v, m.spec(v, 1))
		end
	end
end

local function finite(n: number): boolean
	return n == n and n > -1e9 and n < 1e9
end

Harness.test("landmarks: every landmark has looks A, B and C", function()
	for kind, m in MODELS do
		Harness.eq(#m.variants, 3, kind)
		Harness.eq(m.variants[1], "A")
		Harness.eq(m.variants[2], "B")
		Harness.eq(m.variants[3], "C")
	end
end)

Harness.test("landmarks: every part is well formed", function()
	each(function(kind, v, list)
		Harness.eq(list.variant, v)
		Harness.truthy(#list.parts >= 10, `{kind} {v} too few parts`)
		for i, p in list.parts do
			local where = `{kind} {v} part {i} ({p.name})`
			Harness.truthy(Parts.KINDS[p.kind], `{where}: kind {p.kind}`)
			Harness.truthy(Parts.MATERIALS[p.material], `{where}: material {p.material}`)
			Harness.truthy(
				string.match(p.color, "^#%x%x%x%x%x%x$") ~= nil,
				`{where}: colour {p.color}`
			)
			Harness.truthy(p.transparency >= 0 and p.transparency <= 1, `{where}: transparency`)
			Harness.eq(#p.pos, 3, where)
			Harness.eq(#p.size, 3, where)
			Harness.eq(#p.rot, 3, where)
			for k = 1, 3 do
				Harness.truthy(finite(p.pos[k]) and finite(p.rot[k]), `{where}: number`)
				Harness.truthy(finite(p.size[k]) and p.size[k] > 0.05, `{where}: size`)
			end
			if p.kind == "ball" or p.kind == "cyl" then
				Harness.near(p.size[1], p.size[3], 1e-9, `{where}: round parts must be round`)
			end
			if p.kind == "ball" then
				Harness.near(p.size[1], p.size[2], 1e-9, `{where}: ball must be a sphere`)
			end
			Harness.truthy(
				p.group == nil or p.group == "glow" or p.group == "beam",
				`{where}: group`
			)
		end
		for i, f in list.fx do
			Harness.truthy(Parts.FX_KINDS[f.kind], `{kind} {v} fx {i}: kind {f.kind}`)
			Harness.truthy(f.radius > 0, `{kind} {v} fx {i}: radius`)
		end
	end)
end)

Harness.test("landmarks: part counts stay phone-light", function()
	for _, variant in { "A", "B", "C" } do
		local total = 0
		for kind, m in MODELS do
			local n = #m.spec(variant, 1).parts
			Harness.truthy(n <= (BUDGET[kind] :: number), `{kind} {variant} has {n} parts`)
			total += n
		end
		Harness.truthy(total <= SET_BUDGET, `look {variant} has {total} parts in all`)
	end
end)

Harness.test("landmarks: same look twice is identical (no hidden randomness)", function()
	each(function(kind, v, list)
		local again = (MODELS[kind] :: Model).spec(v, 1)
		Harness.eq(#again.parts, #list.parts)
		for i, p in list.parts do
			local q = again.parts[i]
			Harness.eq(q.name, p.name)
			Harness.eq(q.pos[1], p.pos[1])
			Harness.eq(q.pos[3], p.pos[3])
			Harness.eq(q.color, p.color)
		end
	end)
end)

Harness.test("landmarks: only the volcano core is invisible, and it is solid", function()
	each(function(kind, v, list)
		for _, p in list.parts do
			if p.transparency >= 1 then
				Harness.eq(kind, "volcano")
				Harness.eq(p.name, "ConeCollision")
				Harness.truthy(p.collide, "core must collide")
			end
		end
		if kind == "volcano" then
			local found = 0
			for _, p in list.parts do
				if p.name == "ConeCollision" then
					found += 1
				end
			end
			Harness.eq(found, 1, `volcano {v} core`)
		end
	end)
end)

Harness.test("landmarks: lava, water and lamps are in the glow group", function()
	each(function(kind, v, list)
		local glow = 0
		for _, p in list.parts do
			if p.group == "glow" then
				glow += 1
			end
		end
		Harness.truthy(glow >= 1, `{kind} {v} has {glow} glow parts`)
	end)
end)

Harness.test("landmarks: lighthouses have a beam that can spin around the lamp", function()
	for _, v in Lighthouse.variants do
		local list = Lighthouse.spec(v, 1)
		local pivot = list.pivots.beam
		Harness.truthy(pivot ~= nil, `lighthouse {v} needs a beam pivot`)
		local beams = 0
		local lampY = 0
		for _, p in list.parts do
			if p.group == "beam" then
				beams += 1
				Harness.truthy(p.transparency > 0.3, "beam must be see-through")
				Harness.truthy(not p.collide, "beam must not collide")
				Harness.near(p.pos[2], (pivot :: Parts.Vec)[2], 1e-6, "beam sits at lamp height")
			elseif p.name == "Lamp" then
				lampY = p.pos[2]
			end
		end
		Harness.truthy(beams >= 2, `lighthouse {v} beam parts`)
		Harness.truthy(math.abs(lampY - (pivot :: Parts.Vec)[2]) < 2, "lamp and beam line up")
		Harness.near((pivot :: Parts.Vec)[1], 0, 1e-9)
		Harness.near((pivot :: Parts.Vec)[3], 0, 1e-9)
	end
end)

Harness.test("landmarks: nothing else has a beam pivot", function()
	each(function(kind, _, list)
		if kind ~= "lighthouse" then
			Harness.truthy(list.pivots.beam == nil, `{kind} must not have a beam`)
		end
	end)
end)

Harness.test("landmarks: sizes are big enough to read from far away", function()
	each(function(kind, v, list)
		local reach, top = Parts.bounds(list)
		if kind == "volcano" then
			Harness.truthy(top >= 140 and top <= 260, `volcano {v} height {top}`)
			Harness.truthy(reach >= 85 and reach <= 140, `volcano {v} reach {reach}`)
		elseif kind == "lighthouse" then
			Harness.truthy(top >= 60 and top <= 100, `lighthouse {v} height {top}`)
		else
			Harness.truthy(reach >= 15 and reach <= 50, `{kind} {v} reach {reach}`)
		end
		for _, p in list.parts do
			Harness.truthy(
				p.pos[2] - p.size[2] / 2 > -6,
				`{kind} {v} {p.name} sinks into the ground`
			)
		end
	end)
end)

Harness.test("landmarks: scale grows every size and position, angles stay", function()
	each(function(kind, v, list)
		local big = (MODELS[kind] :: Model).spec(v, 2)
		Harness.eq(#big.parts, #list.parts)
		for i, p in list.parts do
			local q = big.parts[i]
			Harness.near(q.pos[2], p.pos[2] * 2, 1e-9)
			Harness.near(q.size[1], p.size[1] * 2, 1e-9)
			Harness.near(q.rot[2], p.rot[2], 1e-12)
		end
		local pivot = list.pivots.beam
		if pivot ~= nil then
			Harness.near((big.pivots.beam :: Parts.Vec)[2], pivot[2] * 2, 1e-9)
		end
	end)
end)

Harness.test("parts: a slab lies on the slope between its two points", function()
	local list = Parts.new("T", "A")
	-- straight up wall at radius 10, from y 0 to y 10, at angle 0 (+X)
	Parts.slab(list, "wall", 10, 0, 10, 10, 0, 4, 1, "#FFFFFF", 0)
	local p = list.parts[1]
	Harness.near(p.pos[1], 10, 1e-9)
	Harness.near(p.pos[2], 5, 1e-9)
	Harness.near(p.pos[3], 0, 1e-9)
	Harness.near(p.size[3], 11, 1e-9, "length = run + 1")
	-- a 45 degree slope pushed 2 studs out along its normal
	local list2 = Parts.new("T", "A")
	Parts.slab(list2, "ramp", 20, 0, 10, 10, math.pi / 2, 4, 1, "#FFFFFF", 2)
	local q = list2.parts[1]
	Harness.near(q.pos[1], 0, 1e-9)
	Harness.near(q.pos[3], 15 + 2 * math.sin(math.pi / 4), 1e-9)
	Harness.near(q.pos[2], 5 + 2 * math.cos(math.pi / 4), 1e-9)
end)

Harness.test("parts: rand is steady and stays in range; lerpHex mixes colours", function()
	for i = 1, 50 do
		local r = Parts.rand(7, i)
		Harness.truthy(r >= 0 and r < 1)
		Harness.eq(r, Parts.rand(7, i))
	end
	Harness.truthy(Parts.rand(7, 1) ~= Parts.rand(8, 1) or Parts.rand(7, 2) ~= Parts.rand(8, 2))
	Harness.eq(Parts.lerpHex("#000000", "#FFFFFF", 0.5), "#808080")
	Harness.eq(Parts.lerpHex("#FF0000", "#FF0000", 0.3), "#FF0000")
end)

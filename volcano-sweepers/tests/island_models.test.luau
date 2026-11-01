--!strict
-- Island model kit: every model in every look is small, grounded, deterministic and well formed.
local Harness = require("./harness")
local Kit = require("../src/server/World/Models/Kit")
local Registry = require("../src/server/World/Models/Registry")
local Styles = require("../src/server/World/Models/Styles")

local KINDS = { block = true, wedge = true, ball = true, cyl = true }
local MATS = {
	SmoothPlastic = true,
	Neon = true,
	Wood = true,
	Grass = true,
	Slate = true,
	Basalt = true,
	Marble = true,
}
local VARIANTS = { 1, 7, 31, 88, 250, 999 }

local function finite(n: number): boolean
	return n == n and n > -1e6 and n < 1e6
end

local function each(fn: (name: string, style: string, v: number, m: Kit.Model) -> ())
	for _, name in Registry.names do
		for _, style in Styles.ids do
			for _, v in VARIANTS do
				fn(name, style, v, Registry.spec(name, { style = style, v = v }))
			end
		end
	end
end

-- Rotate a vector by Euler XYZ (matrix = Rx * Ry * Rz), the way CFrame.Angles does.
local function rotate(e: Kit.V3, x: number, y: number, z: number): { number }
	local cx, sx, cy, sy, cz, sz =
		math.cos(e.x), math.sin(e.x), math.cos(e.y), math.sin(e.y), math.cos(e.z), math.sin(e.z)
	-- Rz first
	local x1, y1, z1 = cz * x - sz * y, sz * x + cz * y, z
	-- then Ry
	local x2, y2, z2 = cy * x1 + sy * z1, y1, -sy * x1 + cy * z1
	-- then Rx
	return { x2, cx * y2 - sx * z2, sx * y2 + cx * z2 }
end

Harness.test("models: registry lists all eight and rejects unknown names", function()
	Harness.eq(#Registry.names, 8)
	for _, name in Registry.names do
		Harness.truthy((Registry.maxParts[name] or 0) > 0, `{name} has no part budget`)
		Harness.eq(Registry.spec(name).name, name)
	end
	local ok = pcall(Registry.spec, "NoSuchThing")
	Harness.eq(ok, false)
	Harness.eq(Registry.spec("Palm", { style = "nonsense" }).style, "toy")
	Harness.eq(Registry.spec("Palm").style, "toy")
end)

Harness.test("models: part counts stay inside each model's phone budget", function()
	each(function(name, style, v, m)
		local n = #m.parts
		Harness.truthy(n >= 3, `{name}/{style}/{v} has only {n} parts`)
		Harness.truthy(
			n <= Registry.maxParts[name],
			`{name}/{style}/{v} uses {n} parts, budget {Registry.maxParts[name]}`
		)
	end)
end)

Harness.test("models: every part is well formed", function()
	each(function(name, style, v, m)
		for i, s in m.parts do
			local tag = `{name}/{style}/{v} part {i} ({s.name})`
			Harness.truthy(KINDS[s.kind], `{tag}: bad kind {s.kind}`)
			Harness.truthy(MATS[s.mat], `{tag}: bad material {s.mat}`)
			Harness.truthy(
				string.match(s.color, "^#%x%x%x%x%x%x$") ~= nil,
				`{tag}: bad colour {s.color}`
			)
			for _, n in { s.x, s.y, s.z, s.sx, s.sy, s.sz, s.rx, s.ry, s.rz } do
				Harness.truthy(finite(n), `{tag}: bad number`)
			end
			Harness.truthy(s.sx >= 0.1 and s.sy >= 0.1 and s.sz >= 0.1, `{tag}: too thin`)
			Harness.truthy(s.alpha >= 0 and s.alpha <= 1, `{tag}: alpha`)
			Harness.eq(s.neon, s.mat == "Neon", `{tag}: neon flag and material disagree`)
			if s.kind == "ball" then
				Harness.eq(s.sx, s.sy, `{tag}: ball must be round`)
				Harness.eq(s.sx, s.sz, `{tag}: ball must be round`)
			end
			if s.kind == "cyl" then
				Harness.eq(s.sx, s.sz, `{tag}: cylinder must be round`)
			end
		end
	end)
end)

Harness.test("models: grounded, inside the footprint and not too tall", function()
	each(function(name, style, v, m)
		local b = Kit.bounds(m)
		local tag = `{name}/{style}/{v}`
		Harness.truthy(b.minY >= -1.2, `{tag}: sinks too deep ({b.minY})`)
		Harness.truthy(b.minY <= 0.35, `{tag}: floats ({b.minY})`)
		Harness.truthy(b.maxY <= 20, `{tag}: too tall ({b.maxY})`)
		local reach = math.max(math.abs(b.minX), math.abs(b.maxX))
		local deep = math.max(math.abs(b.minZ), math.abs(b.maxZ))
		Harness.truthy(reach <= m.halfX + 2.5, `{tag}: sticks out sideways ({reach} vs {m.halfX})`)
		Harness.truthy(deep <= m.halfZ + 2.5, `{tag}: sticks out front/back ({deep} vs {m.halfZ})`)
	end)
end)

Harness.test("models: only a few solid parts, and no thin solid sticks", function()
	each(function(name, style, v, m)
		local solid = 0
		for _, s in m.parts do
			if s.collide then
				solid += 1
				Harness.truthy(
					math.min(s.sx, s.sz) >= 0.5,
					`{name}/{style}: solid part {s.name} is too thin`
				)
			end
		end
		Harness.truthy(solid <= 12, `{name}/{style}/{v}: {solid} solid parts`)
	end)
end)

Harness.test("models: same inputs give the same model, other variants differ", function()
	for _, name in { "Palm", "Rocks", "Spire" } do
		for _, style in Styles.ids do
			local a = Registry.spec(name, { style = style, v = 12 })
			local b = Registry.spec(name, { style = style, v = 12 })
			local c = Registry.spec(name, { style = style, v = 713 })
			local function key(m: Kit.Model): string
				local out: { string } = {}
				for _, s in m.parts do
					table.insert(out, `{s.name}{s.x}{s.y}{s.z}{s.sx}{s.sy}{s.rx}{s.ry}{s.rz}`)
				end
				return table.concat(out, "|")
			end
			Harness.eq(key(a), key(b), `{name}/{style} not deterministic`)
			Harness.truthy(key(a) ~= key(c), `{name}/{style} ignores v`)
		end
	end
end)

Harness.test("models: the three looks really differ", function()
	for _, name in Registry.names do
		local colors: { [string]: { [string]: boolean } } = {}
		for _, style in Styles.ids do
			local set: { [string]: boolean } = {}
			for _, s in Registry.spec(name, { style = style }).parts do
				set[s.color] = true
			end
			colors[style] = set
		end
		local shared = 0
		local total = 0
		for c in colors.toy do
			total += 1
			if colors.basalt[c] then
				shared += 1
			end
		end
		Harness.truthy(shared < total, `{name}: toy and basalt use the same colours`)
	end
end)

Harness.test("models: Trade Hut has a Counter, a sell spot and a sign in every look", function()
	for _, style in Styles.ids do
		local m = Registry.spec("TradeHut", { style = style })
		Harness.truthy(m.anchors.sell ~= nil, `{style}: no sell anchor`)
		Harness.truthy(m.anchors.sign ~= nil, `{style}: no sign anchor`)
		local counter, sign = nil, nil
		for _, s in m.parts do
			if s.name == "Counter" then
				counter = s
			elseif s.name == "Sign" then
				sign = s
			end
		end
		Harness.truthy(counter ~= nil and counter.collide, `{style}: counter missing or not solid`)
		Harness.truthy(sign ~= nil and sign.text == "TRADE HUT", `{style}: sign text`)
		-- the sell spot is just above the counter top, on the customer (front, -Z) side
		local a = m.anchors.sell
		Harness.truthy(
			counter ~= nil and math.abs(a.y - (counter.y + counter.sy / 2)) < 1,
			"sell spot height"
		)
		Harness.truthy(a.z < 0, "sell spot should face the front")
		Harness.eq(Registry.spec("TradeHut", { style = style, text = "SELL" }).parts[1].text, nil)
	end
end)

Harness.test("models: Gate keeps its 18 stud opening, plate, beam and zone colours", function()
	for _, style in Styles.ids do
		local m = Registry.spec("Gate", { style = style, accent = "#112233", ground = "#445566" })
		local plate, beam
		for _, s in m.parts do
			if s.name == "GatePlate" then
				plate = s
			elseif s.name == "Beam" then
				beam = s
			end
		end
		Harness.truthy(plate ~= nil and beam ~= nil, `{style}: GatePlate or Beam missing`)
		Harness.eq(plate.color, "#112233", `{style}: plate ignores accent`)
		Harness.truthy(not plate.collide, "plate must never block movement")
		Harness.truthy(plate.sx >= 16, "plate wide enough")
		Harness.truthy(
			m.anchors.sign ~= nil and m.anchors.sign.y > beam.y - 1,
			`{style}: sign anchor`
		)
		-- nothing solid inside the walk-through opening
		for _, s in m.parts do
			if s.collide then
				local b = Kit.partBounds(s)
				Harness.truthy(
					b.minX >= 7 or b.maxX <= -7,
					`{style}: solid {s.name} blocks the opening`
				)
			end
		end
		-- the zone ground colour shows somewhere
		local found = false
		for _, s in m.parts do
			found = found or s.color == "#445566"
		end
		Harness.truthy(found, `{style}: zone ground colour unused`)
	end
end)

Harness.test("models: signs carry their text on a board", function()
	for _, style in Styles.ids do
		local m = Registry.spec("Sign", { style = style, text = "GATE" })
		local found = false
		for _, s in m.parts do
			if s.name == "Board" then
				found = s.text == "GATE"
			end
		end
		Harness.truthy(found, `{style}: Board text`)
		Harness.truthy(m.anchors.board ~= nil, `{style}: board anchor`)
	end
end)

Harness.test("models: palms stand tall and only the foot is solid", function()
	for _, style in Styles.ids do
		for _, v in VARIANTS do
			local m = Registry.spec("Palm", { style = style, v = v })
			local b = Kit.bounds(m)
			Harness.truthy(b.maxY >= 7 and b.maxY <= 16, `{style}/{v}: palm height {b.maxY}`)
			local top = m.anchors.top
			Harness.truthy(top ~= nil and top.y >= 8, "palm top anchor")
			for _, s in m.parts do
				if s.collide then
					Harness.truthy(s.y < 3, `{style}: only the foot of the trunk may be solid`)
				end
			end
		end
	end
end)

Harness.test("kit: pole and look helpers aim the right way", function()
	local dirs = {
		{ 0, 1, 0 },
		{ 1, 0, 0 },
		{ 0, 0, 1 },
		{ -1, 2, 0.5 },
		{ 0.3, 1, -0.4 },
		{ -2, -1, 3 },
	}
	for _, d in dirs do
		local len = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
		local e = Kit.upEuler(Kit.v3(d[1], d[2], d[3]))
		local up = rotate(e, 0, 1, 0)
		Harness.near(up[1], d[1] / len, 1e-6, "pole x")
		Harness.near(up[2], d[2] / len, 1e-6, "pole y")
		Harness.near(up[3], d[3] / len, 1e-6, "pole z")
	end
	for _, d in dirs do
		local len = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
		local e = Kit.lookEuler(Kit.v3(d[1], d[2], d[3]))
		local fwd = rotate(e, 0, 0, -1) -- local -Z is the front, like CFrame.lookAt
		Harness.near(fwd[1], d[1] / len, 1e-6, "look x")
		Harness.near(fwd[2], d[2] / len, 1e-6, "look y")
		Harness.near(fwd[3], d[3] / len, 1e-6, "look z")
	end
end)

Harness.test("kit: gable halves climb towards the middle and meet there", function()
	local m = Kit.new("T", "toy", 5, 5)
	Kit.gable(m, "Roof", 2, 5, 3, 10, 6, 4, "#FFFFFF")
	Harness.eq(#m.parts, 2)
	local left, right = m.parts[1], m.parts[2]
	-- the wedge's tall edge is local +Z: it must point at the middle of the roof (x = 2)
	local lt = rotate(Kit.v3(left.rx, left.ry, left.rz), 0, 0, 1)
	local rt = rotate(Kit.v3(right.rx, right.ry, right.rz), 0, 0, 1)
	Harness.near(lt[1], 1, 1e-6, "left tall edge points +X")
	Harness.near(rt[1], -1, 1e-6, "right tall edge points -X")
	Harness.truthy(left.x < 2 and right.x > 2, "halves on either side")
	local b = Kit.bounds(m)
	Harness.near(b.minX, -3, 0.05, "roof left edge")
	Harness.near(b.maxX, 7, 0.05, "roof right edge")
	Harness.near(b.minZ, 0, 0.05, "roof front edge")
	Harness.near(b.maxZ, 6, 0.05, "roof back edge")
end)

Harness.test("kit: unit() is steady and spread out", function()
	Harness.eq(Kit.unit(5, 1), Kit.unit(5, 1))
	local lo, hi = 1, 0
	for v = 1, 200 do
		local x = Kit.unit(v, 3)
		Harness.truthy(x >= 0 and x < 1, "range")
		lo = math.min(lo, x)
		hi = math.max(hi, x)
	end
	Harness.truthy(lo < 0.1 and hi > 0.9, "spread")
	Harness.eq(Kit.pick({ "a", "b", "c" }, 4), "b")
end)

Harness.test("models: one of each model is a small part of the island's part budget", function()
	local total = 0
	for _, name in Registry.names do
		for _, style in Styles.ids do
			total += #Registry.spec(name, { style = style }).parts
		end
	end
	-- 3 looks x 8 models: tens of parts each, never thousands
	Harness.truthy(total <= 8 * 3 * 48, `kit too heavy: {total}`)
end)

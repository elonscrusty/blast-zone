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

Harness.test("models: mushrooms are deterministic and v picks the cap", function()
	local function key(m: Kit.Model): string
		local out: { string } = {}
		for _, s in m.parts do
			table.insert(out, `{s.name}{s.x}{s.y}{s.z}{s.sx}{s.color}`)
		end
		return table.concat(out, "|")
	end
	for _, style in Styles.ids do
		for _, v in VARIANTS do
			local a = Registry.spec("Mushroom", { style = style, v = v })
			local b = Registry.spec("Mushroom", { style = style, v = v })
			Harness.eq(key(a), key(b), `Mushroom/{style}/{v} not deterministic`)
		end
	end
	-- toy and tiki pick their cap colour from v
	for _, style in { "toy", "tiki" } do
		local a = Registry.spec("Mushroom", { style = style, v = 12 })
		local b = Registry.spec("Mushroom", { style = style, v = 13 })
		Harness.truthy(key(a) ~= key(b), `Mushroom/{style} ignores v`)
	end
end)

Harness.test("models: odd variant numbers are clamped to a whole 1..1000", function()
	Harness.eq(Kit.variant(nil), 1)
	Harness.eq(Kit.variant(12.5), 12)
	Harness.eq(Kit.variant(0), 1)
	Harness.eq(Kit.variant(-7), 1)
	Harness.eq(Kit.variant(5000), 1000)
	Harness.eq(Kit.variant(0 / 0), 1)
	Harness.eq(Kit.pick({ "a", "b", "c" }, 4.7), "b")
	Harness.eq(Kit.pick({ "a", "b", "c" }, 4, 0.5), "b")
	for _, name in Registry.names do
		for _, style in Styles.ids do
			for _, v in { 12.5, 0.3, -4, 1e9, 0 / 0 } do
				local m = Registry.spec(name, { style = style, v = v })
				for i, s in m.parts do
					Harness.truthy(
						type(s.color) == "string",
						`{name}/{style}/v={v} part {i} has no colour`
					)
					for _, n in { s.x, s.y, s.z, s.sx, s.sy, s.sz, s.rx, s.ry, s.rz } do
						Harness.truthy(finite(n), `{name}/{style}/v={v} part {i}: bad number`)
					end
				end
			end
			-- a fraction acts like its whole number
			local a = Registry.spec(name, { style = style, v = 12.5 })
			local b = Registry.spec(name, { style = style, v = 12 })
			Harness.eq(#a.parts, #b.parts)
			for i, s in a.parts do
				Harness.eq(s.color, b.parts[i].color, `{name}/{style}: v=12.5 differs from v=12`)
				Harness.eq(s.y, b.parts[i].y, `{name}/{style}: v=12.5 differs from v=12`)
			end
		end
	end
end)

Harness.test("models: sign board anchor is the board's centre in every look", function()
	for _, style in Styles.ids do
		local m = Registry.spec("Sign", { style = style, text = "HI" })
		local a = m.anchors.board
		for _, s in m.parts do
			if s.name == "Board" then
				Harness.near(a.x, s.x, 1e-9, `{style}: board anchor x`)
				Harness.near(a.y, s.y, 1e-9, `{style}: board anchor y`)
				Harness.near(a.z, s.z, 1e-9, `{style}: board anchor z`)
			end
		end
	end
end)

Harness.test("models: basalt spire tips and veins follow their leaning shards", function()
	for _, v in VARIANTS do
		local m = Registry.spec("Spire", { style = "basalt", v = v })
		local shards: { Kit.Spec } = {}
		local tips: { Kit.Spec } = {}
		local veins: { Kit.Spec } = {}
		for _, s in m.parts do
			if s.name == "Shard" then
				table.insert(shards, s)
			elseif s.name == "ShardTip" then
				table.insert(tips, s)
			elseif s.name == "Vein" then
				table.insert(veins, s)
			end
		end
		Harness.eq(#tips, 2 * #shards)
		Harness.eq(#veins, #shards)
		for i, sh in ipairs(shards) do
			local e = Kit.v3(sh.rx, sh.ry, sh.rz)
			-- the shard's top centre and its front-face normal, in model space
			local up = Kit.turn(e, Kit.v3(0, sh.sy / 2, 0))
			local top = Kit.v3(sh.x + up.x, sh.y + up.y, sh.z + up.z)
			for k = 1, 2 do
				local t = tips[(i - 1) * 2 + k]
				-- the tip's base sits on the top face: its centre is tipH/2 above it along the shard axis
				local d = Kit.v3(t.x - top.x, t.y - top.y, t.z - top.z)
				local axis = Kit.turn(e, Kit.v3(0, 1, 0))
				local along = d.x * axis.x + d.y * axis.y + d.z * axis.z
				Harness.near(along, t.sy / 2, 1e-6, `v={v} shard {i} tip height`)
				-- the tip's own up axis is the shard's up axis
				local tipUp = Kit.turn(Kit.v3(t.rx, t.ry, t.rz), Kit.v3(0, 1, 0))
				Harness.near(tipUp.x, axis.x, 1e-6, "tip leans with the shard")
				Harness.near(tipUp.y, axis.y, 1e-6, "tip leans with the shard")
				Harness.near(tipUp.z, axis.z, 1e-6, "tip leans with the shard")
			end
			local vein = veins[i]
			Harness.eq(vein.ry, sh.ry, "vein turns with its shard")
			Harness.eq(vein.rz, sh.rz, "vein leans with its shard")
			-- the vein sits just in front of the shard's front face (local -Z), not inside or far off
			local inv = Kit.v3(vein.x - sh.x, vein.y - sh.y, vein.z - sh.z)
			local front = Kit.turn(e, Kit.v3(0, 0, -1))
			local out = inv.x * front.x + inv.y * front.y + inv.z * front.z
			Harness.near(out, sh.sz / 2 + 0.06, 1e-6, `v={v} shard {i} vein on the face`)
		end
	end
end)

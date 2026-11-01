--!strict
local Harness = require("./harness")
local BotSpecs = require("../src/server/World/Models/BotSpecs")
local CartSpecs = require("../src/server/World/Models/CartSpecs")
local ModelKit = require("../src/server/World/Models/ModelKit")
local ToolSpecs = require("../src/server/World/Models/ToolSpecs")
local Tools = require("../src/shared/Catalog/Tools")

local KINDS = { Block = true, Cyl = true, Ball = true }
local MATS =
	{ Wood = true, SmoothPlastic = true, Neon = true, Metal = true, Fabric = true, Glass = true }

local function finite3(v: { number }, limit: number): boolean
	if #v ~= 3 then
		return false
	end
	for _, x in v do
		if type(x) ~= "number" or x ~= x or math.abs(x) > limit then
			return false
		end
	end
	return true
end

-- Every part is sane: known kind/material, finite numbers, hex colour, unique name.
local function checkParts(label: string, parts: { ModelKit.PartSpec }, sizeLimit: number)
	local names: { [string]: boolean } = {}
	for _, p in parts do
		Harness.truthy(KINDS[p.kind], label .. " kind " .. p.name)
		Harness.truthy(MATS[p.mat], label .. " material " .. p.name)
		Harness.truthy(finite3(p.size, sizeLimit), label .. " size " .. p.name)
		Harness.truthy(finite3(p.pos, 12), label .. " pos " .. p.name)
		Harness.truthy(finite3(p.rot, 360), label .. " rot " .. p.name)
		for _, s in p.size do
			Harness.truthy(s > 0, label .. " positive size " .. p.name)
		end
		Harness.truthy(
			string.match(p.color, "^#%x%x%x%x%x%x$") ~= nil,
			label .. " colour " .. p.name
		)
		Harness.truthy(p.alpha >= 0 and p.alpha <= 1, label .. " alpha " .. p.name)
		Harness.eq(names[p.name], nil, label .. " unique name " .. p.name)
		names[p.name] = true
		if p.kind == "Ball" then
			Harness.eq(p.size[1], p.size[2], label .. " round ball " .. p.name)
			Harness.eq(p.size[2], p.size[3], label .. " round ball " .. p.name)
		end
		if p.kind == "Cyl" then
			Harness.eq(p.size[1], p.size[3], label .. " round cylinder " .. p.name)
		end
	end
end

-- The soft ground shadow is not part of the model's size.
local function solid(parts: { ModelKit.PartSpec }): { ModelKit.PartSpec }
	local out: { ModelKit.PartSpec } = {}
	for _, p in parts do
		if p.name ~= "Shadow" then
			table.insert(out, p)
		end
	end
	return out
end

Harness.test("models: colour maths mixes and clamps", function()
	Harness.eq(ModelKit.mix("#000000", "#FFFFFF", 0.5), "#808080")
	Harness.eq(ModelKit.mix("#FF0000", "#0000FF", 0), "#FF0000")
	Harness.eq(ModelKit.mix("#FF0000", "#0000FF", 1), "#0000FF")
	Harness.eq(ModelKit.lighten("#000000", 1), "#FFFFFF")
	Harness.eq(ModelKit.darken("#FFFFFF", 1), "#000000")
	Harness.eq(ModelKit.style("zzz").id, "A", "unknown look -> Toy")
	Harness.eq(ModelKit.style(nil).id, "A")
end)

Harness.test("models: half extent turns with the part", function()
	local straight = ModelKit.box("x", { 2, 4, 6 }, { 0, 0, 0 }, "#FFFFFF", "Wood")
	local hx, hy, hz = ModelKit.halfExtent(straight)
	Harness.near(hx, 1, 1e-6)
	Harness.near(hy, 2, 1e-6)
	Harness.near(hz, 3, 1e-6)
	local rolled = ModelKit.cyl("y", 1, 4, { 0, 0, 0 }, "#FFFFFF", "Wood", { 0, 0, 90 })
	local rx, ry, rz = ModelKit.halfExtent(rolled)
	Harness.near(rx, 2, 1e-6)
	Harness.near(ry, 0.5, 1e-6)
	Harness.near(rz, 0.5, 1e-6)
end)

Harness.test("tool models: colours and ids match the catalog", function()
	local n = 0
	for _, tool in Tools.list do
		Harness.eq(ToolSpecs.colors[tool.id], tool.color, "colour of " .. tool.id)
		n += 1
	end
	local count = 0
	for _ in ToolSpecs.colors do
		count += 1
	end
	Harness.eq(count, n, "no extra tool colours")
end)

Harness.test("tool models: every catalog tool, in every look, is valid and phone-light", function()
	for _, tool in Tools.list do
		Harness.truthy(ToolSpecs.has(tool.id), "builder for " .. tool.id)
		for _, look in ModelKit.styleOrder do
			local spec = ToolSpecs.build(tool.id, look)
			local label = tool.id .. "/" .. look
			Harness.eq(spec.id, tool.id)
			Harness.eq(spec.look, look)
			checkParts(label .. " hand", spec.hand, 4)
			checkParts(label .. " back", spec.back, 4)
			Harness.truthy(
				#spec.hand >= 8 and #spec.hand <= ToolSpecs.MAX_HAND,
				label .. " hand count " .. #spec.hand
			)
			Harness.truthy(#spec.back <= ToolSpecs.MAX_BACK, label .. " back count " .. #spec.back)
			-- one list of names across hand and back is not needed, but within each it is unique
		end
	end
end)

Harness.test("tool models: tools hang below the grip and stay a sensible size", function()
	for _, tool in Tools.list do
		local spec = ToolSpecs.build(tool.id, "A")
		local b = ModelKit.bounds(spec.hand)
		Harness.truthy(b.maxY <= 1.3, tool.id .. " does not tower over the hand: " .. b.maxY)
		Harness.truthy(b.minY <= -2.5 and b.minY >= -5, tool.id .. " business end: " .. b.minY)
		Harness.truthy(b.maxX - b.minX <= 3.2, tool.id .. " width " .. (b.maxX - b.minX))
		Harness.truthy(b.maxZ - b.minZ <= 3.2, tool.id .. " depth " .. (b.maxZ - b.minZ))
		if #spec.back > 0 then
			local bb = ModelKit.bounds(spec.back)
			Harness.truthy(bb.minZ >= 0.2, tool.id .. " backpack sits behind the torso")
			Harness.truthy(bb.maxZ <= 2.4, tool.id .. " backpack not too deep")
			Harness.truthy(bb.maxX - bb.minX <= 3.4 and bb.maxY - bb.minY <= 3.6)
		end
	end
end)

Harness.test(
	"tool models: the eight tools look different, and look A uses the tool colour",
	function()
		local seen: { [string]: string } = {}
		for _, tool in Tools.list do
			local spec = ToolSpecs.build(tool.id, "A")
			local sig = ModelKit.signature(spec.hand)
			Harness.eq(seen[sig], nil, tool.id .. " same as " .. tostring(seen[sig]))
			seen[sig] = tool.id
			local used = false
			for _, p in spec.hand do
				if string.upper(p.color) == string.upper(tool.color) then
					used = true
				end
			end
			for _, p in spec.back do
				if string.upper(p.color) == string.upper(tool.color) then
					used = true
				end
			end
			Harness.truthy(used, tool.id .. " carries the tool colour in look A")
		end
	end
)

Harness.test("tool models: the three looks differ for every tool", function()
	for _, tool in Tools.list do
		local sigs: { [string]: string } = {}
		for _, look in ModelKit.styleOrder do
			local spec = ToolSpecs.build(tool.id, look)
			local sig = ModelKit.signature(spec.hand) .. "|" .. ModelKit.signature(spec.back)
			Harness.eq(sigs[sig], nil, `{tool.id} look {look} same as {tostring(sigs[sig])}`)
			sigs[sig] = look
		end
	end
end)

Harness.test(
	"tool models: unknown tool id falls back to the twig broom; unknown look to Toy",
	function()
		local odd = ToolSpecs.build("nope", "Z")
		Harness.eq(odd.id, "twig_broom")
		Harness.eq(odd.look, "A")
		Harness.truthy(not ToolSpecs.has("nope"))
	end
)

Harness.test("tool models: building twice gives the same parts", function()
	for _, tool in Tools.list do
		local a = ToolSpecs.build(tool.id, "B")
		local b = ToolSpecs.build(tool.id, "B")
		Harness.eq(ModelKit.signature(a.hand), ModelKit.signature(b.hand))
		Harness.eq(#a.hand, #b.hand)
		Harness.eq(#a.back, #b.back)
	end
end)

Harness.test("helper bots: every look and level is valid and phone-light", function()
	for _, look in BotSpecs.looks do
		local counts: { [number]: boolean } = {}
		for level = 0, BotSpecs.maxLevel do
			local spec = BotSpecs.build(look, level)
			local label = `bot {look} lv{level}`
			checkParts(label, spec.parts, 4)
			Harness.truthy(#spec.parts >= 15 and #spec.parts <= BotSpecs.MAX_PARTS, label)
			counts[#spec.parts] = true
			local b = ModelKit.bounds(solid(spec.parts))
			local hover = if look == "A" then 1.0 else 0.1 -- Bumble hovers a little
			Harness.truthy(b.minY >= -0.01 and b.minY <= hover, label .. " stands on the ground")
			Harness.truthy(b.maxY >= 3 and b.maxY <= 4.4, label .. " height " .. b.maxY)
			Harness.truthy(b.maxX - b.minX <= 3.8, label .. " width")
			Harness.truthy(b.maxZ - b.minZ <= 4.0, label .. " depth")
			local hasSpin = false
			for _, p in spec.parts do
				if string.sub(p.name, 1, 4) == "Spin" then
					hasSpin = true
				end
			end
			Harness.eq(hasSpin, look ~= "C", label .. " spin parts")
		end
		local n = 0
		for _ in counts do
			n += 1
		end
		Harness.eq(n, 1, "level never changes the part count for " .. look)
	end
end)

Harness.test("helper bots: three different bots, level changes the trim colour", function()
	local sigs: { [string]: string } = {}
	for _, look in BotSpecs.looks do
		local sig = ModelKit.signature(BotSpecs.build(look, 0).parts)
		Harness.eq(sigs[sig], nil)
		sigs[sig] = look
	end
	for _, look in BotSpecs.looks do
		local last = ""
		for _, level in { 0, 4, 8, 12 } do
			local sig = ModelKit.signature(BotSpecs.build(look, level).parts)
			Harness.truthy(sig ~= last, `{look} lv{level} has its own trim`)
			last = sig
		end
		Harness.eq(
			ModelKit.signature(BotSpecs.build(look, 4).parts),
			ModelKit.signature(BotSpecs.build(look, 7).parts)
		)
	end
	Harness.eq(BotSpecs.tier(0), 1)
	Harness.eq(BotSpecs.tier(3), 1)
	Harness.eq(BotSpecs.tier(4), 2)
	Harness.eq(BotSpecs.tier(15), 4)
	Harness.eq(BotSpecs.tier(99), 4)
	Harness.eq(BotSpecs.tier(-5), 1)
	Harness.eq(BotSpecs.tierName(8), "Gold")
	Harness.eq(BotSpecs.build("Z", 3).look, "A", "unknown look -> A")
	Harness.eq(BotSpecs.build("B", 99).level, BotSpecs.maxLevel, "level is clamped")
end)

Harness.test("cart: valid, phone-light, sized for one rider", function()
	for _, look in ModelKit.styleOrder do
		local spec = CartSpecs.build(look)
		checkParts("cart " .. look, spec.parts, 6)
		Harness.truthy(#spec.parts >= 30 and #spec.parts <= CartSpecs.MAX_PARTS, "cart count")
		local b = ModelKit.bounds(solid(spec.parts))
		Harness.truthy(b.minY >= -0.01 and b.minY <= 0.1, "cart on the ground")
		Harness.truthy(b.maxY >= 3 and b.maxY <= 5, "cart height " .. b.maxY)
		Harness.truthy(
			b.maxX - b.minX >= 2.5 and b.maxX - b.minX <= 4.2,
			"cart width " .. (b.maxX - b.minX)
		)
		Harness.truthy(b.maxZ - b.minZ >= 5 and b.maxZ - b.minZ <= 7.5, "cart length")
		local seat = false
		local heap = false
		for _, p in spec.parts do
			if p.name == "SeatSpot" then
				seat = p.alpha == 1
				Harness.near(p.pos[2], CartSpecs.seatSpot[2])
			elseif p.name == "AshHeap" then
				heap = true
			end
		end
		Harness.truthy(seat and heap, "seat marker and ash heap")
	end
	Harness.truthy(
		ModelKit.signature(CartSpecs.build("A").parts)
			~= ModelKit.signature(CartSpecs.build("B").parts)
	)
	Harness.truthy(
		ModelKit.signature(CartSpecs.build("B").parts)
			~= ModelKit.signature(CartSpecs.build("C").parts)
	)
end)

Harness.test("cart: the ash heap grows with the fill and stays inside the bin", function()
	local lastH = 0
	for step = 0, 10 do
		local size, y = CartSpecs.heap(step / 10)
		Harness.truthy(size[1] > 0 and size[2] > lastH, "heap grows")
		Harness.eq(size[1], size[3])
		Harness.truthy(size[1] <= 1.5 + 1e-9, "fits between the walls")
		Harness.near(y - size[2] / 2, CartSpecs.binFloorTop, 1e-9, "sits on the floor")
		lastH = size[2]
	end
	local lo = CartSpecs.heap(-3)
	local hi = CartSpecs.heap(9)
	Harness.near(lo[2], CartSpecs.heap(0)[2])
	Harness.near(hi[2], CartSpecs.heap(1)[2])
end)

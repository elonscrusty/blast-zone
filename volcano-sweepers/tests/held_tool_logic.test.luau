--!strict
local Harness = require("./harness")
local HeldToolLogic = require("../src/shared/Client/HeldToolLogic")
local Tools = require("../src/shared/Catalog/Tools")

local SHAPES = { Block = true, Cylinder = true, Ball = true, Wedge = true }
local MATERIALS =
	{ Wood = true, SmoothPlastic = true, Neon = true, Metal = true, Fabric = true, Glass = true }

local function finiteVec(v: { number }, n: number, limit: number?): boolean
	if #v ~= n then
		return false
	end
	for _, x in v do
		if type(x) ~= "number" or x ~= x or math.abs(x) > (limit or 50) then
			return false
		end
	end
	return true
end

Harness.test("held tool: every catalog tool has its own valid blueprint", function()
	for _, tool in Tools.list do
		Harness.truthy(HeldToolLogic.hasBlueprint(tool.id), "blueprint for " .. tool.id)
		local bp = HeldToolLogic.blueprint(tool.id)
		Harness.eq(bp.id, tool.id)
		Harness.truthy(
			#bp.parts >= 3 and #bp.parts <= HeldToolLogic.MAX_PARTS,
			"part count " .. tool.id
		)
		local names: { [string]: boolean } = {}
		local hand = 0
		for _, p in bp.parts do
			Harness.truthy(SHAPES[p.shape], "shape " .. p.name)
			Harness.truthy(MATERIALS[p.material], "material " .. p.name)
			Harness.truthy(
				finiteVec(p.size, 3) and finiteVec(p.pos, 3) and finiteVec(p.rot, 3, 180),
				p.name
			)
			for _, s in p.size do
				Harness.truthy(s > 0 and s <= 4, "size " .. p.name)
			end
			Harness.truthy(string.match(p.color, "^#%x%x%x%x%x%x$") ~= nil, "colour " .. p.name)
			Harness.truthy(p.transparency >= 0 and p.transparency < 1)
			Harness.truthy(p.anchor == "hand" or p.anchor == "back")
			Harness.eq(names[p.name], nil, "unique part name " .. p.name)
			names[p.name] = true
			if p.anchor == "hand" then
				hand += 1
			end
		end
		Harness.truthy(hand >= 2, "something in the hand for " .. tool.id)
		Harness.truthy(bp.amp > 0 and bp.amp <= 60 and bp.tilt > 0 and bp.tilt < 90)
	end
end)

Harness.test("held tool: the eight looks are all different and use the tool colour", function()
	local seen: { [string]: string } = {}
	for _, tool in Tools.list do
		local bp = HeldToolLogic.blueprint(tool.id)
		local sig = { bp.style, tostring(#bp.parts) }
		local usesColour = false
		for _, p in bp.parts do
			table.insert(sig, p.shape .. p.color)
			if string.upper(p.color) == string.upper(tool.color) then
				usesColour = true
			end
		end
		local key = table.concat(sig, "|")
		Harness.eq(seen[key], nil, tool.id .. " looks like " .. tostring(seen[key]))
		seen[key] = tool.id
		Harness.truthy(usesColour, tool.id .. " uses its catalog colour")
	end
	-- vacuums wear something on the back, brooms do not
	local function hasBack(id: string): boolean
		for _, p in HeldToolLogic.blueprint(id).parts do
			if p.anchor == "back" then
				return true
			end
		end
		return false
	end
	Harness.eq(hasBack("twig_broom"), false)
	Harness.eq(hasBack("dust_vac"), true)
	Harness.eq(hasBack("volcano_vac"), true)
end)

Harness.test("held tool: resolve falls back safely", function()
	Harness.eq(HeldToolLogic.resolve("lava_mop", "twig_broom"), "lava_mop")
	Harness.eq(HeldToolLogic.resolve(nil, "push_broom"), "push_broom")
	Harness.eq(HeldToolLogic.resolve("rocket_launcher", "dust_vac"), "dust_vac")
	Harness.eq(HeldToolLogic.resolve(42, nil), "twig_broom")
	Harness.eq(HeldToolLogic.blueprint("nope").id, "twig_broom")
	Harness.eq(HeldToolLogic.blueprint(nil).id, "twig_broom")
end)

Harness.test("held tool: every swing starts and ends at rest and stays sane", function()
	for _, style in { "sweep", "blow", "vac", "mop", "roar", "mega" } do
		for _, t in { -1, 0, 1, 2, 0 / 0 } do
			local p, r, a = HeldToolLogic.pose(style :: any, t, 30)
			Harness.eq(p, 0, style .. " pitch at " .. tostring(t))
			Harness.eq(r, 0, style .. " roll")
			Harness.eq(a, 0, style .. " arm")
		end
		local moved = false
		local last = { 0, 0, 0 }
		for k = 1, 99 do
			local p, r, a = HeldToolLogic.pose(style :: any, k / 100, 30)
			Harness.truthy(math.abs(p) <= 60 and math.abs(r) <= 60 and math.abs(a) <= 40, style)
			if math.abs(p) + math.abs(r) > 5 then
				moved = true
			end
			-- smooth: no jump bigger than 8 degrees between 1% steps
			Harness.truthy(
				math.abs(p - last[1]) < 8 and math.abs(r - last[2]) < 8,
				style .. " smooth"
			)
			last = { p, r, a }
		end
		Harness.truthy(moved, style .. " visibly moves")
	end
end)

Harness.test("held tool: swing time and distance rules", function()
	Harness.near(HeldToolLogic.swingTime(0.34), 0.289, 0.001)
	Harness.eq(HeldToolLogic.swingTime(0.05), 0.16)
	Harness.eq(HeldToolLogic.swingTime(5), 0.32)
	Harness.eq(HeldToolLogic.swingTime(nil), HeldToolLogic.swingTime(0.34))
	Harness.eq(HeldToolLogic.wantModel(100, false), true)
	Harness.eq(HeldToolLogic.wantModel(150, false), false, "not built past the build radius")
	Harness.eq(HeldToolLogic.wantModel(150, true), true, "kept until the drop radius")
	Harness.eq(HeldToolLogic.wantModel(200, true), false)
	Harness.eq(HeldToolLogic.wantModel(0 / 0, true), false)
	Harness.eq(HeldToolLogic.canAnimate(50), true)
	Harness.eq(HeldToolLogic.canAnimate(300), false)
	Harness.eq(HeldToolLogic.wantLite(30, false), false, "full detail up close")
	Harness.eq(HeldToolLogic.wantLite(80, false), true, "lite far away")
	Harness.eq(HeldToolLogic.wantLite(55, false), false, "stays full until the lite radius")
	Harness.eq(HeldToolLogic.wantLite(55, true), true, "stays lite until the full radius")
	Harness.eq(HeldToolLogic.wantLite(40, true), false)
	Harness.eq(HeldToolLogic.wantLite(0 / 0, false), true)
end)

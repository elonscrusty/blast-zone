--!strict
-- Tools panel model: states, next-tier highlight, stat bars.
local Harness = require("./harness")
local Economy = require("../src/shared/Rules/Economy")
local Tools = require("../src/shared/Catalog/Tools")
local ToolsModel = require("../src/shared/Ui/ToolsModel")

local function rowOf(model: ToolsModel.Model, id: string): ToolsModel.Row
	for _, row in model.rows do
		if row.id == id then
			return row
		end
	end
	error("no row " .. id)
end

Harness.test("ToolsModel: eight tools, twig broom equipped, push broom is NEXT", function()
	local model = ToolsModel.build(Economy.blankProfile())
	Harness.eq(#model.rows, 8)
	Harness.eq(model.equippedId, "twig_broom")
	Harness.eq(model.nextId, "push_broom")
	Harness.eq(rowOf(model, "twig_broom").status, "equipped")
	Harness.eq(rowOf(model, "push_broom").status, "short")
	Harness.eq(rowOf(model, "push_broom").badge, "NEXT")
	Harness.eq(rowOf(model, "leaf_blower").status, "later")
	Harness.eq(rowOf(model, "leaf_blower").badge, nil)
	Harness.eq(model.canBuyAny, false)
	for i, tool in Tools.list do
		Harness.eq(model.rows[i].id, tool.id)
		Harness.truthy(model.rows[i].glyph ~= "", "glyph")
	end
end)

Harness.test("ToolsModel: short shows 'Need N more coins!'", function()
	local p = Economy.blankProfile()
	local price = Tools.byId.push_broom.price
	p.coins = price - 30
	local row = rowOf(ToolsModel.build(p), "push_broom")
	Harness.eq(row.price, price)
	Harness.eq(row.missing, 30)
	Harness.eq(row.needText, "Need 30 more coins!")
	Harness.eq(row.affordable, false)
end)

Harness.test("ToolsModel: with the coins, the next tool and a far tool can be bought", function()
	local p = Economy.blankProfile()
	-- enough for the Leaf Blower (tier 3), not for the Dust Vac (tier 4)
	p.coins = Tools.byId.leaf_blower.price
	Harness.truthy(p.coins < Tools.byId.dust_vac.price, "catalog prices climb")
	local model = ToolsModel.build(p)
	Harness.eq(rowOf(model, "push_broom").status, "buy")
	Harness.eq(rowOf(model, "leaf_blower").status, "buy") -- allowed by the rules, so shown as buyable
	Harness.eq(model.canBuyAny, true)
	Harness.eq(rowOf(model, "dust_vac").status, "later")
end)

Harness.test("ToolsModel: owned tools can be equipped, equipped one is marked", function()
	local p = Economy.blankProfile()
	p.toolsOwned = { twig_broom = true, push_broom = true, leaf_blower = true }
	p.tool = "push_broom"
	local model = ToolsModel.build(p)
	Harness.eq(model.equippedId, "push_broom")
	Harness.eq(rowOf(model, "push_broom").status, "equipped")
	Harness.eq(rowOf(model, "twig_broom").status, "owned")
	Harness.eq(rowOf(model, "leaf_blower").status, "owned")
	Harness.eq(model.nextId, "dust_vac")
	Harness.eq(rowOf(model, "dust_vac").badge, "NEXT")
	Harness.eq(rowOf(model, "dust_vac").status, "short")
end)

Harness.test("ToolsModel: next skips holes (own tier 5 only -> next is tier 6)", function()
	local p = Economy.blankProfile()
	p.toolsOwned = { twig_broom = true, turbo_vac = true }
	p.tool = "turbo_vac"
	local model = ToolsModel.build(p)
	Harness.eq(model.nextId, "lava_mop")
	Harness.eq(rowOf(model, "push_broom").status, "later") -- cheaper but behind you: not the NEXT one
end)

Harness.test("ToolsModel: no tool is ever shown locked: every unowned tool has a price", function()
	local p = Economy.blankProfile()
	p.coins = 3
	for _, row in ToolsModel.build(p).rows do
		Harness.truthy(row.status ~= "locked", "no padlock state")
		if not row.owned then
			Harness.truthy(row.price > 0, `{row.id} has a price`)
			Harness.truthy(row.needText ~= nil, `{row.id} says how many coins are missing`)
		end
	end
end)

Harness.test("ToolsModel: owning everything leaves no NEXT", function()
	local p = Economy.blankProfile()
	for _, tool in Tools.list do
		p.toolsOwned[tool.id] = true
	end
	p.tool = "volcano_vac"
	local model = ToolsModel.build(p)
	Harness.eq(model.nextId, nil)
	Harness.eq(model.canBuyAny, false)
	Harness.eq(rowOf(model, "volcano_vac").status, "equipped")
	Harness.truthy(string.find(model.hint, "every tool", 1, true) ~= nil)
end)

Harness.test(
	"ToolsModel: an equipped id the player does not own falls back to the twig broom",
	function()
		local p = Economy.blankProfile()
		p.tool = "dragon_vac"
		Harness.eq(ToolsModel.build(p).equippedId, "twig_broom")
	end
)

Harness.test("ToolsModel: five stat bars, fractions 0..1, best tool tops the bars", function()
	local model = ToolsModel.build(Economy.blankProfile())
	for _, row in model.rows do
		Harness.eq(#row.stats, 5)
		for _, bar in row.stats do
			Harness.truthy(bar.fraction >= 0 and bar.fraction <= 1, row.id .. bar.key)
			Harness.truthy(bar.equippedFraction >= 0 and bar.equippedFraction <= 1)
			Harness.truthy(bar.text ~= "", "text")
		end
	end
	local top = rowOf(model, "volcano_vac")
	Harness.eq(top.stats[1].fraction, 1) -- reach 22 is the best
	Harness.eq(top.stats[3].fraction, 1) -- power 4
	Harness.eq(top.stats[5].fraction, 1) -- bag +900
	-- every tier is at least as strong in reach/power/bag as the one before it
	for i = 2, #model.rows do
		Harness.truthy(
			model.rows[i].stats[3].fraction >= model.rows[i - 1].stats[3].fraction,
			"power rises"
		)
		Harness.truthy(
			model.rows[i].stats[5].fraction >= model.rows[i - 1].stats[5].fraction,
			"bag rises"
		)
	end
	Harness.eq(rowOf(model, "twig_broom").stats[1].text, "7")
	Harness.eq(rowOf(model, "push_broom").stats[2].text, "110°")
	Harness.eq(rowOf(model, "twig_broom").stats[5].text, "+0")
end)

Harness.test("ToolsModel: hostile tables never throw", function()
	Harness.eq(#ToolsModel.build(nil).rows, 8)
	local weird: any = { coins = "x", tool = 5, toolsOwned = { push_broom = "yes", ghost = true } }
	local model = ToolsModel.build(weird)
	Harness.eq(model.equippedId, "twig_broom")
	Harness.eq(rowOf(model, "push_broom").owned, false)
end)

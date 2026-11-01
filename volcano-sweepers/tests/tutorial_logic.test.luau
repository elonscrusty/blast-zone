--!strict
local Harness = require("./harness")
local TutorialLogic = require("../src/shared/Client/TutorialLogic")

local function facts(over: { [string]: any }): TutorialLogic.Facts
	local f: { [string]: any } = {
		now = 10,
		carried = 0,
		fraction = 0,
		ashInReach = false,
		nearHut = false,
		canBuy = false,
		panelOpen = false,
		autoOn = false,
		touch = true,
	}
	for k, v in over do
		f[k] = v
	end
	return f :: any
end

Harness.test("tutorial: no hint in the first second", function()
	local s = TutorialLogic.new(0)
	local h = TutorialLogic.step(s, facts({ now = 0.5, ashInReach = true }))
	Harness.eq(h.text, nil)
end)

Harness.test(
	"tutorial: no ash in reach -> walk to the ash with a line; ash -> hold SWEEP",
	function()
		local s = TutorialLogic.new(0)
		local h = TutorialLogic.step(s, facts({ now = 2 }))
		Harness.eq(s.stage, "find")
		Harness.eq(h.beam, "ash")
		h = TutorialLogic.step(s, facts({ now = 3, ashInReach = true }))
		Harness.eq(s.stage, "sweep")
		Harness.eq(h.text, "Hold SWEEP!")
		Harness.eq(h.point, "sweep")
		Harness.eq(h.beam, nil)
		-- ash briefly out of reach: no flicker back to "find"
		TutorialLogic.step(s, facts({ now = 3.5 }))
		Harness.eq(s.stage, "sweep")
		TutorialLogic.step(s, facts({ now = 5.5 }))
		Harness.eq(s.stage, "find")
	end
)

Harness.test("tutorial: a press with no ash does NOT advance; ash in the pack does", function()
	local s = TutorialLogic.new(0)
	TutorialLogic.step(s, facts({ now = 2, ashInReach = true }))
	TutorialLogic.step(s, facts({ now = 3, ashInReach = true, carried = 0 }))
	Harness.eq(s.stage, "sweep")
	local h =
		TutorialLogic.step(s, facts({ now = 4, ashInReach = true, carried = 2, fraction = 0.07 }))
	Harness.eq(s.stage, "fill")
	Harness.eq(h.text, "Fill your backpack!")
end)

Harness.test("tutorial: auto on and keyboard texts", function()
	local s = TutorialLogic.new(0)
	local h = TutorialLogic.step(s, facts({ now = 2, ashInReach = true, autoOn = true }))
	Harness.eq(h.text, "Walk into the ash!")
	Harness.eq(h.point, nil)
	local k = TutorialLogic.new(0)
	h = TutorialLogic.step(k, facts({ now = 2, ashInReach = true, touch = false }))
	Harness.eq(h.text, "Hold E or click to SWEEP!")
	Harness.eq(h.point, nil)
end)

Harness.test("tutorial: AUTO tip once on touch, then quiet", function()
	local s = TutorialLogic.new(0)
	TutorialLogic.step(s, facts({ now = 2, carried = 1, fraction = 0.03 }))
	Harness.eq(s.stage, "fill")
	local h =
		TutorialLogic.step(s, facts({ now = 2 + TutorialLogic.AUTO_TIP_AFTER + 1, carried = 5 }))
	Harness.eq(h.point, "auto")
	h = TutorialLogic.step(s, facts({ now = 30, carried = 8 }))
	Harness.eq(h.point, nil)
	Harness.eq(s.autoTipShown, true)
	h = TutorialLogic.step(s, facts({ now = 31, carried = 8 }))
	Harness.eq(h.text, nil)
end)

Harness.test(
	"tutorial: half full -> line to the hut -> SELL at the hut -> buy -> cheer -> done",
	function()
		local s = TutorialLogic.new(0)
		TutorialLogic.step(s, facts({ now = 2, carried = 3, fraction = 0.1 }))
		local h = TutorialLogic.step(s, facts({ now = 9, carried = 15, fraction = 0.5 }))
		Harness.eq(s.stage, "sell")
		Harness.eq(h.beam, "hut")
		h = TutorialLogic.step(s, facts({ now = 15, carried = 15, fraction = 0.5, nearHut = true }))
		Harness.eq(h.text, "Tap SELL!")
		Harness.eq(h.point, "sell")
		h = TutorialLogic.step(
			s,
			facts({ now = 15, nearHut = true, touch = false, fraction = 0.5 })
		)
		Harness.eq(h.text, "Press F to SELL!")
		TutorialLogic.onSold(s, 16)
		Harness.eq(s.stage, "buy")
		h = TutorialLogic.step(s, facts({ now = 17, canBuy = false }))
		Harness.eq(h.text, nil, "nothing affordable: stay quiet")
		h = TutorialLogic.step(s, facts({ now = 18, canBuy = true }))
		Harness.eq(h.point, "upgrades")
		h = TutorialLogic.step(s, facts({ now = 19, canBuy = true, panelOpen = true }))
		Harness.eq(h.point, nil, "no finger over an open panel")
		TutorialLogic.onBought(s, 20)
		Harness.eq(s.stage, "cheer")
		h = TutorialLogic.step(s, facts({ now = 21 }))
		Harness.eq(h.text, "You got stronger!")
		TutorialLogic.step(s, facts({ now = 30 }))
		Harness.eq(s.stage, "done")
	end
)

Harness.test("tutorial: an early sale skips ahead, the shop hint gives up in time", function()
	local s = TutorialLogic.new(0)
	TutorialLogic.step(s, facts({ now = 2, carried = 3, fraction = 0.1 }))
	TutorialLogic.onSold(s, 5)
	Harness.eq(s.stage, "buy")
	TutorialLogic.step(s, facts({ now = 5 + TutorialLogic.BUY_GIVE_UP + 1, canBuy = true }))
	Harness.eq(s.stage, "done")
	-- buying before any sale does not end the tutorial early
	local t = TutorialLogic.new(0)
	TutorialLogic.onBought(t, 1)
	Harness.eq(t.stage, "find")
end)

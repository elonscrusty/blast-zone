--!strict
-- Cool Down view-model: locked / allowed / just reset, Spark Shop rows, the tap-twice safety step.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Rules/Economy")
local StatsCalc = require("../src/shared/Rules/StatsCalc")
local SparkPerks = require("../src/shared/Catalog/SparkPerks")
local CoolDownModel = require("../src/shared/Ui/CoolDownModel")

local MIN = Config.Economy.coolDownMinRunCoins

local function blank(): any
	return Economy.blankProfile()
end

Harness.test("cooldown: a new player is locked with an empty bar", function()
	local v = CoolDownModel.build(blank())
	Harness.eq(v.canCoolDown, false)
	Harness.eq(v.badge, false)
	Harness.eq(v.fraction, 0)
	Harness.eq(v.progressText, "0 / 9M")
	Harness.eq(v.remainingText, "Earn 9M more coins to unlock")
	Harness.eq(v.note, "Earn 9M more coins to unlock")
	Harness.eq(v.sparksNow, 0)
	Harness.eq(v.sparksText, "Sparks so far: ✨ 0")
	Harness.eq(v.sparks, 0)
	Harness.eq(v.sparksBalanceText, "You have ✨ 0 Sparks")
	Harness.eq(v.bonus, 0)
	Harness.eq(v.bonusText, "+0% coins forever")
	Harness.eq(v.afterBonusText, "")
	Harness.eq(v.justReset, false)
	Harness.eq(v.title, "Cool the volcano!")
	Harness.eq(
		v.explain,
		"Start over, keep your treasure, get Sparks. Each Spark = +5% coins forever."
	)
end)

Harness.test("cooldown: halfway there is still locked, Sparks grow", function()
	local p = blank()
	p.runCoins = MIN / 2
	local v = CoolDownModel.build(p)
	Harness.eq(v.canCoolDown, false)
	Harness.near(v.fraction, 0.5)
	Harness.eq(v.sparksNow, 7) -- floor(10 x sqrt(0.5))
	Harness.eq(v.sparksText, "Sparks so far: ✨ 7")
	Harness.eq(v.progressText, "4.5M / 9M")
	Harness.eq(v.remainingText, "Earn 4.5M more coins to unlock")
	p.runCoins = MIN - 1
	Harness.eq(CoolDownModel.build(p).canCoolDown, false)
end)

Harness.test("cooldown: allowed from the minimum, shows Sparks you would get", function()
	local p = blank()
	p.runCoins = MIN
	local v = CoolDownModel.build(p)
	Harness.eq(v.canCoolDown, true)
	Harness.eq(v.badge, true)
	Harness.eq(v.fraction, 1)
	Harness.eq(v.sparksNow, 10)
	Harness.eq(v.sparksText, "You will get ✨ 10 Sparks!")
	Harness.eq(v.remainingText, "")
	Harness.eq(v.note, v.afterBonusText)
	Harness.near(v.bonus, 0)
	Harness.eq(
		v.afterBonusText,
		`After this: +{math.floor(StatsCalc.sparkBonus(10) * 100 + 0.5)}% coins forever`
	)
	p.runCoins = MIN * 4
	local big = CoolDownModel.build(p)
	Harness.eq(big.sparksNow, 20)
	Harness.eq(big.fraction, 1)
end)

Harness.test("cooldown: the model agrees with Economy for many runs", function()
	for _, rc in { 0, 1, 1000, MIN - 1, MIN, MIN + 1, MIN * 2.5, 1e12, 0 / 0, -5 } do
		local p = blank()
		p.runCoins = rc
		local v = CoolDownModel.build(p)
		local safe = if rc ~= rc or rc < 0 then 0 else rc
		p.runCoins = safe
		Harness.eq(v.canCoolDown, Economy.canCoolDown(p), "can at " .. tostring(rc))
		Harness.eq(v.sparksNow, Economy.sparksFor(safe), "sparks at " .. tostring(rc))
		Harness.truthy(v.fraction >= 0 and v.fraction <= 1)
	end
end)

Harness.test("cooldown: just after a reset", function()
	local p = blank()
	p.coolDowns = 1
	p.sparks = 10
	p.runCoins = 0
	p.coins = 250
	local v = CoolDownModel.build(p)
	Harness.eq(v.justReset, true)
	Harness.eq(v.note, "Fresh start! Your Sparks are already helping.")
	Harness.eq(v.canCoolDown, false)
	Harness.eq(v.coolDowns, 1)
	Harness.near(v.bonus, StatsCalc.sparkBonus(10), 1e-9)
	Harness.eq(v.sparksBalanceText, "You have ✨ 10 Sparks")
	Harness.eq(v.perkAffordable, true)
	-- a long way into the next run it is no longer 'just reset'
	p.runCoins = MIN / 10
	Harness.eq(CoolDownModel.build(p).justReset, false)
	-- and a player who never cooled down is not 'just reset'
	local fresh = blank()
	Harness.eq(CoolDownModel.build(fresh).justReset, false)
end)

Harness.test("cooldown: keep and reset lists", function()
	local v = CoolDownModel.build(blank())
	Harness.eq(#v.keep, 4)
	Harness.eq(#v.reset, 5)
	for _, item in v.keep do
		Harness.truthy(item.icon ~= "" and item.text ~= "")
	end
	for _, item in v.reset do
		Harness.truthy(item.icon ~= "" and item.text ~= "")
	end
end)

Harness.test("cooldown: Spark Shop rows", function()
	local p = blank()
	p.sparks = 5
	p.sparkPerks = { head_start = 2, free_push = 1 }
	local v = CoolDownModel.build(p)
	Harness.eq(#v.perks, #SparkPerks.list)
	local head = v.perks[1]
	Harness.eq(head.id, "head_start")
	Harness.eq(head.level, 2)
	Harness.eq(head.cost, 5)
	Harness.eq(head.affordable, true)
	Harness.eq(head.maxed, false)
	Harness.eq(head.nowText, SparkPerks.effectText("head_start", 2))
	Harness.eq(head.nextText, "Next: " .. SparkPerks.effectText("head_start", 3))
	local pockets = v.perks[2]
	Harness.eq(pockets.level, 0)
	Harness.eq(pockets.nowText, "Not bought yet")
	Harness.eq(pockets.cost, 2)
	Harness.eq(pockets.affordable, true)
	local push = v.perks[3]
	Harness.eq(push.id, "free_push")
	Harness.eq(push.maxed, true)
	Harness.eq(push.cost, nil)
	Harness.eq(push.affordable, false)
	Harness.eq(push.nextText, "")
	-- too poor for the dearer ones
	Harness.eq(v.perks[6].id, "haggler")
	Harness.eq(v.perks[6].cost, 3)
	p.sparks = 4
	local poor = CoolDownModel.build(p)
	Harness.eq(poor.perks[1].affordable, false) -- needs 5
	Harness.eq(poor.perks[2].affordable, true) -- needs 2
	p.sparks = 0
	Harness.eq(CoolDownModel.build(p).perkAffordable, false)
end)

Harness.test("cooldown: spending Sparks on perks keeps the coin bonus", function()
	local p = blank()
	p.sparks = 6
	local before = CoolDownModel.build(p)
	p.sparks = 4
	p.sparkPerks = { head_start = 1 } -- cost 2
	local after = CoolDownModel.build(p)
	Harness.near(after.bonus, before.bonus, 1e-9)
	Harness.eq(after.bonusText, before.bonusText)
end)

Harness.test("cooldown: maxed perks read maxed", function()
	local p = blank()
	p.sparkPerks = {}
	for _, perk in SparkPerks.list do
		p.sparkPerks[perk.id] = perk.maxLevel
	end
	p.sparks = 999
	local v = CoolDownModel.build(p)
	for _, perk in v.perks do
		Harness.eq(perk.maxed, true, perk.id)
		Harness.eq(perk.affordable, false, perk.id)
		Harness.eq(perk.cost, nil, perk.id)
	end
	Harness.eq(v.perkAffordable, false)
end)

Harness.test("cooldown: junk input never throws", function()
	local v = CoolDownModel.build({ runCoins = "x", sparks = 0 / 0, sparkPerks = 4 } :: any)
	Harness.eq(v.canCoolDown, false)
	Harness.eq(v.sparks, 0)
	Harness.eq(#v.perks, #SparkPerks.list)
	Harness.eq(CoolDownModel.build({} :: any).fraction, 0)
	local lv = CoolDownModel.build({ sparkPerks = { head_start = 99, bot_boost = -3 } } :: any)
	Harness.eq(lv.perks[1].level, 8)
	Harness.eq(lv.perks[1].maxed, true)
	Harness.eq(lv.perks[7].level, 0)
end)

Harness.test("cooldown: doneText", function()
	Harness.eq(CoolDownModel.doneText(1), "You got ✨ 1 Spark! The volcano is cooler now.")
	Harness.eq(CoolDownModel.doneText(12), "You got ✨ 12 Sparks! The volcano is cooler now.")
	Harness.eq(CoolDownModel.doneText(0), "The volcano is cooler now.")
	Harness.eq(CoolDownModel.doneText(0 / 0), "The volcano is cooler now.")
end)

-- ===== the tap-twice safety step =====
Harness.test("confirm: a locked Cool Down can never be sent", function()
	local c = CoolDownModel.newConfirm()
	for t = 0, 30, 3 do
		Harness.eq(CoolDownModel.tap(c, t, false), "none")
	end
	local view = CoolDownModel.confirmView(c, 5, false)
	Harness.eq(view.enabled, false)
	Harness.eq(view.armed, false)
	Harness.eq(view.text, "Not yet")
end)

Harness.test("confirm: first tap only arms, second tap after 1 s sends", function()
	local c = CoolDownModel.newConfirm()
	local idle = CoolDownModel.confirmView(c, 100, true)
	Harness.eq(idle.text, "COOL DOWN")
	Harness.eq(idle.enabled, true)
	Harness.eq(idle.warn, false)

	Harness.eq(CoolDownModel.tap(c, 100, true), "armed")
	local wait = CoolDownModel.confirmView(c, 100.4, true)
	Harness.eq(wait.armed, true)
	Harness.eq(wait.warn, true)
	Harness.eq(wait.enabled, false)
	Harness.eq(wait.text, "Wait...")
	Harness.eq(CoolDownModel.tap(c, 100.5, true), "none", "too fast")
	Harness.eq(CoolDownModel.tap(c, 100.99, true), "none", "still too fast")

	local go = CoolDownModel.confirmView(c, 101, true)
	Harness.eq(go.enabled, true)
	Harness.eq(go.text, "YES! COOL DOWN!")
	Harness.eq(CoolDownModel.tap(c, 101, true), "send")
	-- sending resets: the next tap arms again, a double tap cannot send twice
	Harness.eq(CoolDownModel.tap(c, 101.01, true), "armed")
	Harness.eq(CoolDownModel.tap(c, 101.02, true), "none")
end)

Harness.test("confirm: waiting too long starts over", function()
	local c = CoolDownModel.newConfirm()
	Harness.eq(CoolDownModel.tap(c, 50, true), "armed")
	Harness.eq(CoolDownModel.tap(c, 50 + CoolDownModel.CONFIRM_TIMEOUT, true), "armed")
	local view = CoolDownModel.confirmView(c, 50 + CoolDownModel.CONFIRM_TIMEOUT + 20, true)
	Harness.eq(view.armed, false)
	Harness.eq(view.text, "COOL DOWN")
end)

Harness.test("confirm: cancel disarms, losing eligibility disarms", function()
	local c = CoolDownModel.newConfirm()
	CoolDownModel.tap(c, 10, true)
	CoolDownModel.cancel(c)
	Harness.eq(CoolDownModel.confirmView(c, 12, true).armed, false)
	Harness.eq(CoolDownModel.tap(c, 12, true), "armed")
	-- the server reset the run in the meantime (not allowed any more)
	Harness.eq(CoolDownModel.confirmView(c, 14, false).armed, false)
	Harness.eq(CoolDownModel.tap(c, 15, true), "armed", "needs a fresh first tap")
end)

Harness.test("confirm: a clock that goes backwards does not confirm", function()
	local c = CoolDownModel.newConfirm()
	Harness.eq(CoolDownModel.tap(c, 100, true), "armed")
	Harness.eq(CoolDownModel.tap(c, 50, true), "armed")
end)

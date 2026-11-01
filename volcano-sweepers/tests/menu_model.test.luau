--!strict
-- MENU launcher model: red dots only for what is NEW, the daily dot on server time, tile notes.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Rules/Economy")
local MenuModel = require("../src/shared/Ui/MenuModel")

local DAY = 20000
local NOON = DAY * 86400 + 43200

local function view(coins: number): { [string]: any }
	local p: any = Economy.blankProfile()
	p.coins = coins
	p.daily = { lastDay = DAY, streak = 1 }
	return p
end

Harness.test("MenuModel: a broke new player has no dots", function()
	local dots = MenuModel.dots(view(0), NOON, {})
	Harness.eq(MenuModel.anyDot(dots), false)
end)

Harness.test(
	"MenuModel: the first affordable upgrade lights Upgrades and the MENU button",
	function()
		local dots = MenuModel.dots(view(40), NOON, {})
		Harness.eq(dots.upgrades, true)
		Harness.eq(MenuModel.anyDot(dots), true)
		Harness.eq(dots.tools, nil) -- the Push Broom costs far more
	end
)

Harness.test(
	"MenuModel: opening a shop quiets its dot until something NEW is affordable",
	function()
		local acks: MenuModel.Acks = {}
		local v = view(40)
		MenuModel.ack(acks, "upgrades", v)
		Harness.eq(MenuModel.dots(v, NOON, acks).upgrades, nil)
		-- more coins: lines that were too dear before are now affordable -> the dot comes back
		local rich = view(5000)
		Harness.eq(MenuModel.dots(rich, NOON, acks).upgrades, true)
		-- fewer coins never brings it back on its own
		Harness.eq(MenuModel.dots(view(20), NOON, acks).upgrades, nil)
		-- acking one shop never quiets another
		Harness.eq(MenuModel.dots(rich, NOON, acks).helpers, true)
	end
)

Harness.test("MenuModel: the daily dot follows the server's UTC day", function()
	local v = view(0)
	Harness.eq(MenuModel.dots(v, NOON, {}).daily, nil) -- claimed today
	Harness.eq(MenuModel.dots(v, NOON + 86400, {}).daily, true) -- tomorrow
	Harness.eq(MenuModel.dailyReady(v, 0 / 0), false)
	Harness.eq(MenuModel.dailyReady({ daily = "bad" }, NOON), false)
	Harness.eq(MenuModel.dailyReady(nil, NOON), false)
	-- opening the daily panel does not hide a gift that is still waiting
	local acks: MenuModel.Acks = {}
	MenuModel.ack(acks, "daily", v)
	Harness.eq(MenuModel.dots(v, NOON + 86400, acks).daily, true)
	Harness.eq(MenuModel.tileNote("daily", v, NOON + 86400), "Ready!")
	Harness.eq(MenuModel.tileNote("daily", v, NOON), nil)
end)

Harness.test("MenuModel: Cool Down says Later for new players and Ready! when allowed", function()
	local v = view(0)
	Harness.eq(MenuModel.tileNote("cooldown", v, NOON), "Later")
	Harness.eq(MenuModel.dots(v, NOON, {}).cooldown, nil)
	v.runCoins = Config.Economy.coolDownMinRunCoins * 2
	Harness.eq(MenuModel.tileNote("cooldown", v, NOON), "Ready!")
	local acks: MenuModel.Acks = {}
	Harness.eq(MenuModel.dots(v, NOON, acks).cooldown, true)
	MenuModel.ack(acks, "cooldown", v)
	Harness.eq(MenuModel.dots(v, NOON, acks).cooldown, nil) -- seen once: no nagging
	local veteran = view(0)
	veteran.coolDowns = 2
	Harness.eq(MenuModel.tileNote("cooldown", veteran, NOON), nil)
	Harness.eq(MenuModel.tileNote("settings", veteran, NOON), nil)
end)

Harness.test("MenuModel: junk store values never throw", function()
	local junk: any = { coins = 0 / 0, upgrades = "x", toolsOwned = 5, runCoins = math.huge }
	local dots = MenuModel.dots(junk, NOON, {})
	Harness.eq(MenuModel.anyDot(dots), false)
	Harness.eq(MenuModel.anyDot(MenuModel.dots(nil, NOON, {})), false)
	MenuModel.ack({}, "nope", junk)
end)

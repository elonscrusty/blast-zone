--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local DailyRules = require("../src/shared/Daily/DailyRules")
local MemoryStore = require("../src/shared/Progression/MemoryStore")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local ProgressService = require("../src/shared/Progression/ProgressService")
local RemoteDefs = require("../src/shared/RemoteDefs")
local ShopDefs = require("../src/shared/Shop/ShopDefs")
local ShopRules = require("../src/shared/Shop/ShopRules")
local ShopService = require("../src/shared/Shop/ShopService")
local ShopText = require("../src/shared/Shop/ShopText")
local TrackDefs = require("../src/shared/Progression/TrackDefs")
local Types = require("../src/shared/Types")

local DAY0 = 20000

-- ===== the list =====

Harness.test("shop: ids are saveable and unique and never clash with the track", function()
	local seen: { [string]: boolean } = {}
	for _, o in ShopDefs.list do
		Harness.truthy(string.match(o.id, "^[a-z][a-z0-9_]*$") ~= nil, o.id)
		Harness.truthy(#o.id <= 24, o.id .. " is longer than the BuyRequest id limit")
		Harness.truthy(not seen[o.id], "duplicate " .. o.id)
		seen[o.id] = true
		Harness.truthy(string.match(o.color, "^#%x%x%x%x%x%x$") ~= nil, o.id .. " color")
		Harness.truthy(o.slot == "trail" or o.slot == "tracer", o.id .. " slot")
		Harness.eq(o.price, Config.Shop.prices[o.rarity], o.id .. " price comes from its rarity")
		Harness.truthy(o.price > 0, o.id .. " must cost something")
	end
	for _, list in { TrackDefs.defaults, TrackDefs.tiers, TrackDefs.gifts } do
		for _, it in list do
			Harness.truthy(not seen[it.id], it.id .. " is both a track item and a shop item")
		end
	end
end)

Harness.test("shop: every shop look is a real item with the shop's price", function()
	for _, o in ShopDefs.list do
		local item = TrackDefs.get(o.id)
		Harness.truthy(item ~= nil, o.id .. " missing from TrackDefs")
		local def = item :: TrackDefs.Item
		Harness.eq(def.cost, o.price)
		Harness.eq(def.slot, o.slot)
		Harness.eq(def.color, o.color)
	end
	Harness.eq(#TrackDefs.shop, #ShopDefs.list)
end)

Harness.test("shop: the daily slots can always be filled from the pool", function()
	local need: { [string]: number } = {}
	for _, rarity in Config.Shop.dailySlots do
		need[rarity] = (need[rarity] or 0) + 1
		Harness.truthy(Config.Shop.prices[rarity] ~= nil, rarity .. " has no price")
	end
	for rarity, n in need do
		Harness.truthy(#ShopDefs.pool(rarity) >= n, `pool for {rarity} is smaller than its slots`)
	end
	Harness.truthy(#ShopDefs.always() >= 1, "nothing is always on sale")
end)

Harness.test("shop: prices stay within reach of the Scrap that matches pay", function()
	local best = Config.Rewards.participation
		+ Config.Rewards.placementBonus[1]
		+ Config.Rewards.perElimination * 4
	for rarity, price in Config.Shop.prices do
		Harness.truthy(price <= best * 8, `{rarity} costs more than 8 great matches`)
	end
end)

-- ===== stock =====

Harness.test("shop: every day has the always-on looks plus one look per daily slot", function()
	for day = DAY0, DAY0 + 60 do
		local stock = ShopRules.stockFor(day)
		Harness.eq(#stock, #ShopDefs.always() + #Config.Shop.dailySlots, "day " .. day)
		local seen: { [string]: boolean } = {}
		for _, o in stock do
			Harness.truthy(not seen[o.id], `day {day}: {o.id} twice`)
			seen[o.id] = true
		end
		for _, a in ShopDefs.always() do
			Harness.truthy(seen[a.id], `day {day}: always-on {a.id} missing`)
		end
	end
end)

Harness.test("shop: the same day gives the same shop, and the shop changes over time", function()
	local function key(day: number): string
		local ids = {}
		for _, o in ShopRules.stockFor(day) do
			table.insert(ids, o.id)
		end
		return table.concat(ids, ",")
	end
	Harness.eq(key(DAY0), key(DAY0))
	local kinds: { [string]: boolean } = {}
	for day = DAY0, DAY0 + 30 do
		kinds[key(day)] = true
	end
	Harness.truthy(next(kinds) ~= nil)
	local count = 0
	for _ in kinds do
		count += 1
	end
	Harness.truthy(count >= 8, "the shop barely changes: " .. count .. " different days in 31")
end)

Harness.test("shop: over a month every daily look shows up", function()
	local shown: { [string]: boolean } = {}
	for day = DAY0, DAY0 + 90 do
		for _, o in ShopRules.stockFor(day) do
			shown[o.id] = true
		end
	end
	for _, o in ShopDefs.list do
		Harness.truthy(shown[o.id], o.id .. " never goes on sale")
	end
end)

-- ===== buying (pure rules) =====

local function richPlayer(): ProgressRules.Progression
	local p = ProgressRules.new()
	p.coins = 10000
	return p
end

local function firstDaily(day: number): ShopDefs.Offer
	for _, o in ShopRules.stockFor(day) do
		if not o.always then
			return o
		end
	end
	error("no daily look")
end

Harness.test("buy: spends exactly the shop's price, owns it, wears it", function()
	local p = richPlayer()
	local o = firstDaily(DAY0)
	Harness.truthy(ShopRules.buy(p, o.id, DAY0).ok)
	Harness.eq(p.coins, 10000 - o.price)
	Harness.truthy(ProgressRules.owns(p, o.id))
	Harness.eq(ProgressRules.equippedIn(p, o.slot :: any).id, o.id)
end)

Harness.test("buy: refusals change nothing", function()
	local p = ProgressRules.new()
	p.coins = 10
	local o = firstDaily(DAY0)
	Harness.eq(ShopRules.buy(p, o.id, DAY0).reason, "tooPoor")
	Harness.eq(p.coins, 10)
	Harness.eq(next(p.unlocked), nil)

	p.coins = 10000
	Harness.eq(ShopRules.buy(p, "no_such_look", DAY0).reason, "notInStock")
	Harness.eq(
		ShopRules.buy(p, TrackDefs.tiers[1].id, DAY0).reason,
		"notInStock",
		"track looks are not sold"
	)
	Harness.eq(
		ShopRules.buy(p, "trail_cyan", DAY0).reason,
		"notInStock",
		"free defaults are not sold"
	)
	Harness.truthy(ShopRules.buy(p, o.id, DAY0).ok)
	local after = p.coins
	Harness.eq(ShopRules.buy(p, o.id, DAY0).reason, "owned", "no double buy")
	Harness.eq(p.coins, after)
end)

Harness.test("buy: only what is on sale today, never something from another day", function()
	local p = richPlayer()
	local today = ShopRules.stockFor(DAY0)
	local todayIds: { [string]: boolean } = {}
	for _, o in today do
		todayIds[o.id] = true
	end
	local other: ShopDefs.Offer? = nil
	for _, o in ShopDefs.list do
		if not todayIds[o.id] then
			other = o
			break
		end
	end
	Harness.truthy(other ~= nil, "every look is on sale on day 0; the test needs a smaller sale")
	Harness.eq(ShopRules.buy(p, (other :: ShopDefs.Offer).id, DAY0).reason, "notInStock")
	Harness.eq(p.coins, 10000)
end)

Harness.test("buy: a bought look stays owned after the day turns", function()
	local p = richPlayer()
	local o = firstDaily(DAY0)
	Harness.truthy(ShopRules.buy(p, o.id, DAY0).ok)
	Harness.truthy(ProgressRules.owns(p, o.id))
	Harness.eq(ShopRules.buy(p, o.id, DAY0 + 1).reason ~= nil, true)
	Harness.truthy(ProgressRules.owns(p, o.id), "yesterday's purchase is still yours")
end)

Harness.test("buy: an unbought shop look is not worn even if a save says so", function()
	local p = ProgressRules.new()
	local o = ShopDefs.list[#ShopDefs.list]
	p.equipped[o.slot] = o.id
	Harness.eq(
		ProgressRules.equippedIn(p, o.slot :: any).id,
		TrackDefs.defaultFor(o.slot :: any).id
	)
end)

-- ===== service (with the in-memory store) =====

local ME = { name = "me" }

type Rig = {
	progress: ProgressService.Service,
	shop: ShopService.Service,
	store: ProgressService.Store,
	progressSent: { Types.ProgressState },
	shopSent: { Types.ShopState },
	seen: { [any]: number },
	clock: { t: number },
	saves: number,
}

local function rig(coins: number): Rig
	local used = MemoryStore.new()
	used.update(ME, function(p)
		p.coins = coins
		return true
	end)
	local r: Rig = {
		progress = nil :: any,
		shop = nil :: any,
		store = used,
		progressSent = {},
		shopSent = {},
		seen = {},
		clock = { t = DAY0 * 86400 + 3600 },
		saves = 0,
	}
	local counting: ProgressService.Store = {
		status = used.status,
		read = used.read,
		update = used.update,
		grantOnce = used.grantOnce,
		saveNow = function(player: any): boolean
			r.saves += 1
			return used.saveNow(player)
		end,
	}
	r.progress = ProgressService.new({
		store = counting,
		maxGrant = Config.Progression.maxMatchGrant,
		xpCap = Config.Level.maxXpPerMatch,
		receiptKey = function(matchId: number): string
			return "job:" .. tostring(matchId)
		end,
		send = function(_player: any, state: Types.ProgressState)
			table.insert(r.progressSent, state)
		end,
		applyLook = function() end,
	})
	r.shop = ShopService.new({
		buy = function(player: any, itemId: string, day: number): (boolean, string?)
			return r.progress.buy(player, itemId, day)
		end,
		status = used.status,
		seenDay = function(player: any): number?
			return r.seen[player]
		end,
		setSeenDay = function(player: any, day: number)
			r.seen[player] = day
		end,
		send = function(_player: any, state: Types.ShopState)
			table.insert(r.shopSent, state)
		end,
		now = function(): number
			return r.clock.t
		end,
		resetHour = Config.Daily.resetHourUtc,
	})
	return r
end

local function coinsOf(r: Rig): number
	return (r.store.read(ME) :: ProgressRules.Progression).coins
end

Harness.test("service: push lists today's stock, the timer, and the new mark", function()
	local r = rig(0)
	r.shop.push(ME)
	local s = r.shopSent[1]
	Harness.eq(s.day, DAY0)
	Harness.eq(#s.offers, #ShopDefs.always() + #Config.Shop.dailySlots)
	Harness.eq(s.secondsLeft, DailyRules.secondsLeft(r.clock.t, Config.Daily.resetHourUtc))
	Harness.eq(s.isNew, true)
	Harness.eq(s.status, "temporary")
	for i, o in ShopRules.stockFor(DAY0) do
		Harness.eq(s.offers[i].id, o.id)
		Harness.eq(s.offers[i].price, o.price)
	end
end)

Harness.test("service: opening the shop clears the new mark until the day turns", function()
	local r = rig(0)
	r.shop.markSeen(ME)
	Harness.eq(r.shopSent[#r.shopSent].isNew, false)
	r.shop.push(ME)
	Harness.eq(r.shopSent[#r.shopSent].isNew, false)
	r.clock.t += 86400
	r.shop.push(ME)
	Harness.eq(r.shopSent[#r.shopSent].isNew, true, "a new day is new again")
	Harness.eq(r.shopSent[#r.shopSent].day, DAY0 + 1)
end)

Harness.test(
	"service: a buy spends Scrap, saves, wears the look, and tells both screens",
	function()
		local r = rig(1000)
		local o = firstDaily(DAY0)
		local ok = r.shop.buy(ME, o.id)
		Harness.truthy(ok)
		Harness.eq(coinsOf(r), 1000 - o.price)
		Harness.truthy(r.saves >= 1, "a buy asks for a save")
		local ps = r.progressSent[#r.progressSent]
		Harness.eq(ps.coins, 1000 - o.price)
		Harness.truthy(table.find(ps.unlocked, o.id) ~= nil, "the client learns it is owned")
		Harness.eq(ps.equipped[o.slot], o.id)
		local ss = r.shopSent[#r.shopSent]
		Harness.eq(ss.bought, o.id)
		Harness.eq(ss.denied, nil)
	end
)

Harness.test("service: a refused buy says why and costs nothing", function()
	local r = rig(5)
	local o = firstDaily(DAY0)
	Harness.truthy(not r.shop.buy(ME, o.id))
	Harness.eq(coinsOf(r), 5)
	Harness.eq(r.shopSent[#r.shopSent].denied, "tooPoor")
	Harness.eq(r.shopSent[#r.shopSent].bought, nil)
	Harness.eq(r.progressSent[#r.progressSent].denied, "tooPoor")
	Harness.eq(r.saves, 0, "nothing changed, nothing to save")
end)

Harness.test("service: buying the same look again, or junk ids, never charges twice", function()
	local r = rig(1000)
	local o = firstDaily(DAY0)
	Harness.truthy(r.shop.buy(ME, o.id))
	local after = coinsOf(r)
	for _ = 1, 5 do
		Harness.truthy(not r.shop.buy(ME, o.id))
	end
	Harness.truthy(not r.shop.buy(ME, "not_a_look"))
	Harness.truthy(not r.shop.buy(ME, ""))
	Harness.eq(coinsOf(r), after)
	Harness.eq(r.shopSent[#r.shopSent].denied, "notInStock")
end)

Harness.test(
	"service: the server's clock decides the day, so yesterday's look is refused",
	function()
		local r = rig(5000)
		local yesterday = ShopRules.stockFor(DAY0)
		local todayIds: { [string]: boolean } = {}
		r.clock.t += 86400 * 3
		for _, o in ShopRules.stockFor(DAY0 + 3) do
			todayIds[o.id] = true
		end
		local gone: ShopDefs.Offer? = nil
		for _, o in yesterday do
			if not todayIds[o.id] then
				gone = o
				break
			end
		end
		Harness.truthy(gone ~= nil, "the test needs a look that left the shop")
		Harness.truthy(not r.shop.buy(ME, (gone :: ShopDefs.Offer).id))
		Harness.eq(coinsOf(r), 5000)
	end
)

Harness.test("service: shop looks come back in ProgressState after a rejoin-style push", function()
	local r = rig(1000)
	local o = firstDaily(DAY0)
	Harness.truthy(r.shop.buy(ME, o.id))
	r.progress.push(ME)
	local ps = r.progressSent[#r.progressSent]
	Harness.truthy(table.find(ps.unlocked, o.id) ~= nil)
	Harness.eq(ps.equipped[o.slot], o.id)
end)

-- ===== words and remotes =====

Harness.test("text: card buttons and refusal words are short and never show a code", function()
	Harness.eq(ShopText.button(true, true, 60, 0), "WORN")
	Harness.eq(ShopText.button(true, false, 60, 0), "WEAR")
	Harness.eq(ShopText.button(false, false, 60, 100), "BUY 60")
	Harness.eq(ShopText.button(false, false, 60, 50), "60 (need 10)")
	Harness.eq(ShopText.denied(nil), "")
	Harness.eq(ShopText.denied("something_new"), "")
	for _, reason in { "notInStock", "owned", "tooPoor" } do
		local w = ShopText.denied(reason)
		Harness.truthy(#w > 0 and #w <= 30, reason)
	end
	Harness.eq(ShopText.timer(3 * 3600 + 20 * 60), "New in 3h 20m")
	Harness.eq(ShopText.timer(30), "New in 1m")
end)

Harness.test("remotes: the shop asks are limited and BuyRequest takes only an id", function()
	for _, name in { "ShopRequest", "ShopSeenRequest", "BuyRequest" } do
		local def = RemoteDefs.byName[name]
		Harness.truthy(def ~= nil, name .. " missing")
		Harness.eq(def.direction, "toServer")
		Harness.truthy(def.rate ~= nil and (def.rate :: any).perSecond <= 2, name .. " rate")
	end
	local buy = RemoteDefs.byName.BuyRequest
	Harness.eq(#(buy.schema :: any), 1)
	Harness.eq((buy.schema :: any)[1].name, "itemId")
	Harness.eq(RemoteDefs.byName.ShopState.direction, "toClient")
end)

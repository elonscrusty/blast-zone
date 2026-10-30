--!strict
-- The Scrap Shop against injected deps, so Lune can test it. Only the server runs it.
--   push(player)           sends today's shop (what is on sale, when it changes, and whether it is new to them).
--   markSeen(player)       the player opened the shop: today's "new" dot goes away, saved with the profile.
--   buy(player, itemId)    asks Progress to buy it for the shop day the SERVER works out; then tells the player.
-- Coins, owned looks and what is worn are ProgressState's job, so this sends no coin numbers.

local DailyRules = require("../Daily/DailyRules")
local ShopRules = require("./ShopRules")
local Types = require("../Types")

export type Deps = {
	-- Buys with the progression rules (ProgressService.buy). ok, or false with a reason.
	buy: (player: any, itemId: string, day: number) -> (boolean, string?),
	status: (player: any) -> string,
	seenDay: (player: any) -> number?, -- the last shop day this player opened, if known
	setSeenDay: (player: any, day: number) -> (),
	send: (player: any, state: Types.ShopState) -> (),
	now: () -> number, -- unix seconds (os.time on the server)
	resetHour: number,
}

export type Service = {
	push: (player: any) -> (),
	markSeen: (player: any) -> (),
	buy: (player: any, itemId: string) -> (boolean, string?),
	today: () -> number,
}

local ShopService = {}

function ShopService.new(deps: Deps): Service
	local service = {} :: Service

	local function today(): number
		return DailyRules.dayOf(deps.now(), deps.resetHour)
	end

	local function send(player: any, bought: string?, denied: string?)
		local day = today()
		local offers: { Types.ShopOfferView } = {}
		for _, o in ShopRules.stockFor(day) do
			table.insert(offers, {
				id = o.id,
				slot = o.slot,
				name = o.name,
				color = o.color,
				rarity = o.rarity,
				price = o.price,
				always = o.always,
			})
		end
		deps.send(player, {
			status = deps.status(player),
			day = day,
			secondsLeft = DailyRules.secondsLeft(deps.now(), deps.resetHour),
			offers = offers,
			isNew = deps.seenDay(player) ~= day,
			bought = bought,
			denied = denied,
		})
	end

	function service.today(): number
		return today()
	end

	function service.push(player: any)
		send(player, nil, nil)
	end

	function service.markSeen(player: any)
		local day = today()
		if deps.seenDay(player) ~= day then
			deps.setSeenDay(player, day)
		end
		send(player, nil, nil)
	end

	function service.buy(player: any, itemId: string): (boolean, string?)
		local ok, reason = deps.buy(player, itemId, today())
		send(player, if ok then itemId else nil, if ok then nil else reason or "failed")
		return ok, reason
	end

	return service
end

return ShopService

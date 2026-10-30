--!strict
-- Pure rules for the Scrap Shop: what is on sale today, and whether a buy is allowed. No Roblox, so Lune tests it.
-- Every pick depends only on the day number, so all servers show the same shop. A buy checks first and only then
-- changes the saved progression table; a refusal leaves it untouched. The client only ever ASKS to buy.

local ProgressRules = require("../Progression/ProgressRules")
local ShopDefs = require("./ShopDefs")
local Config = require("../Config")

local ShopRules = {}

export type Result = ProgressRules.Result

-- Small number mixer that stays exact in doubles (same idea as DailyRules.mix).
local function mix(a: number, b: number): number
	local h = (a * 31 + b * 17) % 1000003
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end

-- Today's shop: the always-on looks first, then one look per daily slot, never the same look twice.
function ShopRules.stockFor(day: number): { ShopDefs.Offer }
	local out = ShopDefs.always()
	local used: { [string]: boolean } = {}
	for _, o in out do
		used[o.id] = true
	end
	for slotIndex, rarity in Config.Shop.dailySlots do
		local pool = ShopDefs.pool(rarity)
		if #pool > 0 then
			local start = mix(day, slotIndex) % #pool
			for step = 0, #pool - 1 do
				local pick = pool[(start + step) % #pool + 1]
				if not used[pick.id] then
					used[pick.id] = true
					table.insert(out, pick)
					break
				end
			end
		end
	end
	return out
end

function ShopRules.inStock(day: number, itemId: string): ShopDefs.Offer?
	for _, o in ShopRules.stockFor(day) do
		if o.id == itemId then
			return o
		end
	end
	return nil
end

local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

-- Buys one look from today's shop. The price is the shop's, never the client's. The new look is worn at once.
-- Reasons: "notInStock" (also unknown ids), "owned", "tooPoor".
function ShopRules.buy(p: ProgressRules.Progression, itemId: string, day: number): Result
	local o = ShopRules.inStock(day, itemId)
	if o == nil then
		return refuse("notInStock")
	end
	if ProgressRules.owns(p, itemId) then
		return refuse("owned")
	end
	if p.coins < o.price then
		return refuse("tooPoor")
	end
	p.coins -= o.price
	p.unlocked[itemId] = true
	ProgressRules.equip(p, itemId)
	return { ok = true, reason = nil }
end

return ShopRules

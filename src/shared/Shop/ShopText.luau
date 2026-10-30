--!strict
-- Words for the Scrap Shop screen. Pure, so Lune checks them. Tiny words: carter plays on a phone.

local ShopText = {}

local denied: { [string]: string } = {
	notInStock = "Not in the shop today",
	owned = "You have it",
	tooPoor = "Not enough",
	temporary = "Test mode: not saved",
	loading = "Loading...",
	failed = "Shop not loaded",
	lost = "Shop not loaded",
}

-- Why a buy did not work, in a few words. Unknown reasons say nothing rather than show a code.
function ShopText.denied(reason: string?): string
	if reason == nil then
		return ""
	end
	return denied[reason] or ""
end

function ShopText.timer(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = math.max(1, (s % 3600 + 59) // 60)
	if m == 60 then
		h += 1
		m = 0
	end
	if h > 0 then
		return `New in {h}h {m}m`
	end
	return `New in {m}m`
end

-- What the button on a card says: owned looks can be worn, others show the price.
function ShopText.button(owned: boolean, worn: boolean, price: number, coins: number): string
	if worn then
		return "WORN"
	end
	if owned then
		return "WEAR"
	end
	if coins < price then
		return `{price} (need {price - coins})`
	end
	return `BUY {price}`
end

return ShopText

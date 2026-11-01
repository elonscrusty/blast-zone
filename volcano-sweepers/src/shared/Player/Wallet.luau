--!strict
-- Paying rewards into a profile (daily, goals). Pure. Coins count as earned this run too (they feed
-- the Spark maths); everything stays a whole number inside the saved caps.

local Types = require("../Types")
local ProfileSchema = require("../Profile/ProfileSchema")

local Wallet = {}

local function whole(n: number): number
	if n ~= n or n <= 0 or n == math.huge then
		return 0
	end
	return math.floor(n)
end

-- Adds `coins` and `sparks` (bad numbers count as 0). Returns what was really paid.
function Wallet.earn(profile: Types.Profile, coins: number, sparks: number): (number, number)
	local maxCoins = ProfileSchema.MAX.coins
	local c = whole(coins)
	local s = whole(sparks)
	if c > 0 then
		local before = profile.coins
		profile.coins = math.min(maxCoins, profile.coins + c)
		profile.runCoins = math.min(maxCoins, profile.runCoins + c)
		profile.lifetimeCoins = math.min(maxCoins, profile.lifetimeCoins + c)
		c = profile.coins - before
	end
	if s > 0 then
		local before = profile.sparks
		profile.sparks = math.min(ProfileSchema.MAX.sparks, profile.sparks + s)
		s = profile.sparks - before
	end
	return c, s
end

return Wallet

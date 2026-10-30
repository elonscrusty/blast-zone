--!strict
-- The counters in the top bar, in the order they are drawn (video 3 gap 17). Add a counter by adding a line here.
--   scrap   the main coin. Lives in the progression table (piece 18), so `saved` is false: the wallet only READS it.
--   stars  a second, rarer counter, saved in data.wallet. Earned by playing; never sold for Robux, never power.
-- Ids are saved text (lowercase a-z 0-9 _): never rename one. `always` = drawn even at 0; otherwise it appears
-- the first time it is above 0.

local Config = require("../Config")

export type Def = {
	id: string,
	name: string, -- long name for panels and messages
	short: string, -- tiny name for the bar
	saved: boolean, -- true: stored in data.wallet. false: owned by another piece (scrap)
	always: boolean,
}

local WalletDefs = {}

WalletDefs.list = {
	{
		id = "scrap",
		name = Config.Rewards.currencyName,
		short = "SCRAP",
		saved = false,
		always = true,
	},
	{ id = "stars", name = "Stars", short = "STARS", saved = true, always = true },
} :: { Def }

local byId: { [string]: Def } = {}
for _, def in WalletDefs.list do
	byId[def.id] = def
end

function WalletDefs.get(id: string): Def?
	return byId[id]
end

-- Only the counters this piece saves (not scrap).
function WalletDefs.isSaved(id: string): boolean
	local def = byId[id]
	return def ~= nil and def.saved
end

return WalletDefs

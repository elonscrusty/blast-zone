--!strict
-- Prints the hero roster as JSON for the preview page:  lune run tools/hero_json
-- Real numbers: every card comes from GunCards, at the three spreads carter picks between.
local serde = require("@lune/serde")
local Config = require("../src/shared/Config")
local GunCards = require("../src/shared/GunCards")
local Heroes = require("../src/shared/Heroes")
local WeaponModels = require("../src/client/Combat/WeaponModels")

local spreads = { { key = "A", name = "Small", spread = 0.5 }, { key = "B", name = "Medium", spread = 1 }, { key = "C", name = "Big", spread = 1.5 } }
local out: any = { spreads = {}, guns = WeaponModels.models, order = {} }
for _, hero in Heroes.list do
	table.insert(out.order, hero.id)
end
for _, s in spreads do
	local cfg: any = table.clone(Config :: any)
	cfg.Heroes = table.clone(Config.Heroes :: any)
	cfg.Heroes.spread = s.spread
	local heroes: any = {}
	for _, hero in Heroes.list do
		heroes[hero.id] = GunCards.hero(cfg, hero.id)
	end
	table.insert(out.spreads, { key = s.key, name = s.name, spread = s.spread, heroes = heroes })
end
print(serde.encode("json", out, false))

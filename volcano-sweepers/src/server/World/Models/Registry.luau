--!strict
-- One list of every model builder, so wiring code, the preview and the tests can loop over them.
--   Registry.spec("Palm", { style = "toy", v = 12 })  ->  Kit.Model (pure data)
-- Models/Build.luau turns a Kit.Model into real Parts.

local Camp = require("./Camp")
local Gate = require("./Gate")
local Kit = require("./Kit")
local Mushroom = require("./Mushroom")
local Palm = require("./Palm")
local Rocks = require("./Rocks")
local Sign = require("./Sign")
local Spire = require("./Spire")
local TradeHut = require("./TradeHut")

local Registry = {}

-- What every model file exports.
type ModelModule = {
	maxParts: number,
	spec: (params: Kit.Params?) -> Kit.Model,
}

local modules: { [string]: ModelModule } = {
	TradeHut = TradeHut,
	Gate = Gate,
	Camp = Camp,
	Palm = Palm,
	Rocks = Rocks,
	Mushroom = Mushroom,
	Spire = Spire,
	Sign = Sign,
}

Registry.names = { "TradeHut", "Gate", "Camp", "Palm", "Rocks", "Mushroom", "Spire", "Sign" }

-- Most parts each model may use (phone budget). Tests keep every style under it.
Registry.maxParts = {} :: { [string]: number }
for name, module in modules do
	Registry.maxParts[name] = module.maxParts
end

function Registry.spec(name: string, params: Kit.Params?): Kit.Model
	local module = modules[name]
	if module == nil then
		error(`unknown model '{name}'`)
	end
	return module.spec(params)
end

return Registry

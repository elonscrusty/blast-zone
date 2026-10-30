--!strict
-- Builds the arena once at server start. Other pieces find it by tag (Config.Tags), so there is
-- nothing to call. The layout is picked by Config.Arena.layout.
local ArenaBuilder = require("./ArenaBuilder")
local Layout = require("./Layout")

local specs: { [string]: Layout.Spec } = {
	A = require("./LayoutA"),
	B = require("./LayoutB"),
	C = require("./LayoutC"),
}

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local ArenaSystem = {}
ArenaSystem.order = 10 -- before anything that looks for spawns or crate spots

local built: ArenaBuilder.Built? = nil

function ArenaSystem.start()
	local spec = specs[Config.Arena.layout]
	if not spec then
		warn(`[arena] no layout called {Config.Arena.layout}, using A`)
		spec = specs.A
	end
	built = ArenaBuilder.build(Layout.compile(spec))
end

function ArenaSystem.getLayout(): Layout.Layout?
	return if built then built.layout else nil
end

return ArenaSystem

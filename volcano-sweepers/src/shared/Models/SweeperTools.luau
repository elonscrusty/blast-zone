--!strict
-- The eight sweeper tools as held 3D models (client/Vfx/HeldTool builds them on every client).
--   SweeperTools.build("dragon_vac", "A")      -> Model, the part in the hand (grip at the origin,
--                                                 hangs along -Y, -Z is forward)
--   SweeperTools.buildBack("dragon_vac", "A")  -> Model? the backpack / wings / tanks (torso space,
--                                                 origin = torso centre, +Z is behind); nil when a
--                                                 tool has none
-- opts.lite = true builds only the basic shape (for players far away).
-- `look` is "A" Toy | "B" Steel | "C" Candy (default "A"). Unknown tool id -> the Twig Broom.
-- Models are welded to a see-through Root part (PrimaryPart); weld to the hand grip / torso with
-- ModelBuilder opts.cf or by moving the Root.

local ModelBuilder = require(script.Parent.ModelBuilder)
local ToolSpecs = require(script.Parent.ToolSpecs)

local SweeperTools = {}

-- tool ids in tier order
SweeperTools.ids = {
	"twig_broom",
	"push_broom",
	"leaf_blower",
	"dust_vac",
	"turbo_vac",
	"lava_mop",
	"dragon_vac",
	"volcano_vac",
} :: { string }
SweeperTools.looks = { "A", "B", "C" } :: { string } -- carter keeps all three: A is the main look, B and C are skins
SweeperTools.defaultLook = "A"

function SweeperTools.build(id: string, look: string?, opts: ModelBuilder.Opts?): Model
	local spec = ToolSpecs.build(id, look, opts ~= nil and opts.lite == true)
	return ModelBuilder.build(spec.id, spec.hand, opts)
end

function SweeperTools.buildBack(id: string, look: string?, opts: ModelBuilder.Opts?): Model?
	local spec = ToolSpecs.build(id, look, opts ~= nil and opts.lite == true)
	if #spec.back == 0 then
		return nil
	end
	return ModelBuilder.build(spec.id .. "Back", spec.back, opts)
end

return SweeperTools

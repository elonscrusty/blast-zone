--!strict
-- One door for the big landmarks. The main world file calls this (nothing here is wired yet).
--
--   Landmarks.build("volcano", parent, CFrame.new(0, 0, 0))                 -- look "A", scale 1
--   Landmarks.build("lighthouse", parent, cf, { variant = "B", scale = 1.5 })
--
-- kinds: "volcano", "lava", "spring", "lighthouse". variants: "A" (toy), "B" (low-poly rock),
-- "C" (wild). Use `Landmarks.spec` for the pure part list (counts, tests). The volcano carries an
-- invisible solid core named "ConeCollision" so nobody walks into the mountain.

local BigVolcano = require(script.Parent.BigVolcano)
local HotSpring = require(script.Parent.HotSpring)
local LavaPool = require(script.Parent.LavaPool)
local Lighthouse = require(script.Parent.Lighthouse)
local ModelBuild = require(script.Parent.ModelBuild)
local Parts = require(script.Parent.Parts)

local Landmarks = {}

export type Options = { variant: string?, scale: number? }

local MODELS: { [string]: { variants: { string }, spec: (string, number?) -> Parts.List } } = {
	volcano = BigVolcano,
	lava = LavaPool,
	spring = HotSpring,
	lighthouse = Lighthouse,
}

Landmarks.kinds = { "volcano", "lava", "spring", "lighthouse" }

-- The look used when `variant` is left out. The other two stay in the code as skins.
Landmarks.defaultVariant = "A"

function Landmarks.spec(kind: string, variant: string?, scale: number?): Parts.List?
	local m = MODELS[kind]
	if m == nil then
		return nil
	end
	return m.spec(variant or Landmarks.defaultVariant, scale)
end

function Landmarks.build(
	kind: string,
	parent: Instance,
	origin: CFrame,
	opts: Options?
): ModelBuild.Refs?
	local list = Landmarks.spec(kind, opts and opts.variant, opts and opts.scale)
	if list == nil then
		warn(`Landmarks: unknown kind {kind}`)
		return nil
	end
	return ModelBuild.build(parent, list, origin)
end

return Landmarks

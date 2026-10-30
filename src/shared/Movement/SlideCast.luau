--!strict
-- "How far can this body slide that way?" Sweeps a body-sized box along the path, then checks the
-- floor under the path and the arena edge. Used by the server (the real answer) and the client
-- (so the slide starts at once and agrees). It reads collision only: roofs and hidden visual
-- geometry are CanCollide = false and never matter here.

local Workspace = game:GetService("Workspace")

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local SlideRules = require("./SlideRules")

local SlideCast = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

local function paramsFor(character: Model, root: BasePart): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup
	return params
end

-- Returns the allowed distance (0 .. wanted). dirX/dirZ must be a unit direction.
function SlideCast.resolve(
	character: Model,
	root: BasePart,
	hipHeight: number,
	dirX: number,
	dirZ: number,
	wanted: number,
	bounds: Bounds?
): number
	local cfg = Config.Slide
	local origin = root.Position
	local dir = Vector3.new(dirX, 0, dirZ)
	local params = paramsFor(character, root)

	local feetY = origin.Y - (hipHeight + root.Size.Y / 2)
	local bottom = feetY + cfg.clearance
	local top = origin.Y + 1.5
	local height = math.max(0.5, top - bottom)
	local start = Vector3.new(origin.X, bottom + height / 2, origin.Z)

	local hit = Workspace:Blockcast(
		CFrame.lookAt(start, start + dir),
		Vector3.new(cfg.bodyWidth, height, cfg.bodyWidth),
		dir * wanted,
		params
	)
	local distance = SlideRules.clampToBlock(wanted, if hit then hit.Distance else nil, cfg.skin)

	if bounds and distance > 0 then
		distance = SlideRules.clampToBounds(
			origin.X,
			origin.Z,
			dirX,
			dirZ,
			distance,
			bounds.minX,
			bounds.maxX,
			bounds.minZ,
			bounds.maxZ
		)
	end

	if distance > 0 then
		local samples = SlideRules.groundSamples(distance, cfg.groundStep)
		local hasGround = {}
		local down = Vector3.new(0, -((origin.Y - feetY) + cfg.maxDrop), 0)
		for i, d in samples do
			local from = origin + dir * d
			hasGround[i] = Workspace:Raycast(from, down, params) ~= nil
		end
		distance = SlideRules.clampToGround(distance, samples, hasGround)
	end
	return distance
end

return SlideCast

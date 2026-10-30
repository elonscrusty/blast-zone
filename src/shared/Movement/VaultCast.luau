--!strict
-- "Can this body hop over what is in front of it, and where does it land?" (piece 44). The server
-- makes the real plan; the client makes the same plan so the hop starts at once and agrees.
-- Only parts tagged Vaultable count (low walls, fences, cars). Reads collision only.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local VaultRules = require("./VaultRules")

local VaultCast = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Plan = {
	toPos: Vector3, -- where the body ends (same height as it started)
	distance: number, -- flat studs from the start
	peak: number, -- studs the arc rises at its highest
	duration: number,
	coverName: string,
}

local function bodyParams(character: Model, root: BasePart): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup
	return params
end

function VaultCast.plan(
	character: Model,
	root: BasePart,
	hipHeight: number,
	dirX: number,
	dirZ: number,
	bounds: Bounds?
): Plan?
	local cfg = Config.Vault
	if not cfg.enabled then
		return nil
	end
	local list = CollectionService:GetTagged(Config.Tags.Vaultable)
	if #list == 0 then
		return nil
	end
	local origin = root.Position
	local feetY = origin.Y - (hipHeight + root.Size.Y / 2)
	local dir = Vector3.new(dirX, 0, dirZ)

	-- 1. Is something hoppable right in front of the knees?
	local only = RaycastParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	only.FilterDescendantsInstances = list
	local knee = Vector3.new(origin.X, feetY + 1.2, origin.Z)
	local hit = Workspace:Raycast(knee, dir * cfg.reach, only)
	if hit == nil then
		return nil
	end
	local part = hit.Instance
	if not part:IsA("BasePart") then
		return nil
	end
	local topY = part.Position.Y + part.Size.Y / 2
	if topY - feetY > cfg.maxHeight then
		return nil
	end
	if not VaultRules.headOn(dirX, dirZ, hit.Normal.X, hit.Normal.Z, cfg.headOnDot) then
		return nil
	end

	-- 2. How thick is it along the way? Look back from past the far side; it must be the same thing.
	local reachBack = cfg.maxDepth + 0.1
	local back = Workspace:Raycast(hit.Position + dir * reachBack, -dir * reachBack, only)
	if back == nil or back.Instance ~= part then
		return nil
	end
	local depth = VaultRules.depth(0, dir:Dot(back.Position - hit.Position), cfg.maxDepth)
	if depth == nil then
		return nil
	end

	-- 3. Where would we land? Open floor at about the same height, with room for a body.
	local landing = back.Position + dir * cfg.landingPad
	local toPos = Vector3.new(landing.X, origin.Y, landing.Z)
	if
		bounds ~= nil
		and (
			toPos.X < bounds.minX
			or toPos.X > bounds.maxX
			or toPos.Z < bounds.minZ
			or toPos.Z > bounds.maxZ
		)
	then
		return nil
	end
	local params = bodyParams(character, root)
	local floor =
		Workspace:Raycast(Vector3.new(toPos.X, feetY + 4, toPos.Z), Vector3.new(0, -12, 0), params)
	if floor == nil or math.abs(floor.Position.Y - feetY) > cfg.floorTolerance then
		return nil
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	overlap.CollisionGroup = root.CollisionGroup
	local boxHeight = cfg.bodyHeight - 0.6
	local box = CFrame.new(toPos.X, feetY + 0.3 + boxHeight / 2, toPos.Z)
	if
		#Workspace:GetPartBoundsInBox(
			box,
			Vector3.new(cfg.bodyWidth, boxHeight, cfg.bodyWidth),
			overlap
		) > 0
	then
		return nil
	end

	local flat = Vector3.new(toPos.X - origin.X, 0, toPos.Z - origin.Z).Magnitude
	return {
		toPos = toPos,
		distance = flat,
		peak = VaultRules.peak(topY, feetY, cfg.clearance, cfg.maxPeak),
		duration = cfg.durationSeconds,
		coverName = part.Name,
	}
end

return VaultCast

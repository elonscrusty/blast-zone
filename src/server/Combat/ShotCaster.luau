--!strict
-- "What stops a shot?" in one place. Bullets, shells, blasts and bot eyesight all ask here, so the
-- rules are the same for everyone. Config.ShotRules + Config.Tags decide:
--   BlocksShots parts (walls, solid cover, crates) stop shots. LowCover and fences do not. Roofs are CanQuery=false.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local rules = Config.ShotRules
local tags = Config.Tags

local ShotCaster = {}

-- One params object for every cast (bullets, shells, blasts, bot eyes): casts never overlap, and making
-- a new one for each of them was the most common allocation in a fight.
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function taggedAncestor(inst: Instance, tag: string): Instance?
	local cur: Instance? = inst
	while cur ~= nil and cur ~= workspace do
		if CollectionService:HasTag(cur, tag) then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- The supply container this part belongs to, if any.
function ShotCaster.containerOf(inst: Instance): Instance?
	return taggedAncestor(inst, tags.SupplyContainer)
end

local function blocks(inst: Instance): boolean
	if rules.wallsBlockShots and taggedAncestor(inst, tags.BlocksShots) ~= nil then
		return true
	end
	if rules.lowCoverBlocksShots and taggedAncestor(inst, tags.LowCover) ~= nil then
		return true
	end
	if rules.containersBlockShots and ShotCaster.containerOf(inst) ~= nil then
		return true
	end
	return false
end

-- Distance to the first thing that stops a flat shot, and what it was. `ignore` are bodies;
-- parts under `except` (a crate being blasted) do not count. Things that do not stop shots are flown through.
function ShotCaster.cast(
	origin: Vector3,
	dirX: number,
	dirZ: number,
	dist: number,
	ignore: { Instance },
	except: Instance?
): (number?, Instance?)
	local list = table.clone(ignore)
	params.FilterDescendantsInstances = list
	local ray = Vector3.new(dirX, 0, dirZ) * dist
	for _ = 1, Config.Combat.maxPassThrough do
		local r = workspace:Raycast(origin, ray, params)
		if r == nil then
			return nil, nil
		end
		local inside = except ~= nil and r.Instance:IsDescendantOf(except)
		if not inside and blocks(r.Instance) then
			return (r.Position - origin).Magnitude, r.Instance
		end
		table.insert(list, r.Instance)
		params.FilterDescendantsInstances = list
	end
	-- Too many things in the way to keep looking: stop the shot here, never let it go on forever.
	return dist, nil
end

-- Is there a shot-stopping wall between two points? (Used for blasts, origin checks and bot eyesight.)
function ShotCaster.lineBlocked(
	from: Vector3,
	to: Vector3,
	ignore: { Instance },
	except: Instance?
): boolean
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 1e-3 then
		return false
	end
	local hit = ShotCaster.cast(from, delta.X / dist, delta.Z / dist, dist, ignore, except)
	return hit ~= nil
end

return ShotCaster

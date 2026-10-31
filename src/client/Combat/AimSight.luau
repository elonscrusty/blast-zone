--!strict
-- "Can I see that fighter?" for the phone's aim help. One flat ray from the hero's shot height to the
-- rival, through everything that does not stop shots (the same rules as the server's ShotCaster:
-- Config.ShotRules + Config.Tags). A rival behind a wall never pulls the aim, so the help is not a radar.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local AimSight = {}

local MAX_PASS_THROUGH = 6 -- low cover, fences and the like we may fly through before we give up

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function taggedAncestor(inst: Instance, tag: string): boolean
	local cur: Instance? = inst
	while cur ~= nil and cur ~= workspace do
		if CollectionService:HasTag(cur, tag) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function stopsShots(inst: Instance): boolean
	local rules = Config.ShotRules
	local tags = Config.Tags
	return (rules.wallsBlockShots and taggedAncestor(inst, tags.BlocksShots))
		or (rules.lowCoverBlocksShots and taggedAncestor(inst, tags.LowCover))
		or (rules.containersBlockShots and taggedAncestor(inst, tags.SupplyContainer))
end

-- `bodies` are fighter models (never a wall). True when nothing that stops a shot lies from `from` to `to`.
function AimSight.clear(from: Vector3, to: Vector3, bodies: { Instance }): boolean
	local ignore = table.clone(bodies)
	local delta = to - from
	for _ = 1, MAX_PASS_THROUGH do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(from, delta, params)
		if hit == nil then
			return true
		end
		if stopsShots(hit.Instance) then
			return false
		end
		table.insert(ignore, hit.Instance)
	end
	return false
end

return AimSight

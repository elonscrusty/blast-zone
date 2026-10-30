--!strict
-- The one call into the crate piece: ContainerSystem.damage(hitPart, amount, sourceId, matchId) -> true when
-- hitPart belongs to a supply container. Looked up on first use, so combat still works if crates are missing.

local cached: any? = nil
local looked = false
local brokenListeners: { (pos: Vector3, breakerId: string, matchId: number) -> () } = {}

local ContainerLink = {}

-- Called after a hit from combat breaks a container (gun drops listen here).
function ContainerLink.onBroken(fn: (pos: Vector3, breakerId: string, matchId: number) -> ())
	table.insert(brokenListeners, fn)
end

function ContainerLink.damage(
	part: Instance,
	amount: number,
	sourceId: string,
	matchId: number
): boolean
	if not looked then
		looked = true
		local pickups = script.Parent.Parent:FindFirstChild("Pickups")
		local module = pickups and pickups:FindFirstChild("ContainerSystem")
		if module ~= nil and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				cached = result
			else
				warn("[Combat] could not load ContainerSystem: " .. tostring(result))
			end
		end
	end
	local system: any = cached
	if system == nil then
		return false
	end
	local wasContainer = part:IsA("BasePart") and system.isContainer(part) == true
	local pos = if part:IsA("BasePart") then part.Position else Vector3.zero
	local hit = system.damage(part, amount, sourceId, matchId) == true
	-- A container leaves the crate piece's tables the moment it breaks.
	if wasContainer and system.isContainer(part) ~= true then
		for _, fn in brokenListeners do
			task.spawn(fn, pos, sourceId, matchId)
		end
	end
	return hit
end

return ContainerLink

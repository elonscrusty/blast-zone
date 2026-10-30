--!strict
-- The one call into the crate piece: ContainerSystem.damage(hitPart, amount, sourceId, matchId) -> true when
-- hitPart belongs to a supply container. Looked up on first use, so combat still works if crates are missing.

local cached: any? = nil
local looked = false

local ContainerLink = {}

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
	return system.damage(part, amount, sourceId, matchId) == true
end

return ContainerLink

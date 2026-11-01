--!strict
-- Crater Rim decor: bone-white ribs, glowing ground cracks (also used in the Lava Heart). The spires
-- are the picked Toy Pop model (DecorKinds/Models).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local R: { [string]: Builder } = {}

-- A giant rib: half a ring of bone standing in the ground.
function R.rib(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local radius = 3.6 * s
	local lat = V(math.cos(it.rot), 0, math.sin(it.rot))
	local base = V(it.x, 0, it.z)
	local pts: { Vector3 } = {}
	for k = 0, 4 do
		local theta = k * math.pi / 4
		table.insert(
			pts,
			base + lat * (radius * math.cos(theta)) + V(0, radius * math.sin(theta), 0)
		)
	end
	for k = 1, 4 do
		U.pole(parent, "Rib", pts[k], pts[k + 1], 0.7 * s, P.bone, { shadow = true })
	end
end

-- Thin glowing crack in the ground (flat, no collision). Zone 4 is orange, zone 5 is gold.
function R.crack(parent: Instance, it: WorldPlan.Item)
	local len = (3.5 + (it.v % 60) / 10) * it.scale
	local color = if it.zone == 5 then P.ember else P.lava
	U.block(
		parent,
		"Crack",
		CFrame.new(it.x, 0.06, it.z) * CFrame.Angles(0, it.rot, 0),
		V(0.35, 0.06, len),
		color,
		{
			material = Enum.Material.Neon,
		}
	)
end

return R

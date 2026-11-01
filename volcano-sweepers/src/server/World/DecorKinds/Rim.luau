--!strict
-- Crater Rim decor: red spires, bone-white ribs, glowing ground cracks (also used in the Lava Heart).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local SPIRE_TIERS = {
	{ d = 4.6, h = 4.5, color = "#C23B2D" },
	{ d = 3.3, h = 3.8, color = "#D9503A" },
	{ d = 2.0, h = 3.2, color = "#EE6A45" },
}

local R: { [string]: Builder } = {}

function R.spire(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local y = 0
	for i, tier in SPIRE_TIERS do
		local h = tier.h * s
		U.cylinder(parent, "Spire", V(it.x, y + h / 2, it.z), tier.d * s, h, tier.color, {
			material = Enum.Material.Basalt,
			collide = i <= 2,
			shadow = true,
		})
		y += h
	end
	U.ball(parent, "SpireTip", V(it.x, y + 0.3 * s, it.z), 1.4 * s, P.bone)
end

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

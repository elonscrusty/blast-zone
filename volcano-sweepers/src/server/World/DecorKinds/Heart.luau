--!strict
-- Lava Heart decor: obsidian shards and floating embers (particles). The lava pools are the picked
-- landmark (DecorKinds/Models): DECOR ONLY, no scripts, no Touched events, no damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local V = Vector3.new

local H: { [string]: Builder } = {}

function H.shard(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	U.block(
		parent,
		"ObsidianShard",
		CFrame.new(it.x, 1.4 * s, it.z)
			* CFrame.Angles(0, it.rot, 0)
			* CFrame.Angles(math.rad(8), 0, math.rad(-6)),
		V(0.9 * s, 3.2 * s, 0.9 * s),
		"#3A2A48",
		{ reflectance = 0.25, shadow = true }
	)
end

function H.ember(parent: Instance, it: WorldPlan.Item)
	local anchor = U.emitterAnchor(parent, "EmberDrift", CFrame.new(it.x, 6, it.z), V(3, 1, 3))
	U.emitter(anchor, {
		colorA = "#FFC24D",
		colorB = "#FF5A2A",
		rate = 5,
		lifeMin = 6,
		lifeMax = 9,
		speedMin = 1,
		speedMax = 3,
		sizeA = 0.5,
		sizeB = 0.2,
		spread = 180,
		accel = V(0, 1.2, 0),
		light = 1,
		alpha = 0.2,
	})
end

return H

--!strict
-- Lava Heart decor. Everything here is DECOR ONLY: lava pools are glowing discs with no scripts,
-- no Touched events and no damage. Floating embers are particles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local H: { [string]: Builder } = {}

function H.lavapool(parent: Instance, it: WorldPlan.Item)
	local radius = 5 * it.scale
	U.disc(parent, "LavaBank", it.x, 0.14, it.z, radius + 1, 0.14, "#1B1219")
	local lava = U.disc(parent, "LavaPool", it.x, 0.22, it.z, radius, 0.1, P.orange, {
		material = Enum.Material.Neon,
	})
	U.ball(
		parent,
		"LavaBubble",
		V(it.x + radius * 0.3, 0.35, it.z - radius * 0.2),
		0.7 * it.scale,
		P.ember,
		{
			material = Enum.Material.Neon,
		}
	)
	if it.v % 2 == 0 then
		U.emitter(lava, {
			colorA = "#FFC24D",
			colorB = "#FF4A1F",
			rate = 3,
			lifeMin = 1.5,
			lifeMax = 2.5,
			speedMin = 5,
			speedMax = 9,
			sizeA = 0.45,
			sizeB = 0.1,
			spread = 20,
			accel = V(0, -7, 0),
			light = 1,
			alpha = 0,
			direction = Enum.NormalId.Right, -- flat discs are rotated: +X faces up
		})
	end
end

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

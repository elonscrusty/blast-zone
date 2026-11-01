--!strict
-- Hot Springs decor: steaming blue pools with glowing rims, pink rocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local PINK = { "#FF9EC7", "#FF7AB8", "#F7B6D8" }

local S: { [string]: Builder } = {}

function S.pool(parent: Instance, it: WorldPlan.Item)
	local radius = 5.5 * it.scale
	local rimColor = if it.v % 2 == 0 then P.cyan else P.pink
	U.disc(
		parent,
		"PoolRim",
		it.x,
		0.1,
		it.z,
		radius + 0.7,
		0.12,
		rimColor,
		{ material = Enum.Material.Neon }
	)
	local water = U.disc(
		parent,
		"PoolWater",
		it.x,
		0.16,
		it.z,
		radius,
		0.1,
		"#45C8F5",
		{ transparency = 0.2 }
	)
	U.emitter(water, {
		colorA = "#FFFFFF",
		colorB = "#DFF6FF",
		rate = 5,
		lifeMin = 3,
		lifeMax = 4.5,
		speedMin = 2.5,
		speedMax = 4,
		sizeA = 2.5,
		sizeB = 6,
		spread = 12,
		accel = V(0, 0.6, 0),
		alpha = 0.55,
		texture = U.SMOKE_TEXTURE,
		direction = Enum.NormalId.Right, -- flat discs are rotated: +X faces up
	})
end

function S.pinkrock(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local color = PINK[it.v % #PINK + 1]
	local d = 2.4 * s
	U.ball(parent, "PinkRock", V(it.x, d * 0.35, it.z), d, color, { collide = true, shadow = true })
	local off = V(math.cos(it.rot), 0, math.sin(it.rot)) * (1.3 * s)
	local d2 = 1.4 * s
	U.ball(parent, "PinkRock", V(it.x, d2 * 0.35, it.z) + off, d2, PINK[(it.v + 1) % #PINK + 1])
end

return S

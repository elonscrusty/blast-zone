--!strict
-- The cartoon volcano: stacked tapering cylinders, a glowing crater, lava streaks down the sides,
-- smoke and embers. One tall invisible cylinder (the zone 5 inner radius) stops players walking
-- onto or into the cone. Lava here is DECOR ONLY: no scripts, no touch, never hurts anyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)
local WorldUtil = require(script.Parent.WorldUtil)

local Volcano = {}

export type Refs = {
	lava: BasePart,
	glow: BasePart,
	light: PointLight,
	bubbles: { BasePart },
}

local P = WorldUtil.Palette

function Volcano.build(root: Instance, plan: WorldPlan.Plan): Refs
	local v = plan.volcano
	local k = v.scale -- 1 = the first, small island's volcano
	local folder = Instance.new("Folder")
	folder.Name = "Volcano"

	-- the cone, from the base up
	for i, tier in v.tiers do
		WorldUtil.cylinder(
			folder,
			`Tier{i}`,
			Vector3.new(0, tier.y + tier.h / 2, 0),
			tier.r * 2,
			tier.h,
			tier.color,
			{ material = Enum.Material.Basalt, shadow = true }
		)
	end

	-- lava streaks running down the steps (thin glowing slabs hugging each tier's side)
	for _, s in v.streaks do
		local tier = v.tiers[s.tier]
		if tier ~= nil then
			local dir = Vector3.new(math.cos(s.angle), 0, math.sin(s.angle))
			local pos = dir * (tier.r + 0.12) + Vector3.new(0, tier.y + tier.h / 2, 0)
			WorldUtil.block(
				folder,
				"LavaStreak",
				CFrame.lookAt(pos, pos + dir),
				Vector3.new(1.3 * k, tier.h - 0.4, 0.4),
				P.lava,
				{ material = Enum.Material.Neon }
			)
		end
	end

	-- crater rim, lava lake, hot centre
	WorldUtil.cylinder(
		folder,
		"CraterRim",
		Vector3.new(0, v.rimY + v.rimH / 2, 0),
		v.rimR * 2,
		v.rimH,
		"#4A2E34",
		{ material = Enum.Material.Basalt, shadow = true }
	)
	local lava = WorldUtil.disc(folder, "CraterLava", 0, v.topY + 0.1, 0, v.lavaR, 0.5, P.orange, {
		material = Enum.Material.Neon,
	})
	local glow =
		WorldUtil.disc(folder, "CraterGlow", 0, v.topY + 0.35, 0, v.lavaR * 0.55, 0.2, P.ember, {
			material = Enum.Material.Neon,
		})
	local bubbles: { BasePart } = {}
	local spots = { Vector3.new(4, 0, 2), Vector3.new(-3, 0, 4), Vector3.new(-1, 0, -5) }
	for i, off in spots do
		table.insert(
			bubbles,
			WorldUtil.ball(
				folder,
				`LavaBubble{i}`,
				off * k + Vector3.new(0, v.topY + 0.5, 0),
				(2 + i * 0.4) * k,
				P.ember,
				{
					material = Enum.Material.Neon,
				}
			)
		)
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(P.orange)
	light.Brightness = 3
	light.Range = 60 -- the most a PointLight reaches
	light.Shadows = false
	light.Parent = glow

	-- smoke plume and fountain of embers (no textures needed for embers; smoke uses the built-in puff)
	local smoke = WorldUtil.emitterAnchor(
		folder,
		"CraterSmoke",
		CFrame.new(0, v.topY + 3, 0),
		Vector3.new(v.lavaR, 1, v.lavaR)
	)
	WorldUtil.emitter(smoke, {
		colorA = "#8A7B84",
		colorB = "#3C333A",
		rate = 9,
		lifeMin = 7,
		lifeMax = 10,
		speedMin = 5,
		speedMax = 9,
		sizeA = 9 * k,
		sizeB = 24 * k,
		spread = 14,
		accel = Vector3.new(1.2, 0.8, 0),
		alpha = 0.45,
		texture = WorldUtil.SMOKE_TEXTURE,
	})
	WorldUtil.emitter(lava, {
		colorA = "#FFC24D",
		colorB = "#FF4A1F",
		rate = 12,
		lifeMin = 2.5,
		lifeMax = 4,
		speedMin = 14,
		speedMax = 26,
		sizeA = 0.8,
		sizeB = 0.2,
		spread = 28,
		accel = Vector3.new(0, -14, 0),
		light = 1,
		alpha = 0,
		direction = Enum.NormalId.Right, -- the lava disc is rotated: its +X face looks up
	})

	-- solid core: nobody walks into the volcano (radius = zone 5 inner edge)
	local coreH = math.max(90, v.topY + 10)
	WorldUtil.cylinder(
		folder,
		"ConeCollision",
		Vector3.new(0, coreH / 2, 0),
		(v.baseRadius - 0.2) * 2,
		coreH,
		"#FFFFFF",
		{ collide = true, transparency = 1 }
	)

	folder.Parent = root
	return { lava = lava, glow = glow, light = light, bubbles = bubbles }
end

return Volcano

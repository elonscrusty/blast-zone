--!strict
-- Fern Forest decor: big wedge ferns, spotted mushrooms, thick tree trunks, glowing fireflies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local FERN = { "#4FB04A", "#6FD35E", "#3E9B46" }
local CAPS = { "#F0463C", "#B06CFF", "#FF9A3C", "#5BE6D0" }
local CANOPY = { "#3FAE49", "#52C75A" }
local FLY = { "#E8FF6A", "#B6FF6A", "#FFF38A" }

local F: { [string]: Builder } = {}

function F.fern(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local pitch = math.rad(38)
	local length = 5 * s
	for j = 0, 4 do
		local phi = it.rot + j * (2 * math.pi / 5)
		local dir =
			V(math.cos(phi) * math.cos(pitch), math.sin(pitch), math.sin(phi) * math.cos(pitch))
		local centre = V(it.x, 0.5, it.z) + dir * (length / 2)
		-- a thin wedge rolled flat: wide at the plant, pointed at the tip
		U.wedge(
			parent,
			"FernFrond",
			CFrame.lookAt(centre, centre + dir) * CFrame.Angles(0, 0, math.pi / 2),
			V(0.18, 1.7 * s, length),
			FERN[(it.v + j) % #FERN + 1]
		)
	end
end

function F.mushroom(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local capColor = CAPS[it.v % #CAPS + 1]
	local glow = it.v % 4 == 3
	U.cylinder(parent, "MushroomStem", V(it.x, 0.8 * s, it.z), 0.7 * s, 1.6 * s, "#FFF4E0")
	local capCentre = V(it.x, 1.45 * s, it.z)
	U.ball(parent, "MushroomCap", capCentre, 2.4 * s, capColor, {
		material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic,
	})
	for j = 0, 2 do
		local ang = it.rot + j * 2.1
		local dir = V(math.cos(ang) * 0.55, 0.85, math.sin(ang) * 0.55).Unit
		U.ball(parent, "MushroomSpot", capCentre + dir * (1.2 * s), 0.42 * s, P.white)
	end
end

function F.trunk(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local height = 13 * s
	U.cylinder(parent, "TreeTrunk", V(it.x, height / 2, it.z), 3.2 * s, height, P.woodDark, {
		material = Enum.Material.Wood,
		collide = true,
		shadow = true,
	})
	U.ball(
		parent,
		"TreeCanopy",
		V(it.x, height + 1.5 * s, it.z),
		10 * s,
		CANOPY[it.v % 2 + 1],
		{ shadow = true }
	)
	U.ball(
		parent,
		"TreeCanopy",
		V(it.x + 3 * s * math.cos(it.rot), height - 0.5 * s, it.z + 3 * s * math.sin(it.rot)),
		7 * s,
		CANOPY[(it.v + 1) % 2 + 1]
	)
	U.ball(parent, "TreeLantern", V(it.x + 1.8 * s, height - 2.5 * s, it.z), 0.9, "#FFF38A", {
		material = Enum.Material.Neon,
	})
end

function F.firefly(parent: Instance, it: WorldPlan.Item)
	U.ball(parent, "Firefly", V(it.x, 1.5 + (it.v % 70) / 10, it.z), 0.32, FLY[it.v % #FLY + 1], {
		material = Enum.Material.Neon,
	})
end

return F

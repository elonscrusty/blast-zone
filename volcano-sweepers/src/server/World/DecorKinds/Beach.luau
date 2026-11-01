--!strict
-- Sunny Beach decor: palms, umbrellas, rocks, crabs, shells. Palm trunks and rocks are solid,
-- everything else is walk-through.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local LEAVES = { "#3DBB5C", "#2FA34E", "#55CC66" }
local UMBRELLA = { "#FF5E5E", "#3EC1FF", "#FFD23F", "#7CE069" }
local TOWEL = { "#FFFFFF", "#FF9AD5", "#7FF3FF" }
local ROCK = { "#A7A29A", "#C2B8A3", "#8F9AA3" }
local SHELL = { "#FFB7C5", "#FFF0DB", "#FFD1A1" }

local B: { [string]: Builder } = {}

function B.palm(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local base = V(it.x, 0, it.z)
	local lean = V(math.cos(it.rot), 0, math.sin(it.rot))
	local pts: { Vector3 } = {}
	for k = 0, 3 do
		table.insert(pts, base + lean * (0.35 * k * k * s) + V(0, 3.1 * k * s, 0))
	end
	for k = 1, 3 do
		U.pole(parent, "PalmTrunk", pts[k], pts[k + 1], (1.5 - 0.2 * k) * s, "#B07A4A", {
			material = Enum.Material.Wood,
			collide = k == 1,
			shadow = true,
		})
	end
	local top = pts[4]
	for j = 0, 6 do
		local phi = it.rot + j * (2 * math.pi / 7)
		local dir = V(math.cos(phi) * 0.9, -0.3, math.sin(phi) * 0.9)
		local centre = top + dir.Unit * (3.2 * s)
		local roll = if j % 2 == 0 then math.rad(22) else math.rad(-22)
		U.block(
			parent,
			"PalmLeaf",
			CFrame.lookAt(centre, centre + dir) * CFrame.Angles(0, 0, roll),
			V(1.8 * s, 0.18, 6.4 * s),
			LEAVES[j % 3 + 1],
			{ shadow = true }
		)
	end
	U.ball(parent, "Coconut", top + V(0.5 * s, -0.7 * s, 0.2 * s), 0.8 * s, "#6B4423")
	U.ball(parent, "Coconut", top + V(-0.4 * s, -0.8 * s, -0.3 * s), 0.8 * s, "#6B4423")
end

function B.umbrella(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local color = UMBRELLA[it.v % #UMBRELLA + 1]
	U.cylinder(parent, "UmbrellaPole", V(it.x, 2.4 * s, it.z), 0.25, 4.8 * s, P.white)
	U.cylinder(
		parent,
		"UmbrellaTop",
		V(it.x, 4.95 * s, it.z),
		6.2 * s,
		0.35,
		color,
		{ shadow = true }
	)
	U.cylinder(parent, "UmbrellaCap", V(it.x, 5.2 * s, it.z), 3.4 * s, 0.3, P.white)
	U.ball(parent, "UmbrellaTip", V(it.x, 5.5 * s, it.z), 0.5, P.gold)
	local side = V(-math.sin(it.rot), 0, math.cos(it.rot))
	U.block(
		parent,
		"Towel",
		CFrame.new(V(it.x, 0.06, it.z) + side * (3.6 * s)) * CFrame.Angles(0, it.rot, 0),
		V(2.2 * s, 0.1, 4.4 * s),
		TOWEL[it.v % #TOWEL + 1]
	)
end

function B.rock(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local color = ROCK[it.v % #ROCK + 1]
	local d = 2.2 * s
	U.ball(parent, "Rock", V(it.x, d * 0.35, it.z), d, color, { collide = true, shadow = true })
	local off = V(math.cos(it.rot), 0, math.sin(it.rot)) * (1.2 * s)
	local d2 = 1.3 * s
	U.ball(parent, "Rock", V(it.x, d2 * 0.35, it.z) + off, d2, color)
end

function B.crab(parent: Instance, it: WorldPlan.Item)
	local s = it.scale
	local fwd = V(math.cos(it.rot), 0, math.sin(it.rot))
	local side = V(-fwd.Z, 0, fwd.X)
	local body = V(it.x, 0.4 * s, it.z)
	U.ball(parent, "Crab", body, 0.9 * s, "#FF4B3E")
	U.ball(parent, "CrabClaw", body + fwd * (0.55 * s) + side * (0.6 * s), 0.42 * s, "#FF6B5E")
	U.ball(parent, "CrabClaw", body + fwd * (0.55 * s) - side * (0.6 * s), 0.42 * s, "#FF6B5E")
end

function B.shell(parent: Instance, it: WorldPlan.Item)
	U.disc(parent, "Shell", it.x, 0.22, it.z, 0.45 * it.scale, 0.22, SHELL[it.v % #SHELL + 1])
end

return B

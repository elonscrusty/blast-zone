--!strict
-- Sunny Beach decor: umbrellas, crabs, shells (all walk-through). Palms, rocks and camps are the
-- picked Toy Pop models (DecorKinds/Models).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local P = U.Palette
local V = Vector3.new

local UMBRELLA = { "#FF5E5E", "#3EC1FF", "#FFD23F", "#7CE069" }
local TOWEL = { "#FFFFFF", "#FF9AD5", "#7FF3FF" }
local SHELL = { "#FFB7C5", "#FFF0DB", "#FFD1A1" }

local B: { [string]: Builder } = {}

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

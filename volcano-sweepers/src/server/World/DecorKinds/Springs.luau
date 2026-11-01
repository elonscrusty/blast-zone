--!strict
-- Hot Springs decor: pink rocks. The steaming pools are the picked hot spring landmark
-- (DecorKinds/Models).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local U = require(script.Parent.Parent.WorldUtil)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local V = Vector3.new

local PINK = { "#FF9EC7", "#FF7AB8", "#F7B6D8" }

local S: { [string]: Builder } = {}

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

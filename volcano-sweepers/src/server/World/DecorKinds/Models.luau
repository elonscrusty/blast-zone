--!strict
-- Decor drawn with carter's picked models (Models/Wiring.decor): Toy Pop palms, rocks, mushrooms,
-- spires and camps, and the look A landmarks for the hot spring pools and the lava pools. Lava and
-- water are decor only (no scripts, no touch). Small props are walk-through; palms, rocks, spires,
-- spring basins and lava pool stones keep the few solid parts their model marks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldPlan = require(Shared.WorldPlan)

local Build = require(script.Parent.Parent.Models.Build)
local Landmarks = require(script.Parent.Parent.Models.Landmarks)
local Wiring = require(script.Parent.Parent.Models.Wiring)

export type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local M: { [string]: Builder } = {}

local function place(it: WorldPlan.Item): CFrame
	return CFrame.new(it.x, Config.World.groundY, it.z) * CFrame.Angles(0, it.rot, 0)
end

for kind, d in Wiring.decor do
	if d.landmark then
		M[kind] = function(parent: Instance, it: WorldPlan.Item)
			Landmarks.build(d.name, parent, place(it), {
				variant = Wiring.LOOK,
				scale = Wiring.decorScale(kind, it.scale),
			})
		end
	else
		M[kind] = function(parent: Instance, it: WorldPlan.Item)
			local spec = Wiring.kitSpec(d.name, it.v)
			Build.into(parent, spec, place(it), Wiring.decorScale(kind, it.scale), d.solid)
		end
	end
end

return M

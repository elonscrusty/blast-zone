--!strict
-- Builds the scenery listed in WorldPlan.decor, a few hundred parts at a time with a task.wait()
-- between chunks so the server never stalls. Each chunk is assembled in a loose Folder and
-- attached to its zone folder in one go (one replication burst instead of hundreds). One bad item
-- never stops the rest: every builder runs under pcall and the first error per kind is logged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldPlan = require(Shared.WorldPlan)

local WorldUtil = require(script.Parent.WorldUtil)
local Beach = require(script.Parent.DecorKinds.Beach)
local Forest = require(script.Parent.DecorKinds.Forest)
local Heart = require(script.Parent.DecorKinds.Heart)
local Rim = require(script.Parent.DecorKinds.Rim)
local Springs = require(script.Parent.DecorKinds.Springs)

local Decor = {}

type Builder = (parent: Instance, it: WorldPlan.Item) -> ()

local CHUNK_PARTS = 150

local builders: { [string]: Builder } = {}
for _, module in { Beach, Forest, Springs, Rim, Heart } do
	for kind, fn in module do
		builders[kind] = fn
	end
end

local function buildVents(parent: Instance, plan: WorldPlan.Plan)
	local folder = Instance.new("Folder")
	folder.Name = "Vents"
	for i, v in plan.vents do
		local vent = Instance.new("Folder")
		vent.Name = `Vent{i}`
		WorldUtil.cylinder(
			vent,
			"VentBase",
			Vector3.new(v.x, 0.2, v.z),
			5,
			0.4,
			"#5A4A52",
			{ material = Enum.Material.Basalt }
		)
		local glow =
			WorldUtil.disc(vent, "VentGlow", v.x, 0.46, v.z, 1.6, 0.1, WorldUtil.Palette.cyan, {
				material = Enum.Material.Neon,
			})
		WorldUtil.emitter(glow, {
			colorA = "#FFFFFF",
			colorB = "#BFEFFF",
			rate = 4,
			lifeMin = 2.5,
			lifeMax = 3.5,
			speedMin = 3,
			speedMax = 5,
			sizeA = 1.5,
			sizeB = 4,
			spread = 10,
			alpha = 0.5,
			texture = WorldUtil.SMOKE_TEXTURE,
			direction = Enum.NormalId.Right, -- flat discs are rotated: +X faces up
		})
		vent.Parent = folder
	end
	folder.Parent = parent
end

-- `alive()` turns false when the world was rebuilt or destroyed: stop quietly.
function Decor.build(root: Instance, plan: WorldPlan.Plan, alive: () -> boolean)
	local zoneFolders: { [number]: Folder } = {}
	for _, z in Config.World.zones do
		local folder = Instance.new("Folder")
		folder.Name = `Decor{z.id}`
		folder.Parent = root
		zoneFolders[z.id] = folder
	end

	local batch = Instance.new("Folder")
	batch.Name = "Batch"
	local pending = 0
	local current = 1
	local failed: { [string]: boolean } = {}

	local function flush()
		local target = zoneFolders[current]
		if target ~= nil then
			batch.Parent = target
		else
			batch:Destroy()
		end
		batch = Instance.new("Folder")
		batch.Name = "Batch"
		pending = 0
	end

	for _, it in plan.decor do
		if it.zone ~= current then
			flush()
			current = it.zone
		end
		local build = builders[it.kind]
		if build ~= nil then
			local ok, err = pcall(build, batch, it)
			if not ok and not failed[it.kind] then
				failed[it.kind] = true
				warn(`[World] decor '{it.kind}' failed: {err}`)
			end
			pending += WorldPlan.partCost[it.kind] or 1
		end
		if pending >= CHUNK_PARTS then
			flush()
			task.wait()
			if not alive() then
				return
			end
		end
	end
	flush()

	if alive() then
		local ok, err = pcall(buildVents, root, plan)
		if not ok then
			warn(`[World] vents failed: {err}`)
		end
	end
end

return Decor

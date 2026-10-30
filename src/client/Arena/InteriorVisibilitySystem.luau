--!strict
-- Local roof and wall fading (brief section 8). Reads the parts the server tagged with
-- Config.Arena.occluderTag and sets LocalTransparencyModifier, which only this client sees and
-- which never changes collision. Other participants standing in a room you are not in are
-- hidden the same way, so a faded wall cannot show you someone behind it.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Visibility = require("./Visibility")

local InteriorVisibilitySystem = {}

type Record = { part: BasePart, box: Visibility.Box, current: number }

local records: { [string]: Record } = {}
local boxes: { Visibility.Box } = {}
local buildings: { Visibility.Footprint } = {}
local targets: { [string]: number } = {}
local hiddenModels: { [Model]: boolean } = {}
local attr = Config.Attributes.ParticipantId

local function add(inst: Instance)
	if not inst:IsA("BasePart") or records[inst.Name] then
		return
	end
	local kind = inst:GetAttribute("OccluderKind")
	if typeof(kind) ~= "string" then
		return
	end
	local b = inst:GetAttribute("Building")
	local building = if typeof(b) == "string" then b else nil
	local p, s = inst.Position, inst.Size
	local box: Visibility.Box = {
		id = inst.Name,
		kind = kind,
		building = building,
		x0 = p.X - s.X / 2,
		y0 = p.Y - s.Y / 2,
		z0 = p.Z - s.Z / 2,
		x1 = p.X + s.X / 2,
		y1 = p.Y + s.Y / 2,
		z1 = p.Z + s.Z / 2,
	}
	records[inst.Name] = { part = inst, box = box, current = 0 }
	table.insert(boxes, box)
	if kind == "roof" and building then
		table.insert(
			buildings,
			{ id = building, x0 = box.x0, z0 = box.z0, x1 = box.x1, z1 = box.z1 }
		)
	end
end

local function reset()
	records, boxes, buildings = {}, {}, {}
	for model in hiddenModels do
		hiddenModels[model] = nil
	end
end

local function setModelHidden(model: Model, hidden: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local scanClock = 0

-- Participant characters are Models with a ParticipantId attribute (players and bots alike).
local function updateOccupants(inside: string?, myId: unknown)
	for _, m in Workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute(attr) ~= nil and m:GetAttribute(attr) ~= myId then
			local root = m:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local pos = root.Position
				local hide = Visibility.hidesOccupant(buildings, inside, pos.X, pos.Z)
				if hide ~= (hiddenModels[m] == true) then
					hiddenModels[m] = if hide then true else nil
					setModelHidden(m, hide)
				elseif hide then
					setModelHidden(m, true) -- catch accessories that arrived late
				end
			end
		end
	end
	for model in hiddenModels do
		if not model:IsDescendantOf(Workspace) then
			hiddenModels[model] = nil
		end
	end
end

function InteriorVisibilitySystem.start()
	if not Config.Features.roofFade then
		return
	end
	local fade = Config.Arena.fade
	local tag = Config.Arena.occluderTag
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		if records[inst.Name] then
			-- rare (arena rebuilt): drop everything and let the new parts re-register
			reset()
			for _, other in CollectionService:GetTagged(tag) do
				add(other)
			end
		end
	end)

	local localPlayer = Players.LocalPlayer
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera or #boxes == 0 then
			return
		end
		-- Follow the camera's focus, so it also works while spectating.
		local focus = camera.Focus.Position
		local cam = camera.CFrame.Position
		local inside = Visibility.compute(
			boxes,
			buildings,
			focus.X,
			focus.Z,
			cam.X,
			cam.Y,
			cam.Z,
			fade,
			targets
		)

		local k = 1 - math.exp(-fade.smoothing * dt)
		for id, rec in records do
			local target = targets[id] or 0
			if math.abs(target - rec.current) > 0.002 then
				rec.current += (target - rec.current) * k
				rec.part.LocalTransparencyModifier = rec.current
			end
		end

		scanClock += dt
		if scanClock >= 0.15 then
			scanClock = 0
			local char = localPlayer.Character
			updateOccupants(inside, if char then char:GetAttribute(attr) else nil)
		end
	end)
end

return InteriorVisibilitySystem

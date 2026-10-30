--!strict
-- Draws the night traffic (piece SL). The server says which road stretches have cars; this builds a
-- few glowing hover-cars and moves them. Looks only: the cars have no collision, cannot be hit or
-- aimed at, and thin out around you so one never hides who you are fighting. Cars brake when a shot
-- goes off near their road. Placeholder look: the city art thread can restyle it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TrafficPlan = require(Shared.Traffic.TrafficPlan)
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)

local TrafficClientSystem = {}
TrafficClientSystem.order = 300

local cfg = Config.Traffic

type Live = {
	model: Model,
	parts: { BasePart },
	car: TrafficPlan.Car,
	shown: number, -- last alpha written, so quiet cars cost nothing
}

local segments: { TrafficPlan.Segment } = {}
local live: { Live } = {}
local lastShot: { [number]: number } = {} -- segment index -> os.clock() of the last shot near it
local folder: Folder? = nil
local stateKey = "" -- matchId:seed of the cars drawn now, so a repeat of the same state changes nothing

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function block(
	model: Model,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	neon: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

-- Built facing -Z (the front of a Roblox model); moved with PivotTo.
local function makeCar(glow: Color3): (Model, { BasePart })
	local m = Instance.new("Model")
	m.Name = "NightCar"
	local parts: { BasePart } = {
		block(
			m,
			"Body",
			Vector3.new(5, 1.4, 10),
			Vector3.new(0, 0.7, 0),
			Color3.fromHex(cfg.bodyColor),
			false
		),
		block(
			m,
			"Cab",
			Vector3.new(4, 1.1, 5),
			Vector3.new(0, 1.95, 0.6),
			Color3.fromHex(cfg.cabColor),
			false
		),
		block(m, "Glow", Vector3.new(5.2, 0.3, 10.2), Vector3.new(0, 0.1, 0), glow, true),
		block(
			m,
			"Lights",
			Vector3.new(3.6, 0.4, 0.2),
			Vector3.new(0, 0.9, -5.05),
			Color3.fromHex(cfg.lightColor),
			true
		),
		block(
			m,
			"Tail",
			Vector3.new(3.6, 0.4, 0.2),
			Vector3.new(0, 0.9, 5.05),
			Color3.fromHex(cfg.tailColor),
			true
		),
	}
	m.PrimaryPart = parts[1]
	return m, parts
end

local function clearCars()
	if folder ~= nil then
		folder:Destroy()
	end
	folder = nil
	table.clear(live)
	table.clear(lastShot)
	segments = {}
	stateKey = ""
end

local function onState(state: Types.TrafficState)
	local key = `{state.matchId}:{state.seed}:{#state.segments}`
	if key == stateKey then
		return
	end
	clearCars()
	if #state.segments == 0 then
		return
	end
	stateKey = key
	segments = state.segments
	local f = Instance.new("Folder")
	f.Name = "NightTraffic"
	f.Parent = workspace
	folder = f
	local limit = if isPhone() then cfg.phoneMaxCars else cfg.maxCars
	for _, car in TrafficPlan.populate(segments, state.seed, limit) do
		local model, parts = makeCar(Color3.fromHex(cfg.colors[car.color]))
		model.Parent = f
		table.insert(live, { model = model, parts = parts, car = car, shown = -1 })
	end
end

local function setAlpha(entry: Live, alpha: number)
	if math.abs(alpha - entry.shown) < 0.02 then
		return
	end
	entry.shown = alpha
	for _, p in entry.parts do
		p.LocalTransparencyModifier = 1 - alpha
	end
end

local function focus(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function TrafficClientSystem.start()
	Net.on("TrafficState", onState)
	Net.send("TrafficRequest") -- we may have joined mid-match

	Net.on("ShotFx", function(s: any)
		if #segments == 0 or typeof(s.origin) ~= "Vector3" then
			return
		end
		local now = os.clock()
		for i, seg in segments do
			if TrafficPlan.distanceTo(seg, s.origin.X, s.origin.Z) <= cfg.slowRadius then
				lastShot[i] = now
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		if #live == 0 then
			return
		end
		local now = os.clock()
		local me = focus()
		for _, entry in live do
			local car = entry.car
			local seg = segments[car.seg]
			local since = if lastShot[car.seg] ~= nil then now - lastShot[car.seg] else nil
			local length = TrafficPlan.length(seg)
			car.dist =
				TrafficPlan.advance(car.dist, length, car.speed, TrafficPlan.speedFactor(since), dt)
			local x, z, dx, dz = TrafficPlan.pose(seg, car.dist)
			local pos = Vector3.new(x, TrafficPlan.height(seg), z)
			entry.model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(dx, 0, dz)))
			local alpha = TrafficPlan.endAlpha(car.dist, length)
			if me ~= nil then
				local away = math.sqrt((me.X - x) ^ 2 + (me.Z - z) ^ 2)
				alpha = math.min(alpha, TrafficPlan.nearAlpha(away))
			end
			setAlpha(entry, alpha)
		end
	end)
end

return TrafficClientSystem

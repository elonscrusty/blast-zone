--!strict
-- Draws the rain the server picked (piece 38). One invisible part follows the camera and carries
-- one ParticleEmitter, so the cost is a single emitter at a capped rate (half on phones). The haze
-- is the sky Atmosphere nudged up while it rains. Placeholder look: the city art thread can restyle.
-- Looks only; weather never changes shots, damage or the zone.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local WeatherPlan = require(Shared.Weather.WeatherPlan)

local Net = require(script.Parent.Parent.Core.Net)

local WeatherClientSystem = {}
WeatherClientSystem.order = 300

local cfg = Config.Weather

local level: string = WeatherPlan.CLEAR
local shownLevel: string = WeatherPlan.CLEAR -- the last rain level, kept while the rain fades out
local changedAt = 0 -- os.clock() when the level last changed
local fromAmount = 0 -- rain amount at that moment, so a change fades from where it was
local amountNow = 0

local sheet: Part? = nil
local emitter: ParticleEmitter? = nil
local baseDensity: number? = nil
local baseHaze: number? = nil

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function ensureSheet(): ParticleEmitter
	if emitter ~= nil and sheet ~= nil and sheet.Parent ~= nil then
		return emitter
	end
	local part = Instance.new("Part")
	part.Name = "RainSheet"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(cfg.coverStuds, 1, cfg.coverStuds)

	local e = Instance.new("ParticleEmitter")
	e.Name = "Rain"
	e.Color = ColorSequence.new(Color3.fromHex(cfg.dropColor))
	e.LightEmission = 0.6
	e.Transparency = NumberSequence.new(0.35)
	e.Size = NumberSequence.new(0.25)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-2) -- long thin streaks
	e.Lifetime = NumberRange.new(cfg.dropSeconds * 0.9, cfg.dropSeconds)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.SpreadAngle = Vector2.new(2, 2)
	e.Acceleration = Vector3.zero
	e.LockedToPart = false
	e.Rate = 0
	e.Enabled = false
	e.Parent = part

	part.Parent = workspace
	sheet = part
	emitter = e
	return e
end

local function dropSheet()
	if sheet ~= nil then
		sheet:Destroy()
	end
	sheet = nil
	emitter = nil
end

local function atmosphere(): Atmosphere?
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if a ~= nil then
		return a
	end
	if not cfg.applyAtmosphere then
		return nil
	end
	local made = Instance.new("Atmosphere")
	made.Density = 0.3
	made.Haze = 0
	made.Parent = Lighting
	return made
end

local function setHaze(fogAdd: number, hazeAdd: number)
	Lighting:SetAttribute(cfg.attributes.fog, fogAdd)
	Lighting:SetAttribute(cfg.attributes.haze, hazeAdd)
	if not cfg.applyAtmosphere then
		return
	end
	local a = atmosphere()
	if a == nil then
		return
	end
	if baseDensity == nil or baseHaze == nil then
		baseDensity, baseHaze = a.Density, a.Haze
	end
	a.Density = (baseDensity :: number) + fogAdd
	a.Haze = (baseHaze :: number) + hazeAdd
	if fogAdd == 0 and hazeAdd == 0 then
		baseDensity, baseHaze = nil, nil -- forget the base so a new match reads the day-night value fresh
	end
end

local function onState(state: Types.WeatherState)
	if state.level == level then
		return
	end
	level = state.level
	if WeatherPlan.isLevel(level) then
		shownLevel = level
	end
	fromAmount = amountNow
	changedAt = os.clock()
end

function WeatherClientSystem.start()
	Net.on("WeatherState", onState)
	Net.send("WeatherRequest") -- we may have joined mid-match

	RunService.RenderStepped:Connect(function()
		amountNow = WeatherPlan.amount(level, os.clock() - changedAt, fromAmount)
		if amountNow <= 0.001 and level == WeatherPlan.CLEAR then
			if sheet ~= nil then
				dropSheet()
				setHaze(0, 0)
			end
			return
		end
		local e = ensureSheet()
		local rate = WeatherPlan.dropRate(shownLevel, amountNow, isPhone())
		e.Rate = rate
		e.Enabled = rate > 0
		local look = WeatherPlan.look(shownLevel)
		if look ~= nil then
			e.Speed = NumberRange.new(look.speed * 0.9, look.speed)
		end
		local camera = workspace.CurrentCamera
		if camera ~= nil and sheet ~= nil then
			sheet.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, cfg.heightStuds, 0))
		end
		local fog, haze = WeatherPlan.fogAdd(shownLevel, amountNow)
		setHaze(fog, haze)
	end)
end

return WeatherClientSystem

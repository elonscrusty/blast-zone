--!strict
-- Day to night for the Neon Night city (piece 14), client only. During a match the lighting and
-- the neon glide from day toward night, finishing as sudden death starts (see shared/DayNight).
-- Outside a match the city goes back to daylight. It reads the same ZoneState and MatchState the
-- zone ring uses and never touches gameplay.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DayNight = require(Shared.DayNight)
local MatchPhase = require(Shared.MatchPhase)

local Net = require(script.Parent.Parent.Core.Net)

local DayNightSystem = {}
DayNightSystem.order = 210

type Neon = {
	part: BasePart,
	on: Color3,
	off: Color3,
	litAt: number,
	soft: boolean,
	lit: boolean?, -- last state of a switching window
	light: PointLight?,
	lightBase: number,
}

local function rgb(c: DayNight.Rgb): Color3
	return Color3.fromRGB(math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5))
end

local function find(parent: Instance, name: string, class: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == class then
		return existing
	end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = parent
	return made
end

local function hexColor(v: unknown, fallback: Color3): Color3
	if typeof(v) == "string" then
		return Color3.fromHex(v)
	end
	return fallback
end

function DayNightSystem.start()
	if not Config.Features.dayNight then
		return
	end
	local zone = Config.Zone
	local settings = Config.Art.dayNight
	local weather = Config.Weather.attributes

	local atmosphere = find(Lighting, "NeonAtmosphere", "Atmosphere") :: Atmosphere
	local bloom = find(Lighting, "NeonBloom", "BloomEffect") :: BloomEffect
	local correction = find(Lighting, "NeonColor", "ColorCorrectionEffect") :: ColorCorrectionEffect
	bloom.Size = 24
	bloom.Threshold = 1.1

	-- neon parts, found by tag so late arrivals (streaming) join in
	local neons: { [BasePart]: Neon } = {}
	local list: { Neon } = {}
	local level = -1

	local function register(inst: Instance)
		if not inst:IsA("BasePart") or neons[inst] then
			return
		end
		local light = inst:FindFirstChildOfClass("PointLight")
		local base = inst:GetAttribute("LightBase")
		local n: Neon = {
			part = inst,
			on = hexColor(inst:GetAttribute("NeonOn"), inst.Color),
			off = hexColor(inst:GetAttribute("NeonOff"), inst.Color),
			litAt = tonumber(inst:GetAttribute("NeonLitAt")) or 0,
			soft = inst:GetAttribute("NeonSoft") == true,
			lit = nil,
			light = light,
			lightBase = if typeof(base) == "number" then base else 1,
		}
		neons[inst] = n
		table.insert(list, n)
		level = -1 -- repaint everything once
	end
	local tag = Config.Tags.ArtNeon
	for _, inst in CollectionService:GetTagged(tag) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		local n = neons[inst :: BasePart]
		if n then
			neons[inst :: BasePart] = nil
			local i = table.find(list, n)
			if i then
				table.remove(list, i)
			end
		end
	end)

	local function paint(glow: number, steps: number)
		for _, n in list do
			if n.part.Parent == nil then
				continue
			end
			if n.soft then
				n.part.Color = n.off:Lerp(n.on, DayNight.blend(glow))
				n.part.Material = Enum.Material.Neon
			else
				local lit = DayNight.windowLit(glow, n.litAt)
				if lit ~= n.lit then
					n.lit = lit
					n.part.Color = if lit then n.on else n.off
					n.part.Material = if lit
						then Enum.Material.Neon
						else Enum.Material.SmoothPlastic
				end
			end
			if n.light then
				n.light.Enabled = glow > 0.35
				n.light.Brightness = n.lightBase * glow
			end
		end
		level = DayNight.glowLevel(glow, steps)
	end

	local function applyLook(look: DayNight.Look)
		Lighting.ClockTime = look.clockTime
		Lighting.Brightness = look.brightness
		Lighting.Ambient = rgb(look.ambient)
		Lighting.OutdoorAmbient = rgb(look.outdoorAmbient)
		atmosphere.Color = rgb(look.atmosphereColor)
		atmosphere.Decay = rgb(look.atmosphereDecay)
		-- rain (piece 38) adds fog on top of the day-night value; the weather client only writes these two numbers
		local fogAdd = Lighting:GetAttribute(weather.fog)
		local hazeAdd = Lighting:GetAttribute(weather.haze)
		atmosphere.Density =
			math.clamp(look.density + (if typeof(fogAdd) == "number" then fogAdd else 0), 0, 1)
		atmosphere.Haze =
			math.clamp(look.haze + (if typeof(hazeAdd) == "number" then hazeAdd else 0), 0, 10)
		atmosphere.Glare = look.glare
		bloom.Intensity = look.bloom
		correction.TintColor = rgb(look.tint)
		correction.Saturation = look.saturation
	end

	-- what the server told us about the live match
	local live = false
	local matchId = -1
	local startedMatch = -2
	local matchStart: number? = nil
	Net.on("ZoneState", function(state)
		if state.matchId >= matchId then
			matchStart = DayNight.matchStart(state, zone)
			startedMatch = state.matchId
		end
	end)
	Net.on("MatchState", function(state)
		live = MatchPhase.isCombat(state.phase)
		if state.matchId ~= matchId then
			matchId = state.matchId
			if startedMatch ~= matchId then
				matchStart = nil -- a stale stamp from the match before
			end
		end
	end)
	Net.send("ZoneStateRequest") -- we may have joined mid-match

	local t = settings.lobbyT
	applyLook(DayNight.look(t))
	RunService.RenderStepped:Connect(function(dt: number)
		local now = workspace:GetServerTimeNow()
		local target = DayNight.targetT(live, matchStart, now, zone, settings.lobbyT)
		t = DayNight.follow(t, target, dt, settings.maxChangePerSecond)
		local look = DayNight.look(t)
		applyLook(look)
		-- neon only repaints when the glow moves to a new step (or new parts arrived)
		local step = DayNight.glowLevel(look.glow, settings.glowSteps)
		if step ~= level then
			paint(step / settings.glowSteps, settings.glowSteps)
		end
	end)
end

return DayNightSystem

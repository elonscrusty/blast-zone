--!strict
-- Draws the airdrop the server announced (piece AD): a tall light beam, a falling crate and a ground
-- ring. 3D world art, so it keeps its own colours (tests/ui_tokens lists this file as world art).
-- Nothing here decides anything: when and where come from `AirdropState`; the loot is ordinary pickups
-- the server put out. The look comes from Config.Airdrop.looks[Config.Airdrop.look]. Everything is
-- built from the server's times, so a client that joins late sees the same thing. The hint strip
-- (words, arrow, distance) is AirdropHintSystem; it reads what this file publishes to AirdropClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AirdropRules = require(Shared.Airdrop.AirdropRules)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)
local Fx = require(script.Parent.Parent.Effects.Fx)
local AirdropClient = require(script.Parent.AirdropClient)

local AirdropClientSystem = {}
AirdropClientSystem.order = 320

local cfg = Config.Airdrop

type View = {
	id: string,
	root: Folder,
	pos: Vector3, -- the street where the crate lands
	startedAt: number,
	landsAt: number,
	opensAt: number,
	opened: boolean,
	look: { [string]: any },
	outer: { Part }, -- the beam's wide layer (one part, or the stripes)
	core: Part?,
	ring: Part,
	crate: Model,
	prop: Part?,
	smoke: ParticleEmitter?,
}

local views: { [string]: View } = {}
local folder: Folder? = nil

local function colorOf(hex: string): Color3
	return Color3.fromHex(hex)
end

local function lookDef(id: string?): { [string]: any }
	local looks = cfg.looks
	return looks[id or cfg.look] or looks[cfg.look]
end

local function getFolder(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "AirdropFx"
	made.Parent = Workspace
	folder = made
	return made
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

-- A cylinder that stands up: Roblox cylinders lie along X, so turn a quarter around Z.
local function column(
	parent: Instance,
	name: string,
	at: Vector3,
	height: number,
	diameter: number
): Part
	local p = makePart(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	)
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	return p
end

-- Tells the hint strip what is running (it only reads).
local function publish()
	local list: { AirdropClient.Drop } = {}
	for _, v in views do
		table.insert(
			list,
			{ pos = v.pos, landsAt = v.landsAt, opensAt = v.opensAt, opened = v.opened }
		)
	end
	AirdropClient.set(list)
end

local function destroyView(id: string)
	local v = views[id]
	if v ~= nil then
		views[id] = nil
		v.root:Destroy()
		publish()
	end
end

local function clearAll()
	for id in views do
		destroyView(id)
	end
end

local function build(p: Types.AirdropState): View?
	local pos, startedAt, landsAt, opensAt, id = p.pos, p.startedAt, p.landsAt, p.opensAt, p.dropId
	if pos == nil or startedAt == nil or landsAt == nil or opensAt == nil or id == nil then
		return nil
	end
	local look = lookDef(p.look)
	local height = cfg.beamHeight
	local root = Instance.new("Folder")
	root.Name = id
	root.Parent = getFolder()
	local middle = pos + Vector3.new(0, height / 2, 0)
	local color = colorOf(look.color)

	local outer: { Part } = {}
	local core: Part? = nil
	if look.dashes then
		local step = cfg.dashHeight + cfg.dashGap
		local alt = colorOf(Config.Palette.RewardGold)
		for i = 0, math.floor(height / step) - 1 do
			local dash = column(
				root,
				"Dash",
				pos + Vector3.new(0, 1 + i * step + cfg.dashHeight / 2, 0),
				cfg.dashHeight,
				look.outerDiameter
			)
			dash.Color = if i % 2 == 0 then color else alt
			dash.Transparency = look.outerTransparency
			table.insert(outer, dash)
		end
	else
		local wide = column(root, "Beam", middle, height, look.outerDiameter)
		wide.Color = color
		wide.Transparency = look.outerTransparency
		table.insert(outer, wide)
	end
	local inner = column(root, "BeamCore", middle, height, look.coreDiameter)
	inner.Color = colorOf(look.coreColor)
	inner.Transparency = look.coreTransparency
	core = inner

	local ring = column(root, "Ring", pos + Vector3.new(0, 0.2, 0), 0.3, look.ringDiameter)
	ring.Color = color

	local size = cfg.crateSize
	local crate = Instance.new("Model")
	crate.Name = "AirdropCrate"
	local body = makePart(crate, "Body", Vector3.new(size, size, size), CFrame.new(pos))
	body.Color = colorOf(cfg.crateColor)
	body.Material = Enum.Material.SmoothPlastic
	local band =
		makePart(crate, "Band", Vector3.new(size + 0.2, size * 0.22, size + 0.2), CFrame.new(pos))
	band.Color = colorOf(cfg.bandColor)
	band.Material = Enum.Material.Neon
	crate.PrimaryPart = body
	crate.Parent = root

	local prop: Part? = nil
	local smoke: ParticleEmitter? = nil
	if look.fallProp == "chute" then
		prop = makePart(
			root,
			"Chute",
			Vector3.new(size * 1.9, size * 0.9, size * 1.9),
			CFrame.new(pos)
		)
		prop.Shape = Enum.PartType.Ball
		prop.Material = Enum.Material.SmoothPlastic
		prop.Color = color
	elseif look.fallProp == "flame" then
		prop = makePart(
			root,
			"Flame",
			Vector3.new(size * 0.7, size * 1.5, size * 0.7),
			CFrame.new(pos)
		)
		prop.Shape = Enum.PartType.Ball
		prop.Material = Enum.Material.Neon
		prop.Color = colorOf(look.coreColor)
	elseif look.fallProp == "smoke" then
		local e = Instance.new("ParticleEmitter")
		e.Rate = 30
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(0, 2)
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.5
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 6),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Parent = body
		smoke = e
	end

	return {
		id = id,
		root = root,
		pos = pos,
		startedAt = startedAt,
		landsAt = landsAt,
		opensAt = opensAt,
		opened = false,
		look = look,
		outer = outer,
		core = core,
		ring = ring,
		crate = crate,
		prop = prop,
		smoke = smoke,
	}
end

local function step()
	if next(views) == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local clock = os.clock()
	for id, v in views do
		local strength = AirdropRules.beamStrength(now, v.opensAt, cfg.beamFadeSeconds)
		if v.opened and strength <= 0 then
			destroyView(id)
			continue
		end
		local look = v.look
		-- The beam fades out after the crate opens (and the stripes blink while it waits).
		for i, part in v.outer do
			local base = look.outerTransparency
			if look.dashes and not v.opened then
				local wave = 0.5 + 0.5 * math.sin(clock * cfg.dashBlinkHz * 2 * math.pi - i * 0.7)
				base = base + (1 - base) * 0.6 * (1 - wave)
			end
			part.Transparency = 1 - (1 - base) * strength
		end
		if v.core ~= nil then
			v.core.Transparency = 1 - (1 - look.coreTransparency) * strength
		end
		-- The ground ring spreads out and fades, again and again.
		local k = (clock * 0.8) % 1
		local d = look.ringDiameter * (0.5 + 0.5 * k)
		v.ring.Size = Vector3.new(0.3, d, d)
		v.ring.Transparency = 1 - (1 - (0.25 + 0.75 * k)) * strength

		-- The crate comes down on the server's times; once landed it sits shut.
		if not v.opened then
			local height = AirdropRules.crateHeight(now, v.startedAt, v.landsAt, cfg.startHeight)
			local lift = height + cfg.crateSize / 2
			local sway = if height > 0 then math.sin(clock * 1.6) * 0.25 else 0
			v.crate:PivotTo(CFrame.new(v.pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, sway, 0))
			local falling = height > 0
			if v.prop ~= nil then
				v.prop.Transparency = if falling then 0 else 1
				local offset = if v.prop.Name == "Chute"
					then cfg.crateSize * 2.3
					else -cfg.crateSize * 1.4
				v.prop.CFrame = CFrame.new(v.pos + Vector3.new(0, lift + offset, 0))
				if v.prop.Name == "Flame" then
					local f = 1 + math.sin(clock * 40) * 0.2
					v.prop.Size = Vector3.new(
						cfg.crateSize * 0.7,
						cfg.crateSize * 1.5 * f,
						cfg.crateSize * 0.7
					)
				end
			end
			if v.smoke ~= nil then
				v.smoke.Enabled = falling
			end
		end
	end
end

local function onState(p: any)
	if type(p) ~= "table" or type(p.event) ~= "string" then
		return
	end
	if p.event == "clear" then
		clearAll()
		return
	end
	if type(p.dropId) ~= "string" then
		return
	end
	local state: Types.AirdropState = p
	if p.event == "incoming" then
		if views[p.dropId] ~= nil then
			return
		end
		local opensAt = state.opensAt
		if opensAt == nil or Workspace:GetServerTimeNow() >= opensAt then
			return -- already open: the loot is on the street, nothing to show
		end
		local v = build(state)
		if v ~= nil then
			views[v.id] = v
			publish()
		end
	elseif p.event == "opened" then
		local v = views[p.dropId]
		if v ~= nil and not v.opened then
			v.opened = true
			v.crate:Destroy()
			if v.prop ~= nil then
				v.prop:Destroy()
				v.prop = nil
			end
			Fx.containerBreak(v.pos + Vector3.new(0, cfg.crateSize / 2, 0), "epic")
			publish()
		end
	end
end

function AirdropClientSystem.start()
	if not cfg.enabled then
		return
	end
	Net.on("AirdropState", onState)
	RunService.Heartbeat:Connect(step)
	Net.send("AirdropRequest") -- a client that joined mid-match asks for the drops that are running
end

return AirdropClientSystem

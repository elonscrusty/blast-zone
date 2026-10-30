--!strict
-- Draws the combat HUD in look B from a HudModel.View. Display only: it never decides anything.
-- Small on purpose (carter: "way too cluttered"): health + level, players left + zone timer,
-- one warning line, a minimap and a weapon/ammo panel. Nothing else.
-- Layout numbers live in Layout.luau; piece 08's upgrade cards own the bottom-centre band.

local Players = game:GetService("Players")

local HudModel = require("./HudModel")
local Layout = require("./Layout")
local MinimapMath = require("./MinimapMath")
local UiKit = require("./UiKit")
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local HudView = {}
HudView.__index = HudView

export type Options = {
	minimapRange: number, -- studs from the minimap centre to its rim
	cameraYaw: number, -- degrees, Config.Camera.yawDegrees
	weaponCount: number,
}

export type HudView = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		root: Frame,
		opts: Options,
		-- vitals
		hpFill: Frame,
		hpGhost: Frame,
		hpStroke: UIStroke,
		hpText: TextLabel,
		hpMax: TextLabel,
		levelText: TextLabel,
		xpFill: Frame,
		-- status
		aliveChip: Frame,
		aliveShadow: Frame,
		aliveText: TextLabel,
		zoneChip: Frame,
		zoneShadow: Frame,
		zoneText: TextLabel,
		-- warning
		warnPanel: Frame,
		warnShadow: Frame,
		warnText: TextLabel,
		warnKey: string,
		-- minimap
		safeCircle: Frame,
		zonePointer: TextLabel,
		mapButton: TextButton, -- tap the minimap to open the big map
		-- weapon
		weaponName: TextLabel,
		ammoText: TextLabel,
		magText: TextLabel,
		reloadFill: Frame,
		slotPips: { Frame },
		-- feedback
		edges: { Frame },
		hitArrow: TextLabel,
		hitMarker: TextLabel,
		lastAmmo: number,
		lastHealthFraction: number,
		ghostFraction: number,
		scales: { UIScale },
	},
	HudView
))

local function pieceFrame(root: Frame, name: string, rect: Layout.Rect, scales: { UIScale }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Active = false
	f.Parent = root
	UiKit.place(f, rect)
	-- "HUD size" setting: each piece shrinks toward the screen edge it hugs.
	local scale = Instance.new("UIScale")
	scale.Name = "HudScale"
	scale.Parent = f
	table.insert(scales, scale)
	return f
end

local function edgeFrame(
	parent: Instance,
	anchor: Vector2,
	pos: UDim2,
	size: UDim2,
	rotation: number
): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = UiKit.color(UiKit.look().danger)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new(0.1, 1)
	g.Rotation = rotation
	g.Parent = f
	f.Parent = parent
	return f
end

function HudView.new(opts: Options): HudView
	local look = UiKit.look()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.Hud
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	local scales: { UIScale } = {}

	-- ===== hurt edges (behind everything else) =====
	local edges = {
		edgeFrame(root, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.14), 90),
		edgeFrame(
			root,
			Vector2.new(0.5, 1),
			UDim2.fromScale(0.5, 1),
			UDim2.fromScale(1, 0.14),
			-90
		),
		edgeFrame(root, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.07, 1), 0),
		edgeFrame(
			root,
			Vector2.new(1, 0.5),
			UDim2.fromScale(1, 0.5),
			UDim2.fromScale(0.07, 1),
			180
		),
	}

	-- ===== vitals: health bar and run level =====
	local vitals = pieceFrame(root, "Vitals", Layout.regions.vitals, scales)
	local hpPanel, hpShadow = UiKit.sticker(vitals, root, "Health", look.panel, 0.5)
	hpPanel.Size = UDim2.fromScale(1, 0.58)
	UiKit.followShadow(hpPanel, hpShadow, root)
	local hpClip = Instance.new("CanvasGroup")
	hpClip.Name = "Clip"
	hpClip.BackgroundTransparency = 1
	hpClip.Size = UDim2.fromScale(1, 1)
	hpClip.Parent = hpPanel
	UiKit.round(hpClip, 0.5)
	local hpGhost = Instance.new("Frame")
	hpGhost.Name = "Ghost"
	hpGhost.BackgroundColor3 = UiKit.color(look.panel)
	hpGhost.BorderSizePixel = 0
	hpGhost.Size = UDim2.fromScale(1, 1)
	hpGhost.Parent = hpClip
	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.BackgroundColor3 = UiKit.color(look.danger)
	hpFill.BorderSizePixel = 0
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.Parent = hpClip
	local hpText = UiKit.label(hpPanel, "Health", {
		text = "100",
		size = UDim2.fromScale(0.5, 0.78),
		position = UDim2.fromScale(0.07, 0.5),
		anchor = Vector2.new(0, 0.5),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 30,
	})
	hpText.ZIndex = 3
	local hpMax = UiKit.label(hpPanel, "Max", {
		text = "/100",
		size = UDim2.fromScale(0.3, 0.5),
		position = UDim2.fromScale(0.93, 0.55),
		anchor = Vector2.new(1, 0.5),
		align = Enum.TextXAlignment.Right,
		maxTextSize = 18,
	})
	hpMax.ZIndex = 3
	local hpStroke = hpPanel:FindFirstChildOfClass("UIStroke") :: UIStroke

	local xpRow = Instance.new("Frame")
	xpRow.Name = "XpRow"
	xpRow.BackgroundTransparency = 1
	xpRow.AnchorPoint = Vector2.new(0, 1)
	xpRow.Position = UDim2.fromScale(0, 1)
	xpRow.Size = UDim2.fromScale(1, 0.3)
	xpRow.Active = false
	xpRow.Parent = vitals
	local lvPanel, lvShadow = UiKit.sticker(xpRow, root, "Level", look.accent, 0.5)
	lvPanel.Size = UDim2.fromScale(0.27, 1)
	UiKit.followShadow(lvPanel, lvShadow, root)
	local levelText = UiKit.label(lvPanel, "Text", { text = "LV1", maxTextSize = 18 })
	local xpTrack, xpShadow = UiKit.sticker(xpRow, root, "XpTrack", look.dim, 0.5)
	xpTrack.AnchorPoint = Vector2.new(1, 0.5)
	xpTrack.Position = UDim2.fromScale(1, 0.5)
	xpTrack.Size = UDim2.fromScale(0.68, 0.5)
	UiKit.followShadow(xpTrack, xpShadow, root)
	local xpClip = Instance.new("CanvasGroup")
	xpClip.BackgroundTransparency = 1
	xpClip.Size = UDim2.fromScale(1, 1)
	xpClip.Parent = xpTrack
	UiKit.round(xpClip, 0.5)
	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.BackgroundColor3 = UiKit.color(look.info)
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = xpClip

	-- ===== status: players left, zone timer =====
	local status = pieceFrame(root, "Status", Layout.regions.status, scales)
	local aliveChip, aliveShadow = UiKit.sticker(status, root, "Alive", look.panel, 0.5)
	aliveChip.Size = UDim2.fromScale(0.44, 1)
	UiKit.followShadow(aliveChip, aliveShadow, root)
	local aliveText = UiKit.label(aliveChip, "Text", { text = "6 LEFT", maxTextSize = 20 })
	aliveText.Size = UDim2.fromScale(0.9, 0.8)
	aliveText.Position = UDim2.fromScale(0.5, 0.5)
	aliveText.AnchorPoint = Vector2.new(0.5, 0.5)
	local zoneChip, zoneShadow = UiKit.sticker(status, root, "Zone", look.panel, 0.5)
	zoneChip.AnchorPoint = Vector2.new(1, 0)
	zoneChip.Position = UDim2.fromScale(1, 0)
	zoneChip.Size = UDim2.fromScale(0.54, 1)
	UiKit.followShadow(zoneChip, zoneShadow, root)
	local zoneText = UiKit.label(zoneChip, "Text", { text = "ZONE 0:00", maxTextSize = 20 })
	zoneText.Size = UDim2.fromScale(0.9, 0.8)
	zoneText.Position = UDim2.fromScale(0.5, 0.5)
	zoneText.AnchorPoint = Vector2.new(0.5, 0.5)
	zoneChip.Visible = false

	-- ===== warning (one line) =====
	local warn = pieceFrame(root, "Warning", Layout.regions.warning, scales)
	local warnPanel, warnShadow = UiKit.sticker(warn, root, "Panel", look.danger, 0.5)
	warnPanel.Size = UDim2.fromScale(1, 1)
	UiKit.followShadow(warnPanel, warnShadow, root)
	local warnText =
		UiKit.label(warnPanel, "Text", { text = "", color = look.panel, maxTextSize = 18 })
	warnText.Size = UDim2.fromScale(0.92, 0.8)
	warnText.Position = UDim2.fromScale(0.5, 0.5)
	warnText.AnchorPoint = Vector2.new(0.5, 0.5)
	warnPanel.Visible = false

	-- ===== minimap =====
	local mini = pieceFrame(root, "Minimap", Layout.regions.minimap, scales)
	local miniPanel, miniShadow = UiKit.sticker(mini, root, "Panel", look.danger, 0.5)
	miniPanel.Size = UDim2.fromScale(1, 1)
	UiKit.followShadow(miniPanel, miniShadow, root)
	local miniClip = Instance.new("CanvasGroup")
	miniClip.Name = "Clip"
	miniClip.BackgroundTransparency = 1
	miniClip.Size = UDim2.fromScale(1, 1)
	miniClip.Parent = miniPanel
	UiKit.circle(miniClip)
	local safeCircle = Instance.new("Frame")
	safeCircle.Name = "Safe"
	safeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	safeCircle.BackgroundColor3 = UiKit.color(look.panel)
	safeCircle.BorderSizePixel = 0
	safeCircle.Size = UDim2.fromScale(4, 4)
	safeCircle.Position = UDim2.fromScale(0.5, 0.5)
	safeCircle.Parent = miniClip
	UiKit.circle(safeCircle)
	local ring = Instance.new("UIStroke")
	ring.Color = UiKit.color(look.outline)
	ring.Parent = safeCircle
	UiKit.styleStroke(ring, root, 0.5)
	local zonePointer = UiKit.label(miniClip, "Pointer", {
		text = "▲",
		color = look.accent,
		size = UDim2.fromScale(0.22, 0.22),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 20,
	})
	zonePointer.Visible = false
	local me = Instance.new("Frame")
	me.Name = "Me"
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.Size = UDim2.fromScale(0.13, 0.13)
	me.BackgroundColor3 = UiKit.color(look.accent)
	me.BorderSizePixel = 0
	me.Parent = miniClip
	UiKit.circle(me)
	local meStroke = Instance.new("UIStroke")
	meStroke.Color = UiKit.color(look.outline)
	meStroke.Parent = me
	UiKit.styleStroke(meStroke, root, 0.8)
	-- a clear button over the whole minimap (piece 47: the big map)
	local mapButton = Instance.new("TextButton")
	mapButton.Name = "OpenMap"
	mapButton.Text = ""
	mapButton.AutoButtonColor = false
	mapButton.Selectable = false
	mapButton.BackgroundTransparency = 1
	mapButton.Size = UDim2.fromScale(1, 1)
	mapButton.ZIndex = 10
	mapButton.Parent = miniPanel
	UiKit.circle(mapButton)

	-- ===== weapon and ammo (also the swap button on touch, see TouchControls) =====
	local weapon = pieceFrame(root, "Weapon", Layout.regions.weapon, scales)
	local wPanel, wShadow = UiKit.sticker(weapon, root, "Panel", look.panel, 0.2)
	wPanel.Size = UDim2.fromScale(1, 1)
	UiKit.followShadow(wPanel, wShadow, root)
	local weaponName = UiKit.label(wPanel, "Name", {
		text = "VOLT PISTOL",
		size = UDim2.fromScale(0.62, 0.26),
		position = UDim2.fromScale(0.07, 0.07),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 14,
	})
	local ammoText = UiKit.label(wPanel, "Ammo", {
		text = "12",
		size = UDim2.fromScale(0.42, 0.5),
		position = UDim2.fromScale(0.07, 0.34),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 40,
	})
	local magText = UiKit.label(wPanel, "Magazine", {
		text = "/ 12",
		size = UDim2.fromScale(0.4, 0.3),
		position = UDim2.fromScale(0.5, 0.52),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 20,
	})
	local slotPips: { Frame } = {}
	for i = 1, 2 do
		local pip = Instance.new("Frame")
		pip.Name = "Slot" .. i
		pip.AnchorPoint = Vector2.new(1, 0)
		pip.Position = UDim2.fromScale(0.93 - (2 - i) * 0.1, 0.1)
		pip.Size = UDim2.fromScale(0.07, 0.14)
		pip.SizeConstraint = Enum.SizeConstraint.RelativeYY
		pip.BackgroundColor3 = UiKit.color(look.dim)
		pip.BorderSizePixel = 0
		pip.Visible = opts.weaponCount > 1
		pip.Parent = wPanel
		UiKit.circle(pip)
		table.insert(slotPips, pip)
	end
	local reloadTrack = Instance.new("Frame")
	reloadTrack.Name = "ReloadTrack"
	reloadTrack.AnchorPoint = Vector2.new(0.5, 1)
	reloadTrack.Position = UDim2.fromScale(0.5, 0.92)
	reloadTrack.Size = UDim2.fromScale(0.86, 0.1)
	reloadTrack.BackgroundColor3 = UiKit.color(look.dim)
	reloadTrack.BorderSizePixel = 0
	reloadTrack.Parent = wPanel
	UiKit.circle(reloadTrack)
	local reloadFill = Instance.new("Frame")
	reloadFill.Name = "Fill"
	reloadFill.BackgroundColor3 = UiKit.color(look.accent)
	reloadFill.BorderSizePixel = 0
	reloadFill.Size = UDim2.fromScale(1, 1)
	reloadFill.Parent = reloadTrack
	UiKit.circle(reloadFill)

	-- ===== hit feedback =====
	local hitArrow = UiKit.label(root, "HitArrow", {
		text = "▲",
		color = look.danger,
		size = UDim2.fromScale(0.04, 0.08),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 40,
	})
	hitArrow.Visible = false
	local hitMarker = UiKit.label(root, "HitMarker", {
		text = "✕",
		color = look.panel,
		size = UDim2.fromScale(0.05, 0.08),
		position = UDim2.fromScale(0.5, 0.36),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 36,
	})
	hitMarker.Visible = false

	return setmetatable({
		gui = gui,
		root = root,
		opts = opts,
		hpFill = hpFill,
		hpGhost = hpGhost,
		hpStroke = hpStroke,
		hpText = hpText,
		hpMax = hpMax,
		levelText = levelText,
		xpFill = xpFill,
		aliveChip = aliveChip,
		aliveShadow = aliveShadow,
		aliveText = aliveText,
		zoneChip = zoneChip,
		zoneShadow = zoneShadow,
		zoneText = zoneText,
		warnPanel = warnPanel,
		warnShadow = warnShadow,
		warnText = warnText,
		warnKey = "",
		safeCircle = safeCircle,
		zonePointer = zonePointer,
		mapButton = mapButton,
		weaponName = weaponName,
		ammoText = ammoText,
		magText = magText,
		reloadFill = reloadFill,
		slotPips = slotPips,
		edges = edges,
		hitArrow = hitArrow,
		hitMarker = hitMarker,
		lastAmmo = -1,
		lastHealthFraction = 1,
		ghostFraction = 1,
		scales = scales,
	}, HudView)
end

function HudView.mount(self: HudView)
	self.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function HudView.setScale(self: HudView, value: number)
	for _, s in self.scales do
		s.Scale = value
	end
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Screen angle of a hit that came FROM world direction (dx, dz), in degrees clockwise from "up".
local function hitAngle(dx: number, dz: number): number?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
	local up2 = Vector2.new(look.X, look.Z)
	local right2 = Vector2.new(right.X, right.Z)
	if up2.Magnitude < 1e-3 then
		return nil
	end
	local d = Vector2.new(dx, dz)
	if d.Magnitude < 1e-3 then
		return nil
	end
	local u, r = d:Dot(up2.Unit), d:Dot(right2.Unit)
	return math.deg(math.atan2(r, u))
end

export type FrameInput = {
	view: HudModel.View,
	now: number,
	hurtDirX: number?,
	hurtDirZ: number?,
	safe: MinimapMath.Circle?, -- the safe circle in minimap units, nil before the first zone
	reduceFlashes: boolean,
	hitAmount: number,
}

function HudView.update(self: HudView, f: FrameInput)
	local v = f.view
	local look = UiKit.look()
	if self.gui.Enabled ~= v.visible then
		self.gui.Enabled = v.visible
	end
	if not v.visible then
		return
	end

	-- health: coral fill, a cream ghost that trails behind a drop
	local hf = v.healthFraction
	self.hpFill.Size = UDim2.fromScale(hf, 1)
	if hf < self.ghostFraction then
		self.ghostFraction = math.max(hf, self.ghostFraction - 0.012)
	else
		self.ghostFraction = hf
	end
	self.hpGhost.Size = UDim2.fromScale(self.ghostFraction, 1)
	self.hpGhost.BackgroundColor3 = UiKit.color(look.panel)
	if hf < self.lastHealthFraction - 0.001 then
		UiKit.pop(self.hpText, 1.15)
	end
	self.lastHealthFraction = hf
	setText(self.hpText, v.healthText)
	setText(self.hpMax, v.maxHealthText)
	-- low health: the outline pulses (steady when "fewer flashes" is on)
	local pulse = if v.lowHealth and not f.reduceFlashes then 0.5 + 0.5 * math.sin(f.now * 8) else 0
	self.hpStroke.Color =
		UiKit.color(look.outline)
			:Lerp(UiKit.color(look.danger), if v.lowHealth then 0.4 + 0.6 * pulse else 0)

	setText(self.levelText, v.levelText)
	self.xpFill.Size = UDim2.fromScale(v.xpFraction, 1)

	-- players left, zone timer
	setText(self.aliveText, v.aliveText .. " LEFT")
	local showZone = v.zoneText ~= ""
	self.zoneChip.Visible = showZone
	self.aliveChip.AnchorPoint = if showZone then Vector2.zero else Vector2.new(0.5, 0)
	self.aliveChip.Position = if showZone then UDim2.fromScale(0, 0) else UDim2.fromScale(0.5, 0)
	if showZone then
		setText(self.zoneText, v.zoneText)
		local hot = v.zoneKind == "warning" or v.zoneKind == "suddenDeath" or v.outsideZone
		self.zoneChip.BackgroundColor3 = UiKit.color(if hot then look.danger else look.panel)
		self.zoneText.TextColor3 = UiKit.color(if hot then look.panel else look.ink)
	end

	-- one warning at a time
	local w = v.warning
	if w then
		if self.warnKey ~= w.key then
			self.warnKey = w.key
			UiKit.pop(self.warnPanel, 1.12)
		end
		self.warnPanel.Visible = true
		setText(self.warnText, w.text)
		local fill = if w.severity == "danger"
			then look.danger
			elseif w.severity == "warn" then look.accent
			else look.panel
		self.warnPanel.BackgroundColor3 = UiKit.color(fill)
		self.warnText.TextColor3 =
			UiKit.color(if w.severity == "danger" then look.panel else look.ink)
	else
		self.warnKey = ""
		self.warnPanel.Visible = false
	end

	-- weapon and ammo
	setText(self.weaponName, string.upper(v.weaponName))
	setText(self.ammoText, v.ammoText)
	setText(self.magText, v.magazineText)
	self.ammoText.TextColor3 =
		UiKit.color(if v.ammoLow or v.ammoText == "0" then look.danger else look.ink)
	if v.ammoText ~= "" and tonumber(v.ammoText) ~= self.lastAmmo then
		if self.lastAmmo >= 0 and (tonumber(v.ammoText) or 0) > self.lastAmmo then
			UiKit.pop(self.ammoText, 1.2) -- reloaded
		end
		self.lastAmmo = tonumber(v.ammoText) or -1
	end
	self.reloadFill.Size = UDim2.fromScale(if v.reloading then v.reloadFraction else 0, 1)
	for i, pip in self.slotPips do
		pip.BackgroundColor3 = UiKit.color(if i == v.slot then look.danger else look.dim)
	end

	-- minimap: safe circle relative to the player, a pointer to it when it is off the map
	local safe = f.safe
	if safe then
		local r = math.min(safe.r, 8)
		self.safeCircle.Size = UDim2.fromScale(r, r)
		self.safeCircle.Position = UDim2.fromScale(0.5 + safe.u / 2, 0.5 + safe.v / 2)
		local pu, pv, pinned = MinimapMath.clampToRim(safe.u, safe.v, 0.3)
		local showPointer = v.outsideZone and pinned
		self.zonePointer.Visible = showPointer
		if showPointer then
			self.zonePointer.Position = UDim2.fromScale(0.5 + pu / 2, 0.5 + pv / 2)
			self.zonePointer.Rotation = math.deg(math.atan2(safe.u, -safe.v))
		end
	else
		self.safeCircle.Size = UDim2.fromScale(4, 4)
		self.safeCircle.Position = UDim2.fromScale(0.5, 0.5)
		self.zonePointer.Visible = false
	end

	-- hurt edges and the arrow showing where a hit came from
	local strength = v.hurt * (if f.reduceFlashes then 0.45 else 0.85)
	local outside = if v.outsideZone
		then (if f.reduceFlashes then 0.25 else 0.35 + 0.15 * math.sin(f.now * 6))
		else 0
	local alpha = 1 - math.max(strength, outside)
	for _, e in self.edges do
		e.BackgroundTransparency = alpha
	end
	if v.hurt > 0 and f.hurtDirX ~= nil and f.hurtDirZ ~= nil then
		local angle = hitAngle(f.hurtDirX, f.hurtDirZ)
		if angle ~= nil then
			local r = math.rad(angle)
			self.hitArrow.Visible = true
			self.hitArrow.Rotation = angle
			self.hitArrow.Position =
				UDim2.fromScale(0.5 + math.sin(r) * 0.11 * 0.46, 0.5 - math.cos(r) * 0.11)
			self.hitArrow.TextTransparency = 1 - v.hurt
		end
	else
		self.hitArrow.Visible = false
	end
	self.hitMarker.Visible = v.hitConfirm > 0
	self.hitMarker.TextTransparency = 1 - v.hitConfirm
end

return HudView

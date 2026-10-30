--!strict
-- Draws the big map: the whole arena, the safe circle, the next circle and you. Display only.
-- Placeholder look from Ui/Tokens roles; Claude Design owns the real one. Takes one tap (anywhere
-- on the map) to close and nothing else, so the thumbs stay free while it is open.
-- The ground square is turned with the camera, so up on the map is up on your screen.

local Components = require(script.Parent.Parent.Ui.Components)
local Tokens = require(script.Parent.Parent.Ui.Tokens)
local BigMapMath = require("./BigMapMath")
local Layout = require("./Layout")
local UiKit = require("./UiKit")

local BigMapView = {}
BigMapView.__index = BigMapView

export type ZoneDraw = { centerX: number, centerZ: number, radius: number, targetRadius: number }

export type FrameInput = {
	open: boolean,
	px: number?, -- where you stand
	pz: number?,
	yaw: number, -- CameraHeading.get()
	zone: ZoneDraw?, -- nil before the first zone
}

export type BigMapView = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		arena: BigMapMath.Arena,
		ground: CanvasGroup,
		safe: Frame,
		nextRing: Frame,
		me: Frame,
		shown: boolean,
	},
	BigMapView
))

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

local function circleFrame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.Active = false
	f.Parent = parent
	UiKit.circle(f)
	return f
end

-- `onTap` runs when the map is tapped (the caller closes it).
function BigMapView.new(arena: BigMapMath.Arena, onTap: () -> ()): BigMapView
	local gui, root = Components.screen("BigMap", "BigMap")
	gui.Enabled = false

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.Parent = root
	UiKit.place(holder, Layout.bigMap)

	local panel, shadow = Components.panel(holder, root, "Panel", "dim")
	panel.Size = UDim2.fromScale(1, 1)
	shadow.Active = false

	local clip = Instance.new("CanvasGroup")
	clip.Name = "Clip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.Active = false
	clip.Parent = panel
	UiKit.round(clip, 0.06)

	-- the arena: red everywhere, with the safe circle drawn on it
	local side = BigMapMath.arenaSide()
	local ground = Instance.new("CanvasGroup")
	ground.Name = "Ground"
	ground.AnchorPoint = Vector2.new(0.5, 0.5)
	ground.Position = UDim2.fromScale(0.5, 0.5)
	ground.Size = UDim2.fromScale(side, side)
	ground.BackgroundColor3 = color("danger")
	ground.BorderSizePixel = 0
	ground.Active = false
	ground.Parent = clip
	local groundStroke = Instance.new("UIStroke")
	groundStroke.Color = color("outline")
	groundStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	groundStroke.Parent = ground
	UiKit.styleStroke(groundStroke, root, 0.6)

	local safe = circleFrame(ground, "Safe")
	safe.BackgroundColor3 = color("panel")
	safe.Size = UDim2.fromScale(BigMapMath.MAX_RING, BigMapMath.MAX_RING)
	safe.Position = UDim2.fromScale(0.5, 0.5)

	local nextRing = circleFrame(ground, "Next")
	nextRing.BackgroundTransparency = 1
	nextRing.Visible = false
	local nextStroke = Instance.new("UIStroke")
	nextStroke.Color = color("ink")
	nextStroke.Parent = nextRing
	UiKit.styleStroke(nextStroke, root, 0.8)

	-- you: a dot on the panel (not on the turned ground), so it never tilts
	local me = circleFrame(clip, "Me")
	me.BackgroundColor3 = color("accent")
	me.Size = UDim2.fromScale(0.06, 0.06)
	me.ZIndex = 5
	me.Visible = false
	local meStroke = Instance.new("UIStroke")
	meStroke.Color = color("outline")
	meStroke.Parent = me
	UiKit.styleStroke(meStroke, root, 0.8)

	local title = Components.text(panel, root, "Title", "caption", {
		text = "MAP",
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.3, 0.09),
		position = UDim2.fromScale(0.04, 0.03),
	})
	title.ZIndex = 6
	local hint = Components.text(panel, root, "Hint", "caption", {
		text = "TAP TO CLOSE",
		size = UDim2.fromScale(0.5, 0.08),
		position = UDim2.fromScale(0.5, 0.96),
		anchor = Vector2.new(0.5, 1),
	})
	hint.ZIndex = 6

	-- the whole map is one big tap target
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.Selectable = false
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 10
	tap.Parent = panel
	tap.Activated:Connect(onTap)

	return setmetatable({
		gui = gui,
		arena = arena,
		ground = ground,
		safe = safe,
		nextRing = nextRing,
		me = me,
		shown = false,
	}, BigMapView)
end

function BigMapView.update(self: BigMapView, f: FrameInput)
	if self.shown ~= f.open then
		self.shown = f.open
		self.gui.Enabled = f.open
	end
	if not f.open then
		return
	end

	self.ground.Rotation = BigMapMath.arenaRotation(f.yaw)

	local zone = f.zone
	if zone then
		local safe = BigMapMath.ring(zone.centerX, zone.centerZ, zone.radius, self.arena)
		self.safe.Size = UDim2.fromScale(safe.size, safe.size)
		self.safe.Position = UDim2.fromScale(safe.x, safe.y)
		-- the next circle only shows while the safe one is still on its way there
		local ahead = zone.radius - zone.targetRadius > 0.5
		self.nextRing.Visible = ahead
		if ahead then
			local nxt = BigMapMath.ring(zone.centerX, zone.centerZ, zone.targetRadius, self.arena)
			self.nextRing.Size = UDim2.fromScale(nxt.size, nxt.size)
			self.nextRing.Position = UDim2.fromScale(nxt.x, nxt.y)
		end
	else
		self.safe.Size = UDim2.fromScale(BigMapMath.MAX_RING, BigMapMath.MAX_RING)
		self.safe.Position = UDim2.fromScale(0.5, 0.5)
		self.nextRing.Visible = false
	end

	local px, pz = f.px, f.pz
	if px ~= nil and pz ~= nil then
		local spot = BigMapMath.point(px, pz, self.arena, f.yaw)
		self.me.Position = UDim2.fromScale(spot.x, spot.y)
		self.me.Visible = true
	else
		self.me.Visible = false
	end
end

return BigMapView

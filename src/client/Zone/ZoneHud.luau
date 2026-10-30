--!strict
-- "You are outside the zone" feedback: red screen edges and an arrow back toward the circle.
-- The warning text and timer are piece 10's HUD (it reads the same ZoneState), so no banner here.

local Players = game:GetService("Players")

local UiLayers = require(script.Parent.Parent.Ui.UiLayers)
local Look = require(script.Parent.Parent.Ui.Look)

local Hud = {}
Hud.__index = Hud

local CORAL = Look.color("danger")

export type Hud = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		arrow: TextLabel,
		edges: { Frame },
		outsideShown: boolean,
		lastRotation: number,
	},
	Hud
))

local function edge(
	parent: Instance,
	anchor: Vector2,
	position: UDim2,
	size: UDim2,
	rotation: number
): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = CORAL
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.Visible = false
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new(0.2, 1)
	g.Rotation = rotation
	g.Parent = f
	f.Parent = parent
	return f
end

function Hud.new(): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "ZoneHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = UiLayers.ZoneTint
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local edges = {
		edge(gui, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.16), 90),
		edge(gui, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.16), -90),
		edge(gui, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.1, 1), 0),
		edge(gui, Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.1, 1), 180),
	}

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Position = UDim2.new(0.5, 0, 0, 80)
	arrow.Size = UDim2.fromOffset(40, 40)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.TextColor3 = CORAL
	arrow.TextStrokeTransparency = 0.3
	arrow.Font = Look.font("display")
	arrow.TextSize = 32
	arrow.Visible = false
	arrow.Active = false
	arrow.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return setmetatable({
		gui = gui,
		arrow = arrow,
		edges = edges,
		outsideShown = false,
		lastRotation = 0,
	}, Hud)
end

-- outside: the local player is outside the safe circle and it hurts.
-- headingDegrees: clockwise angle of the way back in, relative to the top of the screen.
function Hud.setOutside(self: Hud, outside: boolean, headingDegrees: number, now: number)
	if outside ~= self.outsideShown then
		self.outsideShown = outside
		for _, f in self.edges do
			f.Visible = outside
		end
		self.arrow.Visible = outside
	end
	if outside then
		local pulse = 0.15 + 0.2 * (0.5 + 0.5 * math.sin(now * 8))
		for _, f in self.edges do
			f.BackgroundTransparency = pulse
		end
		if math.abs(headingDegrees - self.lastRotation) > 1 then
			self.lastRotation = headingDegrees
			self.arrow.Rotation = headingDegrees
		end
	end
end

function Hud.setVisible(self: Hud, visible: boolean)
	self.gui.Enabled = visible
end

return Hud

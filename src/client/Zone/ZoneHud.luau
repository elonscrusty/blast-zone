--!strict
-- Zone warning text and "you are outside" feedback. One banner at a time (the most urgent one
-- wins) so nothing stacks up: outside > warning > closing > sudden death. Sits near the top,
-- clear of the thumbs. Piece 10 may move or restyle it; the data comes from ZoneView.

local Players = game:GetService("Players")

local Hud = {}
Hud.__index = Hud

local CORAL = Color3.fromRGB(241, 91, 100)
local CYAN = Color3.fromRGB(54, 217, 232)
local GOLD = Color3.fromRGB(255, 196, 77)
local NAVY = Color3.fromRGB(20, 36, 58)

export type Hud = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		banner: TextLabel,
		stroke: UIStroke,
		arrow: TextLabel,
		edges: { Frame },
		text: string,
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
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local edges = {
		edge(gui, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.16), 90),
		edge(gui, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.16), -90),
		edge(gui, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.1, 1), 0),
		edge(gui, Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.1, 1), 180),
	}

	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 72)
	banner.AutomaticSize = Enum.AutomaticSize.X
	banner.Size = UDim2.fromOffset(0, 40)
	banner.BackgroundColor3 = NAVY
	banner.BackgroundTransparency = 0.12
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 22
	banner.Text = ""
	banner.Visible = false
	banner.Active = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = banner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = banner
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = GOLD
	stroke.Parent = banner
	banner.Parent = gui

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Position = UDim2.new(0.5, 0, 0, 118)
	arrow.Size = UDim2.fromOffset(40, 40)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.TextColor3 = CORAL
	arrow.TextStrokeTransparency = 0.3
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 32
	arrow.Visible = false
	arrow.Active = false
	arrow.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return setmetatable({
		gui = gui,
		banner = banner,
		stroke = stroke,
		arrow = arrow,
		edges = edges,
		text = "",
		outsideShown = false,
		lastRotation = 0,
	}, Hud)
end

function Hud.setBanner(self: Hud, text: string, color: Color3)
	if text == "" then
		self.banner.Visible = false
		self.text = ""
		return
	end
	if text ~= self.text then
		self.text = text
		self.banner.Text = text
	end
	self.stroke.Color = color
	self.banner.Visible = true
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

Hud.COLORS = { coral = CORAL, cyan = CYAN, gold = GOLD }

return Hud

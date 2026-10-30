--!strict
-- "How to play": carter's pick C, Four Tiles. One screen, four tiles (move, aim, fire, slide), one
-- GOT IT button and a Skip. Street Sticker style like the rest of the UI. Shown in the lobby only.
-- The little pictures are drawn from plain frames (no art ids): a cyan fighter, gold aim and shot marks.
-- Words come from IntroSteps, so they follow the player's device.

local UserInputService = game:GetService("UserInputService")

local Players = game:GetService("Players")

local UiKit = require(script.Parent.Parent.Hud.UiKit)
local IntroSteps = require(script.Parent.IntroSteps)

local IntroView = {}

local ASPECT = 2.1 -- panel width / height
local CYAN = "#36D9E8"
local GOLD = "#FFC44D"
local CORAL = "#F15B64"
local NAVY = "#14243A"
local NAVY_LIGHT = "#1D3552"
local CREAM = "#FFF4D6"

local gui: ScreenGui? = nil
local panel: Frame
local tileNames: { TextLabel } = {}
local tileTexts: { TextLabel } = {}
local gotIt: TextButton
local skip: TextButton
local onFinish: ((boolean) -> ())? = nil
local open = false

-- A circle placed by scale inside `parent`. `d` is its height as a share of the parent's height.
local function disc(
	parent: GuiObject,
	cx: number,
	cy: number,
	d: number,
	color: string,
	transparency: number?
): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(d, d)
	f.BackgroundColor3 = UiKit.color(color)
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Active = false
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = f
	UiKit.circle(f)
	f.Parent = parent
	return f
end

-- A bar centred at (cx, cy); w and h are shares of the parent's width and height.
local function bar(
	parent: GuiObject,
	cx: number,
	cy: number,
	w: number,
	h: number,
	color: string,
	rotation: number?,
	transparency: number?
): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.BackgroundColor3 = UiKit.color(color)
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Active = false
	UiKit.round(f, 0.5)
	f.Parent = parent
	return f
end

local function outlineRing(
	parent: GuiObject,
	cx: number,
	cy: number,
	d: number,
	color: string,
	transparency: number
)
	local ring = disc(parent, cx, cy, d, color, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.color(color)
	stroke.Thickness = 2
	stroke.Transparency = transparency
	stroke.Parent = ring
	return ring
end

local PICTURES: { [string]: (GuiObject) -> () } = {
	move = function(p)
		outlineRing(p, 0.3, 0.52, 0.8, CREAM, 0.6)
		disc(p, 0.36, 0.44, 0.34, CYAN)
		bar(p, 0.7, 0.34, 0.3, 0.09, GOLD, -35)
		bar(p, 0.8, 0.22, 0.12, 0.08, GOLD, 10)
		bar(p, 0.85, 0.32, 0.12, 0.08, GOLD, -75)
	end,
	aim = function(p)
		outlineRing(p, 0.28, 0.52, 0.8, GOLD, 0.2)
		disc(p, 0.28, 0.52, 0.36, CYAN)
		for i = 0, 4 do
			disc(p, 0.5 + i * 0.1, 0.52 - i * 0.045, 0.08, GOLD)
		end
	end,
	fire = function(p)
		disc(p, 0.2, 0.55, 0.34, CYAN)
		bar(p, 0.36, 0.55, 0.18, 0.1, CREAM)
		bar(p, 0.55, 0.55, 0.1, 0.06, GOLD)
		bar(p, 0.69, 0.55, 0.1, 0.06, GOLD)
		disc(p, 0.86, 0.55, 0.22, CORAL)
	end,
	slide = function(p)
		bar(p, 0.36, 0.55, 0.5, 0.12, CYAN, 0, 0.5)
		disc(p, 0.2, 0.55, 0.3, CYAN, 0.8)
		disc(p, 0.34, 0.55, 0.3, CYAN, 0.65)
		disc(p, 0.48, 0.55, 0.3, CYAN, 0.45)
		disc(p, 0.66, 0.55, 0.34, CYAN)
	end,
}

local function finish()
	if not open then
		return
	end
	local callback = onFinish
	IntroView.hide()
	if callback then
		callback(false)
	end
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	pos: UDim2,
	size: UDim2,
	color: string,
	maxSize: number
)
	local l = UiKit.label(parent, name, {
		text = text,
		size = size,
		position = pos,
		color = color,
		maxTextSize = maxSize,
	})
	l.TextWrapped = true
	return l
end

local function button(parent: Instance, name: string, text: string, fill: string?): TextButton
	local look = UiKit.look()
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = UiKit.FONT
	b.TextScaled = true
	b.TextColor3 = UiKit.color(look.ink)
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	if fill then
		b.BackgroundColor3 = UiKit.color(fill)
		UiKit.round(b, 0.3)
		local stroke = Instance.new("UIStroke")
		stroke.Color = UiKit.color(look.outline)
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b
	else
		b.BackgroundTransparency = 1
	end
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 26
	cap.MinTextSize = 8
	cap.Parent = b
	b.Parent = parent
	return b
end

local function build()
	local look = UiKit.look()
	local g = Instance.new("ScreenGui")
	g.Name = "Intro"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.None
	g.DisplayOrder = 55 -- above the match screens, so PLAY cannot be pressed under it
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false

	local veil = Instance.new("TextButton") -- swallows taps behind the panel
	veil.Name = "Veil"
	veil.Text = ""
	veil.AutoButtonColor = false
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = UiKit.color(look.outline)
	veil.BackgroundTransparency = 0.4
	veil.BorderSizePixel = 0
	veil.Parent = g

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = g

	local shadow
	panel, shadow = UiKit.sticker(root, root, "Panel", nil, 0.06)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.8, 0.8)
	panel.Active = true
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = ASPECT
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = panel
	UiKit.followShadow(panel, shadow, root)

	label(
		panel,
		"Title",
		"HOW TO PLAY",
		UDim2.fromScale(0.05, 0.04),
		UDim2.fromScale(0.5, 0.14),
		look.ink,
		34
	).TextXAlignment =
		Enum.TextXAlignment.Left

	skip = button(panel, "Skip", "<u>Skip</u>", nil)
	skip.RichText = true
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.fromScale(0.96, 0.03)
	skip.Size = UDim2.fromScale(0.2, 0.17)

	local ids = IntroSteps.order
	local tileW, gap = 0.215, 0.0133
	for i, id in ids do
		local tile = Instance.new("Frame")
		tile.Name = "Tile_" .. id
		tile.BackgroundColor3 = UiKit.color(NAVY)
		tile.BorderSizePixel = 0
		tile.Position = UDim2.fromScale(0.05 + (i - 1) * (tileW + gap), 0.2)
		tile.Size = UDim2.fromScale(tileW, 0.58)
		UiKit.round(tile, 0.08)
		tile.Parent = panel

		local picture = Instance.new("Frame")
		picture.Name = "Picture"
		picture.BackgroundColor3 = UiKit.color(NAVY_LIGHT)
		picture.BorderSizePixel = 0
		picture.Position = UDim2.fromScale(0.05, 0.04)
		picture.Size = UDim2.fromScale(0.9, 0.46)
		picture.ClipsDescendants = true
		UiKit.round(picture, 0.1)
		picture.Parent = tile
		PICTURES[id](picture)

		tileNames[i] = label(
			tile,
			"Name",
			"",
			UDim2.fromScale(0.05, 0.5),
			UDim2.fromScale(0.9, 0.18),
			GOLD,
			24
		)
		tileTexts[i] = label(
			tile,
			"Text",
			"",
			UDim2.fromScale(0.06, 0.69),
			UDim2.fromScale(0.88, 0.29),
			CREAM,
			17
		)
	end

	gotIt = button(panel, "GotIt", "GOT IT", look.accent)
	gotIt.AnchorPoint = Vector2.new(1, 1)
	gotIt.Position = UDim2.fromScale(0.95, 0.97)
	gotIt.Size = UDim2.fromScale(0.3, 0.17)

	gotIt.Activated:Connect(finish)
	skip.Activated:Connect(finish)

	-- Keyboard and controller: Return or A is GOT IT, Escape or B skips (both count as seen).
	UserInputService.InputBegan:Connect(function(input, processed)
		if not open or processed then
			return
		end
		local code = input.KeyCode
		if
			code == Enum.KeyCode.Return
			or code == Enum.KeyCode.ButtonA
			or code == Enum.KeyCode.Escape
			or code == Enum.KeyCode.ButtonB
		then
			finish()
		end
	end)

	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
end

function IntroView.isOpen(): boolean
	return open
end

-- Fills in the words (call again when the player changes device).
function IntroView.setSteps(steps: { IntroSteps.Step })
	if gui == nil then
		build()
	end
	for i, step in steps do
		if tileNames[i] then
			tileNames[i].Text = step.title
			tileTexts[i].Text = step.text
		end
	end
end

-- onDone(skipped) is called once when the player taps GOT IT or Skip, never when hidden by the system.
function IntroView.show(steps: { IntroSteps.Step }, onDone: (boolean) -> ())
	IntroView.setSteps(steps)
	if open then
		return
	end
	open = true
	onFinish = onDone
	local g = gui :: ScreenGui
	g.Enabled = true
	UiKit.pop(panel, 0.94)
end

-- Closes without calling the callback (a match began, so the intro is not "seen").
function IntroView.hide()
	open = false
	onFinish = nil
	if gui then
		gui.Enabled = false
	end
end

return IntroView

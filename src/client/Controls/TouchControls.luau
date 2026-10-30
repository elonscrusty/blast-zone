--!strict
-- On-screen controls for phones, in look B: move stick (left), aim-and-fire stick (right),
-- Slide, Run, Reload, Heal, a tap target over the weapon panel to swap weapons, and three upgrade pick chips.
-- Sticks measure how far the finger moved from where it first touched, so they work the same on
-- every phone and notch. With "Floating sticks" on (carter's pick) the stick appears under the
-- thumb anywhere in its zone and goes back to a faint ring at rest; off, it stays in its corner.
-- A drag on the free side of the screen (not the aim stick, not a button) turns the camera.
-- Pick chips appear by the aim thumb while an upgrade offer is up, so the move thumb never lifts.
-- Shown only on touch devices while controls are on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Layout = require(script.Parent.Parent.Hud.Layout)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Settings = require(script.Parent.Parent.Settings.Settings)
local Ids = require(ReplicatedStorage:WaitForChild("Shared").Ids)
local Net = require(script.Parent.Parent.Core.Net)
local Controls = require(script.Parent.Controls)
local LootClient = require(script.Parent.Parent.Loot.LootClient)
local MoveState = require(script.Parent.Parent.Movement.MoveState)
local ChipModel = require("./ChipModel")
local InputMath = require("./InputMath")

local TouchControls = {}

local gui: ScreenGui
local root: Frame
local pieces: { [string]: GuiObject } = {}
local slideDial: Frame
local slideText: TextLabel
local healCount: TextLabel
local sprintVeil: Frame
local slideCount: TextLabel
local visible = false
local wasSlideReady = true

local homeOf: { [string]: () -> () } = {} -- puts a floating stick back at its resting place

local function applyLayout()
	local left = Settings.flag("leftHanded")
	local scale = Settings.number("touchScale")
	for name, obj in pieces do
		local zone = Layout.zones[name]
		if zone then
			UiKit.place(obj, zone, left) -- a catch area: no scaling, it must not shrink
		else
			local rect = Layout.regions[name]
			local index = tonumber(string.match(name, "^chip(%d)$"))
			if index then
				rect = Layout.regions[Layout.chipName(index, left)]
			end
			UiKit.place(obj, rect, left)
			local found = obj:FindFirstChild("TouchScale")
			local s: UIScale
			if found and found:IsA("UIScale") then
				s = found
			else
				s = Instance.new("UIScale")
				s.Name = "TouchScale"
				s.Parent = obj
			end
			s.Scale = scale
		end
	end
end

-- The area that catches a thumb for a stick. Created before the buttons so they sit on top: a
-- touch on a button is a button, any other touch in the zone is the stick.
local function makeZone(name: string): Frame
	local zone = Instance.new("Frame")
	zone.Name = name
	zone.BackgroundTransparency = 1
	zone.BorderSizePixel = 0
	zone.Active = true
	zone.Parent = root
	pieces[name] = zone
	return zone
end

-- A stick. `onChange(x, y, active)` gets a vector of length 0..1 with y UP.
local function makeStick(
	name: string,
	zone: Frame,
	label: string?,
	fillHex: string,
	onChange: (number, number, boolean) -> ()
)
	local look = UiKit.look()
	local base, shadow = UiKit.sticker(root, root, name, fillHex, 0.5)
	UiKit.followShadow(base, shadow, root)
	pieces[name] = base

	local function dim()
		-- A faint ring shows where to start; once it is under a thumb it is solid.
		base.BackgroundTransparency = if Settings.flag("floatingSticks") then 0.6 else 0.25
	end
	dim()

	if label then
		UiKit.label(base, "Label", {
			text = label,
			size = UDim2.fromScale(0.6, 0.3),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = look.panel,
			maxTextSize = 34,
		})
	end

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.42, 0.42)
	knob.BackgroundColor3 = UiKit.color(look.panel)
	knob.BorderSizePixel = 0
	knob.Active = false
	knob.Parent = base
	UiKit.circle(knob)
	local ks = Instance.new("UIStroke")
	ks.Color = UiKit.color(look.outline)
	ks.Parent = knob
	UiKit.styleStroke(ks, root)

	local tracked: InputObject? = nil
	local startX, startY = 0, 0

	local function goHome()
		UiKit.place(base, Layout.regions[name], Settings.flag("leftHanded"))
	end
	homeOf[name] = goHome

	local function release()
		tracked = nil
		knob.Position = UDim2.fromScale(0.5, 0.5)
		goHome()
		dim()
		onChange(0, 0, false)
	end

	-- Floating: put the stick under the finger, kept inside its zone so it is never half off screen.
	local function floatUnder(input: InputObject)
		local radius = base.AbsoluteSize.X / 2
		local zp, zs, rp = zone.AbsolutePosition, zone.AbsoluteSize, root.AbsolutePosition
		local cx = if zs.X > 2 * radius
			then math.clamp(input.Position.X, zp.X + radius, zp.X + zs.X - radius)
			else zp.X + zs.X / 2
		local cy = if zs.Y > 2 * radius
			then math.clamp(input.Position.Y, zp.Y + radius, zp.Y + zs.Y - radius)
			else zp.Y + zs.Y / 2
		base.AnchorPoint = Vector2.new(0.5, 0.5)
		base.Position = UDim2.fromOffset(cx - rp.X, cy - rp.Y)
		base.BackgroundTransparency = 0.25
	end

	local function move(input: InputObject)
		local radius = base.AbsoluteSize.X / 2
		local dx, dy = input.Position.X - startX, input.Position.Y - startY
		local x, y = InputMath.stickFromOffset(dx, dy, radius)
		-- Draw the knob where the (clamped) finger offset says, not through the deadzone.
		local mag = math.sqrt(dx * dx + dy * dy)
		local clamp = if mag > radius then radius / mag else 1
		knob.Position = UDim2.new(0.5, dx * clamp, 0.5, dy * clamp)
		onChange(x, y, true)
	end

	zone.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and tracked == nil then
			Controls.noteDevice("touch") -- first: a device change clears sticks, so it comes before we hold this one
			tracked = input
			startX, startY = input.Position.X, input.Position.Y
			if Settings.flag("floatingSticks") then
				floatUnder(input)
			end
			move(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			move(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			release()
		end
	end)
	-- Focus lost, a menu opened, a gamepad took over: let go even though the finger is still down.
	Controls.Cleared:connect(function()
		if tracked ~= nil then
			release()
		end
	end)
	-- Hiding the stick mid-touch must not leave it "held".
	zone:GetPropertyChangedSignal("Visible"):Connect(function()
		if not zone.Visible and tracked ~= nil then
			release()
		end
	end)
	Settings.Changed:connect(function(key: string)
		if key == "floatingSticks" then
			if tracked ~= nil then
				release() -- switching style mid-touch: let go, no half-moved stick
			else
				goHome()
				dim()
			end
		end
	end)
end

-- Turning the camera: a finger dragged sideways on the free side of the screen. It needs no ring
-- or button, so there is nothing to find with a thumb.
local function makeLook(zone: Frame)
	local tracked: InputObject? = nil
	local lastX = 0

	zone.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and tracked == nil then
			Controls.noteDevice("touch")
			tracked = input
			lastX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			Controls.addLook(input.Position.X - lastX)
			lastX = input.Position.X
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			tracked = nil
		end
	end)
	Controls.Cleared:connect(function()
		tracked = nil
	end)
	zone:GetPropertyChangedSignal("Visible"):Connect(function()
		if not zone.Visible then
			tracked = nil
		end
	end)
end

local function makeButton(name: string, text: string, fillHex: string, action: string): TextButton
	local look = UiKit.look()
	local panel, shadow = UiKit.sticker(root, root, name .. "Frame", fillHex, 0.5)
	UiKit.followShadow(panel, shadow, root)
	pieces[name] = panel

	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = panel
	button.Activated:Connect(function()
		Controls.noteDevice("touch")
		Controls.trigger(action)
		UiKit.pop(panel, 0.92)
	end)

	UiKit.label(panel, "Label", {
		text = text,
		size = UDim2.fromScale(0.8, 0.3),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = look.ink,
		maxTextSize = 22,
	})
	return button
end

local function build()
	local look = UiKit.look()
	gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = require(script.Parent.Parent.Ui.UiLayers).TouchControls
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	makeLook(makeZone("lookZone")) -- first, so the sticks and buttons sit on top of it
	local moveZone = makeZone("moveZone")
	local fireZone = makeZone("fireZone")
	makeStick("moveStick", moveZone, nil, look.panel, function(x, y, _active)
		Controls.setTouchMove(x, y)
	end)
	makeStick("fireStick", fireZone, "FIRE", look.danger, function(x, y, active)
		Controls.setTouchAim(x, y, active)
	end)

	makeButton("slide", "SLIDE", look.accent, "slide")
	makeButton("reload", "RELOAD", look.panel, "reload")
	-- Heal pack button (piece 42): the count sits under the word. Placeholder look.
	makeButton("heal", "HEAL", look.good, "heal")
	local healLabel = pieces.heal:FindFirstChild("Label")
	if healLabel and healLabel:IsA("TextLabel") then
		healLabel.Position = UDim2.fromScale(0.5, 0.36)
	end
	healCount = UiKit.label(pieces.heal, "Count", {
		text = "0",
		size = UDim2.fromScale(0.6, 0.38),
		position = UDim2.fromScale(0.5, 0.7),
		anchor = Vector2.new(0.5, 0.5),
		color = look.ink,
		maxTextSize = 24,
	})
	healCount.ZIndex = 4

	-- Sprint toggle (piece 45): the veil drops as breath runs out. Placeholder look.
	makeButton("sprint", "RUN", look.panel, "sprint")
	do
		local sprint = pieces.sprint
		local breathClip = Instance.new("CanvasGroup")
		breathClip.Name = "Clip"
		breathClip.BackgroundTransparency = 1
		breathClip.Size = UDim2.fromScale(1, 1)
		breathClip.Active = false
		breathClip.ZIndex = 3
		breathClip.Parent = sprint
		UiKit.circle(breathClip)
		sprintVeil = Instance.new("Frame")
		sprintVeil.Name = "Veil"
		sprintVeil.Size = UDim2.fromScale(1, 0)
		sprintVeil.BackgroundColor3 = UiKit.color(look.outline)
		sprintVeil.BackgroundTransparency = 0.35
		sprintVeil.BorderSizePixel = 0
		sprintVeil.Active = false
		sprintVeil.Parent = breathClip
	end

	-- Slide cooldown: a navy veil that drains upward, and the seconds left.
	local slide = pieces.slide
	local clip = Instance.new("CanvasGroup")
	clip.Name = "Clip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.Active = false
	clip.ZIndex = 3
	clip.Parent = slide
	UiKit.circle(clip)
	slideDial = Instance.new("Frame")
	slideDial.Name = "Veil"
	slideDial.AnchorPoint = Vector2.new(0, 1)
	slideDial.Position = UDim2.fromScale(0, 1)
	slideDial.Size = UDim2.fromScale(1, 0.6)
	slideDial.BackgroundColor3 = UiKit.color(look.outline)
	slideDial.BackgroundTransparency = 0.35
	slideDial.BorderSizePixel = 0
	slideDial.Active = false
	slideDial.Parent = clip
	slideText = UiKit.label(slide, "Seconds", {
		text = "",
		size = UDim2.fromScale(0.7, 0.4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = look.panel,
		maxTextSize = 26,
	})
	slideText.ZIndex = 4
	-- How many slides are ready (piece 45); only shown when there is more than one charge.
	slideCount = UiKit.label(slide, "Charges", {
		text = "",
		size = UDim2.fromScale(0.4, 0.3),
		position = UDim2.fromScale(0.5, 0.82),
		anchor = Vector2.new(0.5, 0.5),
		color = look.ink,
		maxTextSize = 20,
	})
	slideCount.ZIndex = 4

	-- Tap target over the weapon panel (the picture is drawn by the HUD).
	local swap = Instance.new("TextButton")
	swap.Name = "weapon"
	swap.Text = ""
	swap.AutoButtonColor = false
	swap.BackgroundTransparency = 1
	swap.Parent = root
	swap.Activated:Connect(function()
		Controls.noteDevice("touch")
		Controls.trigger("swap")
	end)
	pieces.weapon = swap

	-- Upgrade pick chips: 1 2 3 by the aim thumb, shown while an offer is up. A tap is the same
	-- action as the key (upgradeN); the cards and the server decide if it counts.
	local chipState = ChipModel.new()
	local chips: { Frame } = {}
	local function showChips(count: number)
		for i, chip in chips do
			local want = i <= count
			if chip.Visible ~= want then
				chip.Visible = want
				if want then
					UiKit.pop(chip, 1.25)
				end
			end
		end
	end
	for i = 1, 3 do
		local chip = makeButton("chip" .. i, tostring(i), look.accent, "upgrade" .. i)
		local frame = chip.Parent :: Frame
		frame.Visible = false
		local number = frame:FindFirstChild("Label")
		if number and number:IsA("TextLabel") then
			number.Size = UDim2.fromScale(0.8, 0.7)
			local cap = number:FindFirstChildOfClass("UITextSizeConstraint")
			if cap then
				cap.MaxTextSize = 40
			end
		end
		table.insert(chips, frame)
	end
	Net.on("UpgradeOffer", function(payload: any)
		showChips(ChipModel.applyOffer(chipState, payload))
	end)
	Net.on("UpgradeApplied", function()
		ChipModel.clear(chipState)
		showChips(0)
	end)
	Net.on("MatchState", function(state: any)
		if type(state) ~= "table" or not ChipModel.fighting((state :: any).phase) then
			ChipModel.clear(chipState)
			showChips(0)
		end
	end)
	Net.on("Eliminated", function(info: any)
		if type(info) == "table" and info.victimId == Ids.player(Players.LocalPlayer.UserId) then
			ChipModel.clear(chipState) -- an eliminated player picks nothing
			showChips(0)
		end
	end)

	applyLayout()
	Settings.Changed:connect(function(key: string)
		if key == "leftHanded" or key == "touchScale" then
			applyLayout()
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TouchControls.start()
	build()
	Controls.DeviceChanged:connect(function()
		gui.Enabled = visible and Controls.device() == "touch"
	end)
	gui.Enabled = visible and Controls.device() == "touch"
end

-- Called every frame by HudSystem. `show` = the HUD wants controls on screen.
function TouchControls.update(
	show: boolean,
	slideReady: boolean,
	slideFraction: number,
	slideSeconds: number
)
	visible = show
	local want = show and Controls.device() == "touch"
	if gui.Enabled ~= want then
		gui.Enabled = want
	end
	if not want then
		return
	end
	local packs = LootClient.get().healPacks
	local countText = tostring(packs)
	if healCount.Text ~= countText then
		healCount.Text = countText
		UiKit.pop(pieces.heal, 1.18)
	end
	pieces.heal.BackgroundTransparency = if packs > 0 then 0 else 0.5
	local feet = MoveState.get()
	sprintVeil.Size =
		UDim2.fromScale(1, if feet.wantsSprint or feet.locked then 1 - feet.stamina else 0)
	pieces.sprint.BackgroundTransparency = if feet.wantsSprint and feet.running then 0 else 0.35
	local chargeText = if feet.slideMax > 1 then tostring(feet.slideCharges) else ""
	if slideCount.Text ~= chargeText then
		slideCount.Text = chargeText
	end
	if slideReady and not wasSlideReady then
		UiKit.pop(pieces.slide, 1.18) -- ready again
	end
	wasSlideReady = slideReady
	slideDial.Size = UDim2.fromScale(1, if slideReady then 0 else 1 - slideFraction)
	local text = if slideReady then "" else tostring(math.ceil(slideSeconds))
	if slideText.Text ~= text then
		slideText.Text = text
	end
end

return TouchControls

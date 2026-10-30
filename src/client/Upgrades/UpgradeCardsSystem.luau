--!strict
-- The upgrade cards (piece 08): three cards in a row at the bottom centre, between the thumbs.
-- Look: carter's "Street Sticker" HUD style (cream card, thick navy outline, hard shadow, gold tile).
-- Screen space (agreed with the HUD): x 26%-74%, y 76%-96% of the safe area. DisplayOrder 20.
--
-- The client only shows what the server offers and asks for a pick: UpgradeChoose(offerId, index).
-- The server decides if it counts. Cards stay up while the match runs, never block movement
-- (nothing here sinks input except taps on the cards themselves), and a new offer ignores taps
-- for a moment so a tap meant for the old card cannot take the new one.
--   Touch / mouse: tap a card.  Keyboard: 1, 2, 3.  Controller: D-pad left, up, right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))

local UpgradeCardsSystem = {}
UpgradeCardsSystem.order = 200 -- after the HUD

local CREAM = Color3.fromHex("FFF4D6")
local NAVY = Color3.fromHex("14243A")
local GOLD = Color3.fromHex("FFC44D")
local CYAN = Color3.fromHex("36D9E8")
local CORAL = Color3.fromHex("F15B64")
local FONT = Enum.Font.FredokaOne

-- Placeholder labels for the icon tile until the original icon art exists (no asset ids invented).
local ICON_TEXT: { [string]: string } = {
	reload = "RLD",
	slide = "SLD",
	feet = "RUN",
	twin = "x2",
	fan = "x3",
	steady = "AIM",
	range = "FAR",
	boom = "BOOM",
	damage = "DMG",
}

local PAD_HINT = { "←", "↑", "→" } -- D-pad left, up, right pick card 1, 2, 3

local GAMEPAD_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.DPadLeft] = 1,
	[Enum.KeyCode.DPadUp] = 2,
	[Enum.KeyCode.DPadRight] = 3,
}

type Option = {
	id: string,
	name: string,
	description: string,
	icon: string,
	stacks: number,
	maxStacks: number,
	change: string?,
	kind: string?,
}
type Offer = { offerId: string, matchId: number, options: { Option } }

local gui: ScreenGui
local row: Frame
local toast: TextLabel
local waiting: TextLabel
local current: Offer? = nil
local cardButtons: { TextButton } = {}
local unlockedAt = 0
local busy = false
local ownId = ""

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

local function outline(parent: Instance, thickness: number)
	make(
		"UIStroke",
		{ Color = NAVY, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		parent
	)
end

local function clearCards()
	for _, child in row:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	cardButtons = {}
	current = nil
	busy = false
end

local function hideAll()
	clearCards()
	row.Visible = false
end

local function textLabel(props: { [string]: any }, parent: Instance): TextLabel
	local label: TextLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = NAVY,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
	}, parent)
	for key, value in props do
		(label :: any)[key] = value
	end
	make("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 8 }, label)
	return label
end

local function choose(index: number)
	local offer = current
	if offer == nil or busy or os.clock() < unlockedAt or offer.options[index] == nil then
		return
	end
	busy = true
	for i, button in cardButtons do
		button.BackgroundColor3 = if i == index then GOLD else CREAM
	end
	Net.send("UpgradeChoose", offer.offerId, index)
	-- If the server never answers (a rejected tap), let the player try again.
	task.delay(0.8, function()
		if current == offer then
			busy = false
			for _, button in cardButtons do
				button.BackgroundColor3 = CREAM
			end
		end
	end)
end

local function buildCard(option: Option, index: number, strokeSize: number)
	local slot = make("Frame", {
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.32, 0, 1, 0),
		LayoutOrder = index,
	}, row)

	make("Frame", { -- hard drop shadow
		Name = "Shadow",
		BackgroundColor3 = NAVY,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.new(0, strokeSize, 0, strokeSize * 1.4),
		BorderSizePixel = 0,
	}, slot)
	make("UICorner", { CornerRadius = UDim.new(0.18, 0) }, slot.Shadow)

	local card: TextButton = make("TextButton", {
		Name = "Card",
		BackgroundColor3 = CREAM,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, slot)
	make("UICorner", { CornerRadius = UDim.new(0.18, 0) }, card)
	outline(card, strokeSize)

	local accent = if option.kind == "move" then CYAN else GOLD
	local tile = make("Frame", {
		BackgroundColor3 = accent,
		Position = UDim2.fromScale(0.06, 0.08),
		Size = UDim2.fromScale(0.3, 0.36),
		BorderSizePixel = 0,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0.22, 0) }, tile)
	outline(tile, math.max(1, strokeSize * 0.6))
	local iconLabel = textLabel({
		Size = UDim2.fromScale(1, 1),
		Text = ICON_TEXT[option.icon] or "?",
		TextXAlignment = Enum.TextXAlignment.Center,
	}, tile)
	iconLabel.Name = "Icon"

	textLabel({
		Name = "Name",
		Position = UDim2.fromScale(0.4, 0.06),
		Size = UDim2.fromScale(0.56, 0.4),
		Text = string.upper(option.name),
	}, card)

	local change = textLabel({
		Name = "Change",
		Position = UDim2.fromScale(0.06, 0.5),
		Size = UDim2.fromScale(0.88, 0.26),
		Text = option.change or option.description,
		BackgroundTransparency = 0,
		BackgroundColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, change)

	-- Stack pips: filled = owned, gold = what this pick adds.
	local pips = make("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.06, 0.8),
		Size = UDim2.fromScale(0.5, 0.14),
	}, card)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 3),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, pips)
	for i = 1, option.maxStacks do
		local pip = make("Frame", {
			BackgroundColor3 = if i <= option.stacks
				then NAVY
				elseif i == option.stacks + 1 then GOLD
				else CREAM,
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
		}, pips)
		make("UIAspectRatio", { AspectRatio = 1 }, pip)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pip)
		outline(pip, 1.5)
	end

	-- A pad in hand shows its D-pad direction (left, up, right) instead of the number key.
	local padInUse = string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	if UserInputService.KeyboardEnabled or padInUse then
		local key = make("TextLabel", {
			Name = "Key",
			BackgroundColor3 = NAVY,
			TextColor3 = CREAM,
			Font = FONT,
			Text = if padInUse then PAD_HINT[index] else tostring(index),
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.92, 0.88),
			Size = UDim2.fromScale(0.16, 0.2),
		}, card)
		make("UIAspectRatio", { AspectRatio = 1 }, key)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, key)
	end

	card.Activated:Connect(function()
		choose(index)
	end)
	table.insert(cardButtons, card)

	-- Slide up into place.
	card.Position = UDim2.fromScale(0, 0.4)
	slot.Shadow.Position = UDim2.new(0, strokeSize, 0.4, strokeSize * 1.4)
	TweenService
		:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0, 0),
		})
		:Play()
	TweenService
		:Create(slot.Shadow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, strokeSize, 0, strokeSize * 1.4),
		})
		:Play()
end

local function showOffer(offer: Offer?)
	clearCards()
	if offer == nil or #offer.options == 0 then
		row.Visible = false
		return
	end
	current = offer
	unlockedAt = os.clock() + Config.Upgrades.selectionLockSeconds
	local width = gui.AbsoluteSize.X
	local strokeSize = math.max(2, math.round(width * 0.007))
	for i, option in offer.options do
		buildCard(option, i, strokeSize)
	end
	row.Visible = true
end

local function showToast(text: string)
	toast.Text = text
	toast.Visible = true
	local shown = text
	task.delay(1.6, function()
		if toast.Text == shown then
			toast.Visible = false
		end
	end)
end

function UpgradeCardsSystem.start()
	local player = Players.LocalPlayer
	ownId = Ids.player(player.UserId)

	gui = make("ScreenGui", {
		Name = "UpgradeCards",
		DisplayOrder = 20,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	}, player:WaitForChild("PlayerGui"))

	-- Bottom-centre zone shared with the HUD thread: x 26%-74%, y 76%-96%.
	row = make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromScale(0.48, 0.2),
		Visible = false,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.02, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	toast = textLabel({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromScale(0.4, 0.06),
		BackgroundTransparency = 0,
		BackgroundColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, toast)
	outline(toast, 2)

	waiting = textLabel({
		Name = "Waiting",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.26, 0.75),
		Size = UDim2.fromScale(0.1, 0.05),
		BackgroundTransparency = 0,
		BackgroundColor3 = CORAL,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, waiting)
	outline(waiting, 2)

	Net.on("UpgradeOffer", function(offer: Offer?)
		showOffer(offer)
	end)

	Net.on("UpgradeApplied", function(info: { upgradeId: string, stacks: number, text: string? })
		-- The server sends nothing more when no offer is waiting, so the picked cards close here;
		-- a queued next offer arrives right after this message and opens them again.
		hideAll()
		showToast(if info.text and info.text ~= "" then info.text else "Upgrade!")
	end)

	-- Offers waiting behind the one on screen (piece 07 sends XpState).
	Net.on("XpState", function(state: { pendingOffers: number }?)
		local extra = if state then state.pendingOffers - (if current then 1 else 0) else 0
		waiting.Visible = extra > 0
		waiting.Text = "+" .. extra
	end)

	-- Cards only live while fighting.
	Net.on("MatchState", function(state: { phase: string }?)
		if state == nil or (state.phase ~= "Active" and state.phase ~= "FinalPressure") then
			hideAll()
		end
	end)

	Net.on("Eliminated", function(info: { victimId: string }?)
		if info ~= nil and info.victimId == ownId then
			hideAll()
		end
	end)

	-- Shortcuts. When the controls door exists (piece 10) it owns the keys and the D-pad and sends
	-- the actions "upgrade1" to "upgrade3"; without it, read the keys here.
	local controlsFolder = script.Parent.Parent:FindFirstChild("Controls")
	local controlsModule = if controlsFolder then controlsFolder:FindFirstChild("Controls") else nil
	local okControls, Controls = false, nil :: any
	if controlsModule ~= nil and controlsModule:IsA("ModuleScript") then
		okControls, Controls = pcall(require, controlsModule)
	end
	if okControls and Controls ~= nil then
		Controls.Action:connect(function(name: string)
			local index = tonumber(string.match(name, "^upgrade(%d)$"))
			if index ~= nil and current ~= nil then
				choose(index)
			end
		end)
	else
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or current == nil then
				return
			end
			local index = table.find(Config.Upgrades.desktopKeys, input.KeyCode.Name)
				or GAMEPAD_KEYS[input.KeyCode]
			if index ~= nil then
				choose(index)
			end
		end)
	end
end

return UpgradeCardsSystem

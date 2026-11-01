--!strict
-- The UI kit. Every screen in the game is built from these, so everything looks the same:
-- chunky rounded cards, soft rims, a darker "lip" under each button that squashes when pressed.
-- All colours, fonts, sizes and times come from Theme.
--
-- Every builder takes ONE props table (all optional unless said) and returns the Instance(s) plus
-- a small control table. Common props: parent, name, position, size, anchor, layoutOrder, zIndex.
--
--   Components.screen(name, displayOrder, opts?) -> Screen   a ScreenGui + root frame in "virtual px"
--   Components.Label / Button / IconButton / Panel / Card / Pill / Bar / Toggle / Tabs /
--     ScrollList / Pips / CostButton / Badge / CoinIcon
--   Components.tween(inst, goal, info?)   a tween that cancels the previous one on the same property
--   Components.punch(inst, amount?)       quick scale pop      Components.shakeX(inst) wiggle sideways

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local Theme = require(script.Parent.Theme)
local Bridge = require(script.Parent.Bridge)

local Components = {}

export type Common = {
	parent: Instance?,
	name: string?,
	position: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}

-- ===== tiny building blocks =====
local function make(className: string, props: { [string]: any }): any
	local inst: any = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: UDim?): UICorner
	return make("UICorner", { CornerRadius = radius or Theme.radius.md, Parent = parent })
end

local function stroke(
	parent: Instance,
	color: Color3,
	thickness: number?,
	transparency: number?
): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or Theme.size.stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function textStroke(
	parent: Instance,
	color: Color3,
	thickness: number?,
	transparency: number?
): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Light-to-slightly-darker top-to-bottom tint on a frame (multiplies the frame's own colour).
local function sheen(parent: Instance, bottom: number?): UIGradient
	local b = bottom or 0.84
	return make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(b, b, b)),
		Rotation = 90,
		Parent = parent,
	})
end

local function common(props: Common, defaults: { [string]: any }): { [string]: any }
	local out = defaults
	out.Name = props.name or out.Name
	out.Position = props.position or out.Position or UDim2.new()
	out.Size = props.size or out.Size
	out.AnchorPoint = props.anchor or out.AnchorPoint or Vector2.zero
	out.LayoutOrder = props.layoutOrder or 0
	out.ZIndex = props.zIndex or 1
	out.Parent = props.parent
	return out
end

-- ===== motion helpers =====
local active: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

function Components.tween(inst: Instance, goal: { [string]: any }, info: TweenInfo?): Tween
	local per = active[inst]
	if per == nil then
		per = {}
		active[inst] = per
	end
	local mine = per :: { [string]: Tween }
	for prop in goal do
		local old = mine[prop]
		if old ~= nil then
			old:Cancel()
		end
	end
	local tween = TweenService:Create(inst, info or Theme.ease.normal, goal)
	for prop in goal do
		mine[prop] = tween
	end
	tween.Completed:Connect(function()
		for prop in goal do
			if mine[prop] == tween then
				mine[prop] = nil
			end
		end
	end)
	tween:Play()
	return tween
end

local PUNCH_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)

-- Quick "bump" of a GuiObject (grows a little, then back). Safe to spam.
function Components.punch(inst: GuiObject, amount: number?)
	local sc = inst:FindFirstChild("PunchScale")
	if sc == nil or not sc:IsA("UIScale") then
		sc = make("UIScale", { Name = "PunchScale", Parent = inst })
	end
	local scale = sc :: UIScale
	scale.Scale = 1
	Components.tween(scale, { Scale = 1 + (amount or 0.08) }, PUNCH_INFO)
end

local SHAKE_STEPS = { -7, 7, -5, 5, -2, 0 }
local shaking: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Wiggle sideways (for "can't afford"). `rest` is where it must end up; pass it when the thing may
-- be mid-tween (a button face that is still rising after a press), otherwise the current spot is
-- used. Do not use on children of a UIListLayout (the layout resets Position); Button.shake()
-- wiggles its inner face instead.
function Components.shakeX(inst: GuiObject, rest: UDim2?)
	if shaking[inst] then
		return
	end
	shaking[inst] = true
	local base = rest or inst.Position
	task.spawn(function()
		for _, dx in SHAKE_STEPS do
			if inst.Parent == nil then
				break
			end
			local t = TweenService:Create(
				inst,
				TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.new(
						base.X.Scale,
						base.X.Offset + dx,
						base.Y.Scale,
						base.Y.Offset
					),
				}
			)
			t:Play()
			t.Completed:Wait()
		end
		if inst.Parent ~= nil then
			inst.Position = base
		end
		shaking[inst] = nil
	end)
end

-- ===== screen =====
export type Screen = {
	gui: ScreenGui,
	root: Frame,
	size: Vector2, -- virtual size of root
	scale: number, -- the UIScale factor
	resized: any, -- Signal: fires after size/scale changed
	destroy: () -> (),
}

-- A ScreenGui (ResetOnSpawn off) with one root frame. root is sized in VIRTUAL px and carries the
-- UIScale, so children use plain pixel offsets and everything still ends up the right size on a
-- phone, a tablet or a 4K monitor. By default the gui stays inside the device safe area (notches).
--   opts.fullBleed = true  ignore device insets completely (splash screen)
--   opts.spill = true      stay inside the safe area but let things (a dim backdrop) draw past it
function Components.screen(
	name: string,
	displayOrder: number,
	opts: { fullBleed: boolean?, spill: boolean? }?
): Screen
	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local fullBleed = opts ~= nil and opts.fullBleed == true
	local spill = fullBleed or (opts ~= nil and opts.spill == true)
	pcall(function()
		local g: any = gui
		g.ScreenInsets = if fullBleed
			then Enum.ScreenInsets.None
			else Enum.ScreenInsets.DeviceSafeInsets
	end)
	if spill then
		pcall(function()
			local g: any = gui
			g.ClipToDeviceSafeArea = false
		end)
	end
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(800, 360),
		Parent = gui,
	})
	local uiScale = make("UIScale", { Name = "Scale", Parent = root })
	local screen: Screen = {
		gui = gui,
		root = root,
		size = Vector2.new(800, 360),
		scale = 1,
		resized = Signal.new(),
		destroy = function() end,
	}

	local function update()
		local abs = gui.AbsoluteSize
		if abs.X < 16 or abs.Y < 16 then
			local cam = workspace.CurrentCamera
			if cam == nil then
				return
			end
			abs = cam.ViewportSize
		end
		local s = Theme.scaleFor(abs.X, abs.Y)
		uiScale.Scale = s
		root.Size = UDim2.fromOffset(abs.X / s, abs.Y / s)
		screen.size = Vector2.new(abs.X / s, abs.Y / s)
		screen.scale = s
		screen.resized:fire()
	end
	local conn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	-- belt and braces: a rotated phone also changes the camera's viewport
	local cam = workspace.CurrentCamera
	local camConn = if cam
		then cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		else nil
	gui.Parent = playerGui
	update()

	screen.destroy = function()
		conn:Disconnect()
		if camConn then
			camConn:Disconnect()
		end
		gui:Destroy()
	end
	return screen
end

-- ===== Label =====
export type LabelProps = Common & {
	text: string?,
	textSize: number?, -- max size (text shrinks to fit); also the size when scaled = false
	font: Enum.Font?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	outline: Color3?, -- soft outline for text on busy backgrounds
	wrap: boolean?,
	scaled: boolean?, -- default true (TextScaled + size constraint)
}

function Components.Label(props: LabelProps): TextLabel
	local scaled = props.scaled ~= false
	local size = props.textSize or Theme.text.body
	local label = make(
		"TextLabel",
		common(props, {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Text = props.text or "",
			Font = props.font or Theme.font.bold,
			TextColor3 = props.color or Theme.color.charcoal,
			TextXAlignment = props.align or Enum.TextXAlignment.Center,
			TextYAlignment = props.valign or Enum.TextYAlignment.Center,
			TextWrapped = props.wrap == true,
			TextScaled = scaled,
			TextSize = size,
			RichText = false,
		})
	)
	if scaled then
		make(
			"UITextSizeConstraint",
			{ MaxTextSize = size, MinTextSize = Theme.text.min, Parent = label }
		)
	end
	if props.outline then
		textStroke(label, props.outline, 1.5, 0.35)
	end
	return label
end

-- ===== CoinIcon (a gold coin drawn from shapes: no asset ids) =====
function Components.CoinIcon(props: Common): Frame
	local coin = make(
		"Frame",
		common(props, {
			Name = "Coin",
			BackgroundColor3 = Theme.color.gold,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(24, 24),
		})
	)
	make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = coin })
	corner(coin, Theme.radius.full)
	stroke(coin, Theme.color.goldDark, 2)
	sheen(coin, 0.82)
	local ring = make("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = coin,
	})
	corner(ring, Theme.radius.full)
	stroke(ring, Theme.color.goldDark, 1.5, 0.25)
	local shine = make("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.16, 0.12),
		Size = UDim2.fromScale(0.2, 0.3),
		Rotation = 35,
		BackgroundColor3 = Theme.color.white,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = coin,
	})
	corner(shine, Theme.radius.full)
	return coin
end

-- ===== Button =====
export type ButtonProps = Common & {
	text: string?,
	icon: string?, -- emoji
	variant: string?, -- primary | secondary | good | gold | danger | neutral | dark
	textSize: number?,
	round: boolean?, -- circle
	flat: boolean?, -- no lip
	enabled: boolean?,
	sound: string?, -- Sfx name, default "click"
	silent: boolean?, -- no click sound / haptic / pop (hold buttons do their own)
	stack: boolean?, -- icon above text instead of beside it (big round buttons)
	onClick: (() -> ())?,
}

export type Button = {
	root: Frame,
	face: Frame, -- the visible face (moves down when pressed); parent pictures to it
	hit: TextButton, -- invisible, covers the WHOLE button box: this is what fingers touch
	label: TextLabel,
	icon: TextLabel,
	enabled: boolean,
	setText: (text: string) -> (),
	setIcon: (icon: string) -> (),
	setVariant: (name: string) -> (),
	setEnabled: (on: boolean) -> (),
	onClick: (fn: () -> ()) -> () -> (),
	onBlocked: (fn: () -> ()) -> () -> (),
	shake: () -> (),
	destroy: () -> (),
}

function Components.Button(props: ButtonProps): Button
	local lipPx = if props.flat then 0 else Theme.size.lip
	local round = props.round == true
	local variantName = props.variant or "primary"
	local look = Theme.variant[variantName] or Theme.variant.primary
	local enabled = props.enabled ~= false
	local radius = if round then Theme.radius.full else Theme.radius.md

	local root = make(
		"Frame",
		common(props, {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(120, Theme.size.touch),
		})
	)
	-- circles are drawn lip-px smaller than the box so they stay round
	local faceSize = if round then UDim2.new(1, -lipPx, 1, -lipPx) else UDim2.new(1, 0, 1, -lipPx)
	local faceX = if round then lipPx / 2 else 0
	local facePos = UDim2.fromOffset(faceX, 0)
	local pressedPos = UDim2.fromOffset(faceX, math.max(0, lipPx - 1))

	local lip = make("Frame", {
		Name = "Lip",
		Position = UDim2.fromOffset(faceX, lipPx),
		Size = faceSize,
		BackgroundColor3 = look.lip,
		BorderSizePixel = 0,
		Active = false,
		Parent = root,
	})
	corner(lip, radius)
	local lipStroke = stroke(lip, look.rim, 2)

	local face = make("Frame", {
		Name = "Face",
		Position = facePos,
		Size = faceSize,
		BackgroundColor3 = look.face,
		BorderSizePixel = 0,
		Active = false,
		Parent = root,
	})
	corner(face, radius)
	local faceStroke = stroke(face, look.rim, 2)
	sheen(face, 0.86)

	-- The hit box is the whole root (lip included), so a 44 px button really is 44 px under a
	-- finger. It sits above the face and draws nothing.
	local hit = make("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})

	local shine = make("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -16, 0.34, 0),
		BackgroundColor3 = Theme.color.white,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Active = false,
		Parent = face,
	})
	corner(shine, Theme.radius.full)

	local textSize = props.textSize or Theme.text.body
	local hasIcon = props.icon ~= nil and props.icon ~= ""
	local hasText = props.text ~= nil and props.text ~= ""
	local icon = make("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.font.bold,
		Text = props.icon or "",
		TextColor3 = look.text,
		TextScaled = true,
		Active = false,
		Parent = face,
	})
	make(
		"UITextSizeConstraint",
		{ MaxTextSize = math.max(textSize + 8, 30), MinTextSize = Theme.text.min, Parent = icon }
	)
	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.font.title,
		Text = props.text or "",
		TextColor3 = look.text,
		TextScaled = true,
		Active = false,
		Parent = face,
	})
	make(
		"UITextSizeConstraint",
		{ MaxTextSize = textSize, MinTextSize = Theme.text.min, Parent = label }
	)
	local labelStroke = textStroke(label, look.textStroke, 1.5, 0.45)

	local function layoutContent()
		local both = hasIcon and hasText
		icon.Visible = hasIcon
		label.Visible = hasText
		if both and props.stack then
			icon.Position = UDim2.new(0.5, 0, 0.36, 0)
			icon.Size = UDim2.fromScale(0.5, 0.44)
			label.Position = UDim2.new(0.5, 0, 0.74, 0)
			label.Size = UDim2.fromScale(0.74, 0.26)
		elseif both then
			icon.Position = UDim2.new(0, 22, 0.5, -1)
			icon.Size = UDim2.new(0, 28, 0.62, 0)
			label.Position = UDim2.new(0.5, 18, 0.5, -1)
			label.Size = UDim2.new(1, -52, 0.7, 0)
		elseif hasIcon then
			icon.Position = UDim2.new(0.5, 0, 0.5, -1)
			icon.Size = UDim2.fromScale(0.66, 0.66)
		else
			label.Position = UDim2.new(0.5, 0, 0.5, -1)
			label.Size = UDim2.new(1, -14, 0.72, 0)
		end
	end
	layoutContent()

	local clicked = Signal.new()
	local blocked = Signal.new()
	local self: Button
	local pressed = false
	local hovered = false
	local conns: { RBXScriptConnection } = {}

	local function paint()
		local shown = if enabled then look else Theme.variant.disabled
		local face3 = shown.face
		if enabled and hovered and not pressed then
			face3 = shown.face:Lerp(Theme.color.white, 0.14)
		end
		Components.tween(face, { BackgroundColor3 = face3 }, Theme.ease.fast)
		lip.BackgroundColor3 = shown.lip
		lipStroke.Color = shown.rim
		faceStroke.Color = shown.rim
		icon.TextColor3 = shown.text
		label.TextColor3 = shown.text
		labelStroke.Color = shown.textStroke
		icon.TextTransparency = if enabled then 0 else 0.1
	end

	local function setPressed(on: boolean)
		if pressed == on then
			return
		end
		pressed = on
		Components.tween(
			face,
			{ Position = if on then pressedPos else facePos },
			TweenInfo.new(Theme.duration.instant)
		)
		paint()
	end

	table.insert(
		conns,
		hit.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if
				(t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
				and input.UserInputState == Enum.UserInputState.Begin
			then
				setPressed(true)
			end
		end)
	)
	table.insert(
		conns,
		hit.InputEnded:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				setPressed(false)
			end
		end)
	)
	table.insert(
		conns,
		hit.MouseEnter:Connect(function()
			hovered = true
			paint()
		end)
	)
	table.insert(
		conns,
		hit.MouseLeave:Connect(function()
			hovered = false
			setPressed(false)
			paint()
		end)
	)
	table.insert(
		conns,
		hit.Activated:Connect(function()
			if not enabled then
				Bridge.play("error")
				self.shake()
				blocked:fire()
				return
			end
			if props.silent ~= true then
				Bridge.play(props.sound or "click")
				Bridge.tap(0.25)
				Components.punch(root, 0.06)
			end
			clicked:fire()
		end)
	)

	self = {
		root = root,
		face = face,
		hit = hit,
		label = label,
		icon = icon,
		enabled = enabled,
		setText = function(text: string)
			label.Text = text
			hasText = text ~= ""
			layoutContent()
		end,
		setIcon = function(glyph: string)
			icon.Text = glyph
			hasIcon = glyph ~= ""
			layoutContent()
		end,
		setVariant = function(name: string)
			look = Theme.variant[name] or Theme.variant.primary
			paint()
		end,
		setEnabled = function(on: boolean)
			enabled = on
			self.enabled = on
			paint()
		end,
		onClick = function(fn: () -> ()): () -> ()
			local c = clicked:connect(fn)
			return function()
				c:disconnect()
			end
		end,
		onBlocked = function(fn: () -> ()): () -> ()
			local c = blocked:connect(fn)
			return function()
				c:disconnect()
			end
		end,
		shake = function()
			-- always settle at the resting spot, even if the press tween is still running
			Components.shakeX(face, facePos)
		end,
		destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			table.clear(conns)
			root:Destroy()
		end,
	}
	if props.onClick then
		self.onClick(props.onClick)
	end
	paint()
	return self
end

-- A square emoji button (menu, close, small actions).
export type IconButtonProps = Common & {
	icon: string,
	variant: string?,
	round: boolean?,
	enabled: boolean?,
	onClick: (() -> ())?,
}

function Components.IconButton(props: IconButtonProps): Button
	local p: ButtonProps = {
		parent = props.parent,
		name = props.name,
		position = props.position,
		size = props.size or UDim2.fromOffset(Theme.size.touch, Theme.size.touch),
		anchor = props.anchor,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		icon = props.icon,
		variant = props.variant or "neutral",
		round = props.round,
		enabled = props.enabled,
		onClick = props.onClick,
	}
	return Components.Button(p)
end

-- ===== Badge (red notification dot) =====
export type BadgeProps = {
	parent: Instance,
	size: number?,
	count: number?,
}

export type Badge = {
	root: Frame,
	set: (visible: boolean, count: number?) -> (),
	destroy: () -> (),
}

-- Sits on the top-right corner of its parent. When it lights it pops and pulses three times, then
-- stays still (a dot that never stops moving is noise, not news).
local BADGE_PULSES = 2 -- extra repeats after the first pulse

function Components.Badge(props: BadgeProps): Badge
	local px = props.size or 16
	local dot = make("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 1, 0, -1),
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = Theme.color.red,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Active = false,
		Parent = props.parent,
	})
	corner(dot, Theme.radius.full)
	stroke(dot, Theme.color.white, 2)
	local num = Components.Label({
		parent = dot,
		text = "",
		textSize = Theme.text.min,
		font = Theme.font.title,
		color = Theme.color.white,
		zIndex = 21,
	})
	local scale = make("UIScale", { Name = "Pop", Scale = 1, Parent = dot })
	local pulse: Tween? = nil
	local shown = false

	local function stopPulse()
		if pulse then
			pulse:Cancel()
			pulse = nil
		end
		scale.Scale = 1
	end

	local self: Badge
	self = {
		root = dot,
		set = function(visible: boolean, count: number?)
			local text = if count ~= nil and count > 1
				then (if count > 9 then "9+" else tostring(count))
				else ""
			num.Text = text
			if visible == shown then
				return
			end
			shown = visible
			if visible then
				dot.Visible = true
				scale.Scale = 0
				Components.tween(scale, { Scale = 1 }, Theme.ease.pop).Completed:Connect(function()
					if shown then
						stopPulse() -- a quick off/on must never leave two pulses running
						local t = TweenService:Create(
							scale,
							TweenInfo.new(
								0.7,
								Enum.EasingStyle.Sine,
								Enum.EasingDirection.InOut,
								BADGE_PULSES, -- a few pulses, then the dot stays still
								true
							),
							{ Scale = 1.18 }
						)
						pulse = t
						t:Play()
					end
				end)
			else
				stopPulse()
				dot.Visible = false
			end
		end,
		destroy = function()
			stopPulse()
			dot:Destroy()
		end,
	}
	return self
end

-- ===== Card =====
export type CardProps = Common & {
	color: Color3?,
	padding: number?,
}

function Components.Card(props: CardProps): Frame
	local card = make(
		"Frame",
		common(props, {
			Size = UDim2.new(1, 0, 0, 80),
			BackgroundColor3 = props.color or Theme.color.creamLight,
			BorderSizePixel = 0,
		})
	)
	corner(card, Theme.radius.md)
	stroke(card, Theme.color.parchmentLine, 2)
	if props.padding then
		make("UIPadding", {
			PaddingTop = UDim.new(0, props.padding),
			PaddingBottom = UDim.new(0, props.padding),
			PaddingLeft = UDim.new(0, props.padding),
			PaddingRight = UDim.new(0, props.padding),
			Parent = card,
		})
	end
	return card
end

-- ===== Pill =====
export type PillProps = Common & {
	text: string?,
	icon: string?, -- emoji, or "@coin" for the drawn gold coin
	fill: Color3?,
	fillTransparency: number?,
	textColor: Color3?,
	textSize: number?,
	align: Enum.TextXAlignment?,
	bordered: boolean?,
}

export type Pill = {
	root: Frame,
	label: TextLabel,
	icon: GuiObject?,
	setText: (text: string) -> (),
	setFill: (color: Color3, transparency: number?) -> (),
	setTextColor: (color: Color3) -> (),
}

function Components.Pill(props: PillProps): Pill
	local glass = Theme.glass
	local pill = make(
		"Frame",
		common(props, {
			Size = UDim2.fromOffset(100, 28),
			BackgroundColor3 = props.fill or glass.color,
			BackgroundTransparency = if props.fill
				then (props.fillTransparency or 0)
				else glass.transparency,
			BorderSizePixel = 0,
		})
	)
	corner(pill, Theme.radius.full)
	if props.bordered ~= false then
		stroke(pill, glass.strokeColor, 1.5, glass.strokeTransparency)
	end
	local textX = 10
	local iconObj: GuiObject? = nil
	if props.icon and props.icon ~= "" then
		if props.icon == "@coin" then
			iconObj = Components.CoinIcon({
				parent = pill,
				position = UDim2.new(0, 6, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				size = UDim2.fromOffset(20, 20),
				zIndex = 2,
			})
			textX = 6 + 20 + 6
		else
			local glyph = make("TextLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(0, 22, 0.8, 0),
				Font = Theme.font.bold,
				Text = props.icon,
				TextColor3 = props.textColor or Theme.color.white,
				TextScaled = true,
				Active = false,
				Parent = pill,
			})
			make(
				"UITextSizeConstraint",
				{ MaxTextSize = Theme.text.icon, MinTextSize = Theme.text.min, Parent = glyph }
			)
			iconObj = glyph
			textX = 6 + 24
		end
	end
	local label = Components.Label({
		parent = pill,
		name = "Text",
		text = props.text or "",
		textSize = props.textSize or Theme.text.small,
		font = Theme.font.title,
		color = props.textColor or Theme.color.white,
		align = props.align
			or (if iconObj then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center),
		position = UDim2.fromOffset(textX, 0),
		size = UDim2.new(1, -(textX + 8), 1, 0),
		zIndex = 2,
	})
	return {
		root = pill,
		label = label,
		icon = iconObj,
		setText = function(text: string)
			label.Text = text
		end,
		setFill = function(color: Color3, transparency: number?)
			pill.BackgroundColor3 = color
			pill.BackgroundTransparency = transparency or 0
		end,
		setTextColor = function(color: Color3)
			label.TextColor3 = color
		end,
	}
end

-- ===== Bar =====
export type BarProps = Common & {
	fill: Color3?,
	track: Color3?,
	text: string?,
	textSize: number?,
	ticks: { number }?, -- 0..1 positions for little milestone marks
}

export type Bar = {
	root: Frame,
	fill: Frame,
	label: TextLabel,
	value: number,
	set: (fraction: number, animate: boolean?) -> (),
	setColor: (color: Color3) -> (),
	setText: (text: string) -> (),
	flash: () -> (),
	markTick: (index: number, reached: boolean) -> (),
}

function Components.Bar(props: BarProps): Bar
	local track = make(
		"Frame",
		common(props, {
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundColor3 = props.track or Theme.color.ink,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		})
	)
	corner(track, Theme.radius.full)
	stroke(track, Theme.color.white, 1.5, 0.7)
	local inner = make("Frame", {
		Name = "Inner",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = track,
	})
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.fill or Theme.color.lava,
		BorderSizePixel = 0,
		Visible = false,
		Parent = inner,
	})
	corner(fill, Theme.radius.full)
	make("UISizeConstraint", { MinSize = Vector2.new(10, 0), Parent = fill })
	sheen(fill, 0.78)
	local shine = make("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.new(1, -8, 0.3, 0),
		BackgroundColor3 = Theme.color.white,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = fill,
	})
	corner(shine, Theme.radius.full)
	local flashFrame = make("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = fill,
	})
	corner(flashFrame, Theme.radius.full)

	local tickFrames: { Frame } = {}
	for i, t in props.ticks or {} do
		local tick = make("Frame", {
			Name = "Tick" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(math.clamp(t, 0, 1), 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Theme.color.white,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = inner,
		})
		tickFrames[i] = tick
	end

	local label = Components.Label({
		parent = track,
		name = "Text",
		text = props.text or "",
		textSize = props.textSize or Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.ink,
		zIndex = 6,
	})
	label.Visible = props.text ~= nil

	local self: Bar
	self = {
		root = track,
		fill = fill,
		label = label,
		value = 0,
		set = function(fraction: number, animate: boolean?)
			local f = if fraction == fraction then math.clamp(fraction, 0, 1) else 0
			self.value = f
			fill.Visible = f > 0.002
			local goal = UDim2.fromScale(f, 1)
			if animate == false then
				fill.Size = goal
			else
				Components.tween(fill, { Size = goal }, Theme.ease.slow)
			end
		end,
		setColor = function(color: Color3)
			Components.tween(fill, { BackgroundColor3 = color }, Theme.ease.normal)
		end,
		setText = function(text: string)
			label.Text = text
			label.Visible = text ~= ""
		end,
		flash = function()
			flashFrame.BackgroundTransparency = 0.35
			Components.tween(flashFrame, { BackgroundTransparency = 1 }, Theme.ease.slow)
		end,
		markTick = function(index: number, reached: boolean)
			local tick = tickFrames[index]
			if tick then
				tick.BackgroundColor3 = if reached then Theme.color.gold else Theme.color.white
				tick.BackgroundTransparency = if reached then 0 else 0.4
			end
		end,
	}
	return self
end

-- ===== Toggle =====
export type ToggleProps = Common & {
	value: boolean?,
	label: string?,
	onChanged: ((value: boolean) -> ())?,
}

export type Toggle = {
	root: TextButton,
	get: () -> boolean,
	set: (value: boolean, silent: boolean?) -> (),
	onChanged: (fn: (value: boolean) -> ()) -> () -> (),
}

function Components.Toggle(props: ToggleProps): Toggle
	local row = make(
		"TextButton",
		common(props, {
			Size = UDim2.new(1, 0, 0, Theme.size.touch),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			BorderSizePixel = 0,
		})
	)
	if props.label then
		Components.Label({
			parent = row,
			text = props.label,
			textSize = Theme.text.body,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			size = UDim2.new(1, -72, 1, 0),
		})
	end
	local track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(58, 32),
		BackgroundColor3 = Theme.color.grey,
		BorderSizePixel = 0,
		Active = false,
		Parent = row,
	})
	corner(track, Theme.radius.full)
	local trackStroke = stroke(track, Theme.color.greyDark, 2)
	local knob = make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.color.white,
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(knob, Theme.radius.full)
	stroke(knob, Theme.color.greyDeep, 1.5, 0.5)

	local value = props.value == true
	local changed = Signal.new()
	local function paint(animate: boolean)
		local posGoal = if value then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		local colorGoal = if value then Theme.color.green else Theme.color.grey
		trackStroke.Color = if value then Theme.color.greenDeep else Theme.color.greyDark
		if animate then
			Components.tween(knob, { Position = posGoal }, Theme.ease.fast)
			Components.tween(track, { BackgroundColor3 = colorGoal }, Theme.ease.fast)
		else
			knob.Position = posGoal
			track.BackgroundColor3 = colorGoal
		end
	end
	paint(false)

	local self: Toggle
	self = {
		root = row,
		get = function()
			return value
		end,
		set = function(v: boolean, silent: boolean?)
			if v == value then
				return
			end
			value = v
			paint(true)
			if silent ~= true then
				changed:fire(value)
			end
		end,
		onChanged = function(fn: (v: boolean) -> ()): () -> ()
			local c = changed:connect(fn)
			return function()
				c:disconnect()
			end
		end,
	}
	row.Activated:Connect(function()
		Bridge.play("click")
		Bridge.tap(0.2)
		self.set(not value)
	end)
	if props.onChanged then
		self.onChanged(props.onChanged)
	end
	return self
end

-- ===== Tabs =====
export type TabDef = { id: string, text: string?, icon: string? }
export type TabsProps = Common & {
	tabs: { TabDef },
	selected: string?,
	onSelect: ((id: string) -> ())?,
}

export type Tabs = {
	root: Frame,
	select: (id: string, silent: boolean?) -> (),
	selected: () -> string,
	setBadge: (id: string, on: boolean) -> (),
	onSelect: (fn: (id: string) -> ()) -> () -> (),
}

function Components.Tabs(props: TabsProps): Tabs
	local bar = make(
		"Frame",
		common(props, {
			Size = UDim2.new(1, 0, 0, Theme.size.touch),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
	)
	local count = math.max(1, #props.tabs)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.size.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	local buttons: { [string]: Button } = {}
	local badges: { [string]: Badge } = {}
	local current = props.selected or (if props.tabs[1] then props.tabs[1].id else "")
	local changed = Signal.new()

	local function paint()
		for id, b in buttons do
			b.setVariant(if id == current then "secondary" else "neutral")
		end
	end

	local self: Tabs
	for i, def in props.tabs do
		local b = Components.Button({
			parent = bar,
			name = "Tab_" .. def.id,
			text = def.text,
			icon = def.icon,
			size = UDim2.new(1 / count, -Theme.size.gap * (count - 1) / count, 1, 0),
			layoutOrder = i,
			variant = "neutral",
			textSize = Theme.text.body,
		})
		buttons[def.id] = b
		badges[def.id] = Components.Badge({ parent = b.root })
		b.onClick(function()
			self.select(def.id)
		end)
	end
	paint()

	self = {
		root = bar,
		select = function(id: string, silent: boolean?)
			if buttons[id] == nil then
				return
			end
			local was = current
			current = id
			paint()
			if silent ~= true and was ~= id then
				changed:fire(id)
			end
		end,
		selected = function()
			return current
		end,
		setBadge = function(id: string, on: boolean)
			local badge = badges[id]
			if badge then
				badge.set(on)
			end
		end,
		onSelect = function(fn: (id: string) -> ()): () -> ()
			local c = changed:connect(fn)
			return function()
				c:disconnect()
			end
		end,
	}
	if props.onSelect then
		self.onSelect(props.onSelect)
	end
	return self
end

-- ===== ScrollList =====
export type ScrollListProps = Common & {
	gap: number?,
	padding: number?,
	horizontal: boolean?,
}

export type ScrollList = {
	root: ScrollingFrame, -- parent your rows/cards to this
	layout: UIListLayout,
}

function Components.ScrollList(props: ScrollListProps): ScrollList
	local horizontal = props.horizontal == true
	local scroll = make(
		"ScrollingFrame",
		common(props, {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
			ScrollingDirection = if horizontal
				then Enum.ScrollingDirection.X
				else Enum.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = Theme.color.charcoalSoft,
			ScrollBarImageTransparency = 0.4,
			ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
			VerticalScrollBarInset = Enum.ScrollBarInset.None,
			ClipsDescendants = true,
		})
	)
	local pad = props.padding or 4
	make("UIPadding", {
		PaddingTop = UDim.new(0, pad),
		PaddingBottom = UDim.new(0, pad),
		PaddingLeft = UDim.new(0, pad),
		PaddingRight = UDim.new(0, pad + (if horizontal then 0 else 6)),
		Parent = scroll,
	})
	local layout = make("UIListLayout", {
		FillDirection = if horizontal
			then Enum.FillDirection.Horizontal
			else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, props.gap or Theme.size.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	return { root = scroll, layout = layout }
end

-- ===== Pips (level dots) =====
export type PipsProps = Common & {
	total: number,
	filled: number?,
	color: Color3?,
}

export type Pips = {
	root: Frame,
	set: (filled: number, total: number?) -> (),
}

function Components.Pips(props: PipsProps): Pips
	local row = make(
		"Frame",
		common(props, {
			Size = UDim2.new(1, 0, 0, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
	)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})
	local onColor = props.color or Theme.color.lava
	local pips: { Frame } = {}
	local total = 0

	local function build(n: number)
		for _, p in pips do
			p:Destroy()
		end
		table.clear(pips)
		total = n
		for i = 1, n do
			local p = make("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.new(1 / n, -2 * (n - 1) / n, 1, 0),
				BackgroundColor3 = Theme.color.creamDark,
				BorderSizePixel = 0,
				Parent = row,
			})
			corner(p, UDim.new(0, 3))
			pips[i] = p
		end
	end
	build(math.max(1, props.total))

	local function set(filled: number, newTotal: number?)
		if newTotal ~= nil and newTotal ~= total and newTotal >= 1 then
			build(newTotal)
		end
		for i, p in pips do
			p.BackgroundColor3 = if i <= filled then onColor else Theme.color.creamDark
		end
	end
	set(props.filled or 0)
	return { root = row, set = set }
end

-- ===== CostButton =====
export type CostButtonProps = Common & {
	price: number?,
	affordable: boolean?,
	currency: string?, -- "coins" (default) or "sparks"
	label: string?, -- shown instead of a price: "OWNED", "MAXED"
	textSize: number?,
	onBuy: (() -> ())?,
	onBlocked: (() -> ())?,
}

export type CostButton = {
	button: Button,
	root: Frame,
	-- price nil = nothing to buy (shows `label`, greyed); affordable false = greyed + shakes on tap
	set: (price: number?, affordable: boolean, label: string?) -> (),
	onBuy: (fn: () -> ()) -> () -> (),
	onBlocked: (fn: () -> ()) -> () -> (),
}

function Components.CostButton(props: CostButtonProps): CostButton
	local currency = props.currency or "coins"
	local button = Components.Button({
		parent = props.parent,
		name = props.name or "CostButton",
		position = props.position,
		size = props.size or UDim2.fromOffset(120, Theme.size.touch),
		anchor = props.anchor,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		variant = "good",
		text = "",
		textSize = props.textSize or Theme.text.body,
	})
	-- price = drawn coin (or a sparkle for Sparks) + number, centred as one group
	local group = make("Frame", {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -1),
		Size = UDim2.new(1, -12, 0.72, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Parent = button.face,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = group,
	})
	local currencyIcon: GuiObject
	if currency == "sparks" then
		local spark = Components.Label({
			parent = group,
			text = "✨",
			textSize = Theme.text.icon,
			size = UDim2.fromOffset(22, 22),
			layoutOrder = 1,
		})
		currencyIcon = spark
	else
		currencyIcon = Components.CoinIcon({
			parent = group,
			size = UDim2.fromOffset(22, 22),
			layoutOrder = 1,
		})
	end
	-- a fixed size (not scaled) label that grows with its text, so "35" and "1.2M" both sit in
	-- the middle next to the coin (prices are short: Theme.fmt gives at most ~6 characters)
	local priceLabel = Components.Label({
		parent = group,
		name = "Amount",
		text = "",
		textSize = props.textSize or Theme.text.body,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.greenInk,
		size = UDim2.new(0, 0, 1, 0),
		align = Enum.TextXAlignment.Left,
		layoutOrder = 2,
		scaled = false,
	})
	priceLabel.AutomaticSize = Enum.AutomaticSize.X
	-- only used while it shows a word ("MAXED") in TextScaled mode
	make("UITextSizeConstraint", {
		MaxTextSize = props.textSize or Theme.text.body,
		MinTextSize = Theme.text.min,
		Parent = priceLabel,
	})
	local priceStroke = priceLabel:FindFirstChildOfClass("UIStroke")
	local function paintPrice(color: Color3, outline: Color3)
		priceLabel.TextColor3 = color
		if priceStroke then
			priceStroke.Color = outline
		end
	end

	local blockedSignal = Signal.new()
	local buySignal = Signal.new()
	button.onClick(function()
		buySignal:fire()
	end)
	button.onBlocked(function()
		blockedSignal:fire()
	end)

	local self: CostButton
	self = {
		button = button,
		root = button.root,
		set = function(price: number?, affordable: boolean, label: string?)
			if price == nil then
				currencyIcon.Visible = false
				priceLabel.AutomaticSize = Enum.AutomaticSize.None
				priceLabel.TextScaled = true
				priceLabel.Size = UDim2.fromScale(1, 1)
				priceLabel.TextXAlignment = Enum.TextXAlignment.Center
				priceLabel.Text = label or ""
				paintPrice(Theme.variant.disabled.text, Theme.variant.disabled.textStroke)
				button.setVariant("disabled")
				button.setEnabled(false)
				return
			end
			currencyIcon.Visible = true
			priceLabel.TextScaled = false
			priceLabel.Size = UDim2.new(0, 0, 1, 0)
			priceLabel.AutomaticSize = Enum.AutomaticSize.X
			priceLabel.TextXAlignment = Enum.TextXAlignment.Left
			priceLabel.Text = Theme.fmt(price)
			if affordable then
				button.setVariant("good")
				button.setEnabled(true)
				paintPrice(Theme.color.white, Theme.color.greenInk)
			else
				button.setVariant("disabled")
				button.setEnabled(false)
				paintPrice(Theme.variant.disabled.text, Theme.variant.disabled.textStroke)
			end
		end,
		onBuy = function(fn: () -> ()): () -> ()
			local c = buySignal:connect(fn)
			return function()
				c:disconnect()
			end
		end,
		onBlocked = function(fn: () -> ()): () -> ()
			local c = blockedSignal:connect(fn)
			return function()
				c:disconnect()
			end
		end,
	}
	if props.onBuy then
		self.onBuy(props.onBuy)
	end
	if props.onBlocked then
		self.onBlocked(props.onBlocked)
	end
	self.set(props.price, props.affordable == true, props.label)
	return self
end

-- ===== Panel (the big modal frame; PanelHost fills `body`) =====
export type PanelProps = Common & {
	title: string,
	icon: string?,
	onClose: (() -> ())?,
}

export type Panel = {
	root: Frame,
	body: Frame,
	titleLabel: TextLabel,
	close: Button,
	setTitle: (text: string) -> (),
	-- slimmer title bar and padding on short screens (PanelHost calls it from the panel height)
	setCompact: (compact: boolean) -> (),
	-- a one-line message strip under the title bar (toasts while a panel is open)
	notify: (text: string, kind: string?) -> (),
}

local NOTICE_H = 30
local NOTICE_SECONDS = 2.6

function Components.Panel(props: PanelProps): Panel
	local holder = make(
		"Frame",
		common(props, {
			Size = UDim2.fromOffset(520, 320),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
	)
	-- soft drop shadow
	local shadow = make("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.ink,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = holder,
	})
	corner(shadow, Theme.radius.lg)

	local card = make("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.cream,
		BorderSizePixel = 0,
		Parent = holder,
	})
	corner(card, Theme.radius.lg)
	stroke(card, Theme.color.charcoal, Theme.size.strokeThick)
	card.Active = true -- swallow taps so they never fall through to the backdrop behind

	local barH = Theme.size.titleBar
	local barColor = Theme.color.lavaButton
	local bar = make("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, barH),
		BackgroundColor3 = barColor,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = card,
	})
	corner(bar, Theme.radius.lg)
	-- square off the bar's bottom corners
	make("Frame", {
		Name = "BarFill",
		Position = UDim2.new(0, 0, 1, -Theme.radius.lg.Offset),
		Size = UDim2.new(1, 0, 0, Theme.radius.lg.Offset),
		BackgroundColor3 = barColor,
		BorderSizePixel = 0,
		Parent = bar,
	})
	make("Frame", {
		Name = "BarLine",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Theme.color.lavaDeep,
		BorderSizePixel = 0,
		Parent = bar,
	})
	local closeSize = Theme.size.closeButton
	if props.icon and props.icon ~= "" then
		Components.Label({
			parent = bar,
			name = "TitleIcon",
			text = props.icon,
			textSize = Theme.text.emoji,
			position = UDim2.fromOffset(10, 0),
			size = UDim2.new(0, 38, 1, -4),
		})
	end
	local titleX = if props.icon and props.icon ~= "" then 52 else 16
	local titleLabel = Components.Label({
		parent = bar,
		name = "Title",
		text = props.title,
		textSize = Theme.text.title,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.lavaInk,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(titleX, 0),
		size = UDim2.new(1, -(titleX + closeSize + 14), 1, -4),
	})

	local close = Components.Button({
		parent = bar,
		name = "Close",
		variant = "danger",
		round = true,
		size = UDim2.fromOffset(closeSize, closeSize),
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -8, 0.5, -1),
		sound = "click",
	})
	-- the X, drawn from two bars (no font needed)
	for i, rot in { 45, -45 } do
		local arm = make("Frame", {
			Name = "Arm" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.5, 0, 0, 5),
			Rotation = rot,
			BackgroundColor3 = Theme.color.white,
			BorderSizePixel = 0,
			Active = false,
			Parent = close.face,
		})
		corner(arm, Theme.radius.full)
	end
	if props.onClose then
		close.onClick(props.onClose)
	end

	local body = make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, barH),
		Size = UDim2.new(1, 0, 1, -barH),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = card,
	})
	local bodyPad = make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = body,
	})

	-- the notice strip slides out from under the title bar, over the top of the body
	local notice = make("Frame", {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, barH - NOTICE_H),
		Size = UDim2.new(1, -24, 0, NOTICE_H),
		BackgroundColor3 = Theme.kind.info.fill,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Active = false,
		Parent = card,
	})
	corner(notice, Theme.radius.md)
	local noticeStroke = stroke(notice, Theme.kind.info.accent, 2)
	local noticeText = Components.Label({
		parent = notice,
		name = "Text",
		text = "",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.kind.info.text,
		position = UDim2.fromOffset(8, 0),
		size = UDim2.new(1, -16, 1, 0),
		zIndex = 5,
	})
	local noticeToken = 0

	local self: Panel
	self = {
		root = holder,
		body = body,
		titleLabel = titleLabel,
		close = close,
		setTitle = function(text: string)
			titleLabel.Text = text
		end,
		setCompact = function(compact: boolean)
			barH = if compact then Theme.size.titleBarShort else Theme.size.titleBar
			local x = if compact then Theme.size.touch else Theme.size.closeButton
			bar.Size = UDim2.new(1, 0, 0, barH)
			close.root.Size = UDim2.fromOffset(x, x)
			body.Position = UDim2.fromOffset(0, barH)
			body.Size = UDim2.new(1, 0, 1, -barH)
			local v = if compact then 6 else 10
			bodyPad.PaddingTop = UDim.new(0, v)
			bodyPad.PaddingBottom = UDim.new(0, v)
			if not notice.Visible then
				notice.Position = UDim2.new(0.5, 0, 0, barH - NOTICE_H)
			end
		end,
		notify = function(text: string, kind: string?)
			local look = Theme.kind[kind or "info"] or Theme.kind.info
			notice.BackgroundColor3 = look.fill
			noticeStroke.Color = look.accent
			noticeText.TextColor3 = look.text
			noticeText.Text = text
			noticeToken += 1
			local mine = noticeToken
			notice.Visible = true
			Components.tween(notice, { Position = UDim2.new(0.5, 0, 0, barH + 4) }, Theme.ease.pop)
			task.delay(NOTICE_SECONDS, function()
				if mine ~= noticeToken or notice.Parent == nil then
					return
				end
				local t = Components.tween(
					notice,
					{ Position = UDim2.new(0.5, 0, 0, barH - NOTICE_H) },
					Theme.ease.normal
				)
				t.Completed:Connect(function()
					if mine == noticeToken then
						notice.Visible = false
					end
				end)
			end)
		end,
	}
	return self
end
return Components

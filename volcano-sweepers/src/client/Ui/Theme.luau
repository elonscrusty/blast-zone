--!strict
-- The one place that says how the game looks. No other UI file may use a raw colour, font,
-- corner size or duration: ask Theme.
--
--   Theme.color.*         Color3 palette (warm volcano: cream cards, charcoal text, lava orange,
--                         teal second colour, gold coins, green = good)
--   Theme.variant.*       button looks: face colour, bottom "lip" colour, rim colour, text colour
--   Theme.font.*          Enum.Font choices
--   Theme.text.*          text sizes (virtual px; TextScaled labels use these as the MAX size)
--   Theme.radius.*        UDim corner radii        Theme.size.*  spacing / stroke / touch size
--   Theme.duration.*      tween times (seconds)    Theme.ease.*  TweenInfo presets
--   Theme.DisplayOrder    HUD 10, Banner 12, Toasts 14, Panels 20, Overlay 40 (an open panel
--                         sits above the HUD, the banner and the toasts; toasts for an open
--                         panel are shown inside it by PanelHost.notify)
--   Theme.scale()         UIScale factor for the current screen;  Theme.scaleFor(w, h)
--   Theme.fmt(n)          1.2K / 3.4M number text
--   Theme.topInset()      height of Roblox's top bar in real px

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)

local Theme = {}

-- ===== palette (hex in one table, Color3 built from it) =====
local hex = {
	cream = "#FFF4DC",
	creamLight = "#FFFBF0",
	creamDark = "#F1DDB2",
	parchmentLine = "#E2C78F",
	charcoal = "#2B2430",
	charcoalSoft = "#6A5E70",
	ink = "#1B1220",
	white = "#FFFFFF",
	lava = "#FF7A2F",
	lavaButton = "#D9561A", -- button faces / title bar: white text reads at 4:1 (lava is 2.6:1)
	lavaDark = "#C9501A",
	lavaDeep = "#8F3510",
	lavaInk = "#5E2209",
	red = "#E8412C",
	redDark = "#A92A1B",
	teal = "#1FB5A8",
	tealDark = "#138A82",
	tealDeep = "#0B5F5A",
	tealInk = "#073E3B",
	gold = "#FFC53D",
	goldLight = "#FFE08A",
	goldDark = "#D99A0B",
	green = "#4CC764",
	greenDark = "#2E9A45",
	greenButton = "#2A8F40", -- button faces with white text (4.1:1; green is 2.2:1)
	greenDeep = "#1D6B2E",
	greenInk = "#124A1F",
	sky = "#5BB8F5",
	slate = "#6F7A8F",
	greyLight = "#DCD6DA",
	grey = "#B9B2B7",
	greyDark = "#8E878F",
	greyDeep = "#5E5760",
}
Theme.hex = hex

local color: { [string]: Color3 } = {}
for name, value in hex do
	color[name] = Color3.fromHex(value)
end
Theme.color = color

-- Dark glass behind HUD readouts (so they read on sand, grass and lava alike).
Theme.glass = {
	color = color.ink,
	transparency = 0.35,
	strokeColor = color.white,
	strokeTransparency = 0.7,
}

-- ===== button variants =====
export type Variant = { face: Color3, lip: Color3, rim: Color3, text: Color3, textStroke: Color3 }

local function variant(
	face: string,
	lip: string,
	rim: string,
	text: string,
	textStroke: string
): Variant
	return {
		face = Color3.fromHex(face),
		lip = Color3.fromHex(lip),
		rim = Color3.fromHex(rim),
		text = Color3.fromHex(text),
		textStroke = Color3.fromHex(textStroke),
	}
end

Theme.variant = {
	-- faces are the darker tones so white text stays readable in sunlight (WCAG >= 3.9:1)
	primary = variant(hex.lavaButton, hex.lavaDeep, hex.lavaInk, hex.white, hex.lavaInk),
	secondary = variant(hex.tealDark, hex.tealDeep, hex.tealInk, hex.white, hex.tealInk),
	good = variant(hex.greenButton, hex.greenDeep, hex.greenInk, hex.white, hex.greenInk),
	gold = variant(hex.gold, hex.goldDark, "#8A5E00", hex.charcoal, hex.goldLight),
	danger = variant(hex.red, hex.redDark, "#6E140B", hex.white, "#6E140B"),
	neutral = variant(hex.creamLight, hex.parchmentLine, "#B99A5E", hex.charcoal, hex.creamLight),
	dark = variant("#4A3F52", hex.ink, hex.ink, hex.cream, hex.ink),
	-- greyed out, but the words (a price, "Need 40 more") stay readable: dark on grey, 7:1
	disabled = variant(hex.grey, hex.greyDark, hex.greyDeep, hex.charcoal, hex.greyLight),
} :: { [string]: Variant }

-- Toast / pill kinds.
Theme.kind = {
	info = { fill = color.ink, text = color.white, accent = color.sky },
	good = { fill = color.greenButton, text = color.white, accent = color.green },
	warn = { fill = color.lavaDark, text = color.white, accent = color.lava },
	gold = { fill = color.gold, text = color.charcoal, accent = color.goldDark },
} :: { [string]: { fill: Color3, text: Color3, accent: Color3 } }

-- Burp banner tones (fill, text).
Theme.tone = {
	rumble = { fill = color.lavaDark, text = color.white },
	pops = { fill = color.red, text = color.white },
	ash = { fill = color.slate, text = color.white },
	gold = { fill = color.gold, text = color.charcoal },
	gems = { fill = color.tealDark, text = color.white },
} :: { [string]: { fill: Color3, text: Color3 } }

-- ===== fonts, sizes =====
Theme.font = {
	title = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
}

Theme.text = {
	tiny = 12,
	small = 14,
	label = 15, -- words on the round thumb buttons (SWEEP, SELL)
	body = 16,
	icon = 20, -- emoji glyphs in pills, toasts and small pictures
	big = 20,
	title = 26,
	count = 30, -- big countdown digits
	emoji = 30, -- big emoji (panel title icon)
	huge = 40,
	logo = 64, -- splash broom
	min = UiMath.K.textMin, -- 11: the smallest TextScaled may ever shrink to
}

Theme.radius = {
	sm = UDim.new(0, 8),
	md = UDim.new(0, 12),
	lg = UDim.new(0, 18),
	full = UDim.new(0.5, 0),
}

-- Touch sizes live in shared/Ui/UiMath.K so Lune tests can check them (>= 44 px).
Theme.size = {
	touch = UiMath.K.touch, -- 44: the smallest thing a thumb may tap
	button = UiMath.K.button, -- 48: every main action button (BUY, CLAIM, EQUIP, AUTO, MENU)
	claimW = UiMath.K.claimW, -- 104: price / claim buttons on cards
	pad = 8,
	gap = 6,
	stroke = 2,
	strokeThick = 3,
	lip = 4, -- depth of a button's bottom edge (drawn INSIDE the button; the whole box is tappable)
	titleBar = UiMath.K.titleBar,
	titleBarShort = UiMath.K.titleBarShort,
	closeButton = UiMath.K.closeButton,
	menuButton = UiMath.K.menuSize,
}

-- ===== motion =====
Theme.duration = {
	instant = 0.06,
	fast = 0.12,
	normal = 0.2,
	slow = 0.35,
	toast = 3,
	splash = 0.8,
	splashMax = 4,
}

Theme.ease = {
	fast = TweenInfo.new(Theme.duration.fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	normal = TweenInfo.new(Theme.duration.normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(Theme.duration.normal, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	slow = TweenInfo.new(Theme.duration.slow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

Theme.DisplayOrder = {
	hud = 10,
	banner = 12,
	toasts = 14,
	panels = 20,
	overlay = 40,
}

-- ===== helpers =====
local function camera(): Camera?
	return workspace.CurrentCamera
end

function Theme.scaleFor(width: number, height: number): number
	return UiMath.scaleFor(width, height)
end

-- UIScale factor from the current viewport (screens built with Components.screen use their own
-- gui size, which is the same thing minus device insets).
function Theme.scale(): number
	local cam = camera()
	if cam == nil then
		return 1
	end
	local size = cam.ViewportSize
	return UiMath.scaleFor(size.X, size.Y)
end

-- Height (real px) of Roblox's own top bar. Screens ignore the gui inset, so HUD pieces that must
-- not sit under the Roblox menu icons start below this.
function Theme.topInset(): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(inset) == "Vector2" then
		return math.clamp(inset.Y, 0, 64)
	end
	return 36
end

function Theme.fmt(n: number): string
	return Format.compact(n)
end

return Theme

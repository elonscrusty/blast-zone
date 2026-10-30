--!strict
-- The look of the whole UI in one place: colours, fonts, text sizes, corners, shadows, motion.
-- Views never write a colour, font or size of their own; they ask for a role here (or build with
-- Components.luau, which asks here). Swapping the skin restyles every screen at once.
-- Pure data so Lune can test it. Rule: plans/CONTRACTS.md, "Look and logic".

local StreetSticker = require("./Skins/StreetSticker")

export type Colors = {
	panel: string,
	panelAlt: string,
	ink: string,
	inkOnAccent: string,
	inkOnDark: string,
	outline: string,
	shadow: string,
	accent: string,
	good: string,
	danger: string,
	info: string,
	dim: string,
	backdrop: string,
	coin: string,
	winTop: string,
	winBottom: string,
	loseTop: string,
	loseBottom: string,
	drawTop: string,
	drawBottom: string,
}

export type Skin = {
	id: string,
	name: string,
	colors: Colors,
	fonts: { display: string, body: string },
	text: { display: number, title: number, body: number, caption: number },
	shape: { strokeScale: number, cornerScale: number, shadowOffset: number, backdropAlpha: number },
	motion: { pop: number, slide: number, fade: number },
}

export type ColorRole = string -- one of Tokens.COLOR_KEYS
export type TextRole = "display" | "title" | "body" | "caption"

local Tokens = {}

-- Every key a skin must have. The import tool and the tests use these lists.
Tokens.COLOR_KEYS = {
	"panel",
	"panelAlt",
	"ink",
	"inkOnAccent",
	"inkOnDark",
	"outline",
	"shadow",
	"accent",
	"good",
	"danger",
	"info",
	"dim",
	"backdrop",
	"coin",
	"winTop",
	"winBottom",
	"loseTop",
	"loseBottom",
	"drawTop",
	"drawBottom",
}
Tokens.TEXT_KEYS = { "display", "title", "body", "caption" }
Tokens.SHAPE_KEYS = { "strokeScale", "cornerScale", "shadowOffset", "backdropAlpha" }
Tokens.MOTION_KEYS = { "pop", "slide", "fade" }

-- Roblox built-in fonts a skin may name (Claude Design picks the closest one).
Tokens.FONTS = {
	"FredokaOne",
	"LuckiestGuy",
	"Bangers",
	"GothamBlack",
	"GothamBold",
	"Gotham",
	"BuilderSans",
	"BuilderSansBold",
	"BuilderSansExtraBold",
	"Montserrat",
	"Michroma",
	"Oswald",
	"Sarpanch",
	"TitilliumWeb",
	"Ubuntu",
	"Arcade",
	"PermanentMarker",
}

-- Never smaller than this on a phone, in design points (also Config.Settings.minTouchTarget).
Tokens.MIN_TOUCH = 48
Tokens.MIN_TEXT = 9

Tokens.skins = {
	street_sticker = StreetSticker :: Skin,
}

Tokens.defaultSkin = "street_sticker"

local current = Tokens.defaultSkin

function Tokens.get(id: string?): Skin
	return Tokens.skins[id or current] or Tokens.skins[Tokens.defaultSkin]
end

-- Picks the skin every screen uses. Call before screens are built (skins are not live-swapped yet).
function Tokens.use(id: string): boolean
	if Tokens.skins[id] == nil then
		return false
	end
	current = id
	return true
end

function Tokens.currentId(): string
	return current
end

function Tokens.color(role: ColorRole, skin: Skin?): string
	local colors = (skin or Tokens.get(nil)).colors :: any
	local value = colors[role]
	assert(type(value) == "string", "unknown colour role " .. role)
	return value
end

-- "#RRGGBB" -> 0..1 channels. Pure, for tests and contrast checks.
function Tokens.rgb(hex: string): (number, number, number)
	assert(string.match(hex, "^#%x%x%x%x%x%x$"), "bad hex " .. hex)
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number
	return r / 255, g / 255, b / 255
end

local function channel(c: number): number
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

-- WCAG contrast ratio between two colours (1 to 21). Text needs 4.5, big text 3.
function Tokens.contrast(a: string, b: string): number
	local function lum(hex: string): number
		local r, g, bl = Tokens.rgb(hex)
		return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(bl)
	end
	local la, lb = lum(a), lum(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

local function isHex(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end

local function hasFont(name: any): boolean
	return table.find(Tokens.FONTS, name) ~= nil
end

-- Everything wrong with a skin, as short sentences (empty list = good). Used by the tests and by
-- tools/import-design so a Claude Design export is checked before it reaches the game.
function Tokens.check(skin: any): { string }
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	if type(skin) ~= "table" then
		return { "skin is not a table" }
	end
	if type(skin.id) ~= "string" or not string.match(skin.id, "^[%l][%l%d_]*$") then
		bad("id must be lower_snake_case, like neon_night")
	end
	if type(skin.name) ~= "string" or #skin.name == 0 then
		bad("name is missing")
	end
	local colors = if type(skin.colors) == "table" then skin.colors else {}
	for _, key in Tokens.COLOR_KEYS do
		if not isHex(colors[key]) then
			bad(`colors.{key} must be "#RRGGBB"`)
		end
	end
	local fonts = if type(skin.fonts) == "table" then skin.fonts else {}
	for _, key in { "display", "body" } do
		if not hasFont(fonts[key]) then
			bad(`fonts.{key} must be a Roblox font from Tokens.FONTS`)
		end
	end
	local text = if type(skin.text) == "table" then skin.text else {}
	for _, key in Tokens.TEXT_KEYS do
		local v = text[key]
		if type(v) ~= "number" or v < Tokens.MIN_TEXT or v > 120 then
			bad(`text.{key} must be a number from {Tokens.MIN_TEXT} to 120`)
		end
	end
	local shape = if type(skin.shape) == "table" then skin.shape else {}
	local limits = {
		strokeScale = { 0, 0.03 },
		cornerScale = { 0, 0.5 },
		shadowOffset = { 0, 0.04 },
		backdropAlpha = { 0, 1 },
	}
	for _, key in Tokens.SHAPE_KEYS do
		local v, lim = shape[key], limits[key]
		if type(v) ~= "number" or v < lim[1] or v > lim[2] then
			bad(`shape.{key} must be a number from {lim[1]} to {lim[2]}`)
		end
	end
	local motion = if type(skin.motion) == "table" then skin.motion else {}
	for _, key in Tokens.MOTION_KEYS do
		local v = motion[key]
		if type(v) ~= "number" or v < 0 or v > 2 then
			bad(`motion.{key} must be seconds from 0 to 2`)
		end
	end
	if #problems == 0 then
		-- Words must be readable on a small phone in sunlight.
		local function needs(fg: string, bg: string, ratio: number)
			local c = Tokens.contrast(colors[fg], colors[bg])
			if c < ratio then
				bad(`{fg} on {bg} is hard to read ({string.format("%.1f", c)}:1, needs {ratio}:1)`)
			end
		end
		needs("ink", "panel", 4.5)
		needs("ink", "panelAlt", 4.5)
		needs("inkOnAccent", "accent", 3)
		needs("inkOnAccent", "danger", 3)
		needs("inkOnDark", "backdrop", 4.5)
	end
	return problems
end

return Tokens

--!strict
-- Short door to the current skin for screen code: colours by role, fonts by role. Screens call these
-- instead of writing Color3 or Enum.Font values, so a new skin from Claude Design restyles them.
-- Roles: see Tokens.COLOR_KEYS and Tokens.EXTRA_COLORS. Rule: plans/CONTRACTS.md, "Look and logic".

local Tokens = require("./Tokens")

local Look = {}

-- Roblox Color3 for a colour role ("panel", "ink", "accent", ...).
function Look.color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

-- "#RRGGBB" for a colour role (for code that keeps colours as text).
function Look.hex(role: string): string
	return Tokens.color(role)
end

local function fontEnum(name: string): Enum.Font
	local ok, font = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and typeof(font) == "EnumItem" then
		return font :: Enum.Font
	end
	return Enum.Font.FredokaOne
end

-- "display" = big words and numbers (LuckiestGuy, capitals only), "body" = things you read.
function Look.font(role: "display" | "body"): Enum.Font
	local fonts = Tokens.get(nil).fonts
	return fontEnum(if role == "display" then fonts.display else fonts.body)
end

-- Text size in points of the 780 x 360 phone for a text role.
function Look.textSize(role: Tokens.TextRole): number
	return (Tokens.get(nil).text :: any)[role]
end

return Look

--!strict
-- The look layer: every skin is complete and readable, the HUD theme follows the skin, the Claude
-- Design import tool checks and converts skins, and view files keep looks out of their logic.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("./harness")
local Tokens = require("../src/client/Ui/Tokens")
local Theme = require("../src/client/Hud/Theme")
local DesignImport = require("../tools/DesignImport")

Harness.test("ui tokens: every skin passes the skin check", function()
	for id, skin in Tokens.skins do
		Harness.eq(skin.id, id, "skin id must match its key")
		local problems = Tokens.check(skin)
		Harness.eq(#problems, 0, `{id}: {table.concat(problems, "; ")}`)
	end
	Harness.truthy(Tokens.skins[Tokens.defaultSkin], "default skin missing")
end)

Harness.test("ui tokens: the HUD theme reads the current skin", function()
	local skin = Tokens.get(nil)
	local look = Theme.get(nil)
	Harness.eq(look.panel, skin.colors.panel)
	Harness.eq(look.accent, skin.colors.accent)
	Harness.eq(look.strokeScale, skin.shape.strokeScale)
	Harness.eq(Theme.get("B").panel, Tokens.get("street_sticker").colors.panel)
end)

Harness.test("ui tokens: unknown skins and roles are refused", function()
	Harness.eq(Tokens.use("no_such_skin"), false)
	Harness.eq(Tokens.currentId(), Tokens.defaultSkin)
	Harness.eq(pcall(Tokens.color, "notARole"), false)
	Harness.eq(Tokens.get("no_such_skin").id, Tokens.defaultSkin)
end)

Harness.test("ui tokens: contrast maths", function()
	Harness.near(Tokens.contrast("#000000", "#FFFFFF"), 21, 0.01)
	Harness.near(Tokens.contrast("#777777", "#777777"), 1, 1e-6)
end)

Harness.test("ui tokens: the skin check finds broken skins", function()
	local broken = table.clone(Tokens.get(nil)) :: any
	broken.colors = table.clone(broken.colors)
	broken.colors.ink = "#FFF4D5" -- cream on cream
	broken.fonts = { display = "ComicSans", body = "GothamBold" }
	local problems = Tokens.check(broken)
	Harness.truthy(#problems >= 1, "should find the bad font")
	broken.fonts = { display = "FredokaOne", body = "GothamBold" }
	problems = Tokens.check(broken)
	Harness.truthy(
		string.find(problems[1] or "", "hard to read", 1, true) ~= nil,
		"should find low contrast"
	)
end)

Harness.test("ui import: the template converts and comes back the same", function()
	local raw = serde.decode("json", fs.readFile("design/skin-template.json"))
	local source, problems = DesignImport.convert(raw)
	Harness.eq(#problems, 0, table.concat(problems, "; "))
	local text = source :: string
	Harness.truthy(string.find(text, "--!strict", 1, true) == 1, "must start with --!strict")
	Harness.truthy(string.find(text, 'panel = "#FFF4D6"', 1, true) ~= nil, "colour missing")
	Harness.eq(DesignImport.fileName("neon_night"), "NeonNight")
end)

Harness.test("ui import: fills sizes, fixes hex case, refuses missing colours", function()
	local raw = serde.decode("json", fs.readFile("design/skin-template.json"))
	raw.text = nil
	raw.colors.panel = "fff4d6"
	local skin = DesignImport.normalize(raw)
	Harness.eq(skin.colors.panel, "#FFF4D6")
	Harness.eq(skin.text.title, Tokens.get(Tokens.defaultSkin).text.title)
	raw.colors.accent = nil
	local source, problems = DesignImport.convert(raw)
	Harness.eq(source, nil)
	Harness.truthy(#problems > 0)
	local none, why = DesignImport.convert("nope")
	Harness.eq(none, nil)
	Harness.eq(#why, 1)
end)

-- Look and logic: only the look layer writes colours and fonts. 3D world art keeps its own colours.
-- LEGACY files still have their own; move each to Components/Tokens, then delete its line here.
local LOOK_LAYER = {
	"src/client/Ui/",
	"src/client/Hud/Theme.luau",
	"src/client/Hud/UiKit.luau",
}
local WORLD_ART = {
	"src/client/Arena/DayNightSystem.luau", -- piece 14 sky and light colours
	"src/client/Character/CharacterGun.luau",
	"src/client/Combat/CombatFx.luau",
	"src/client/Combat/GunModels.luau",
	"src/client/Effects/", -- piece 13 particles, tracers and flashes
	"src/client/Movement/SlideTrail.luau",
	"src/client/Pickups/PickupFxSystem.luau",
	"src/client/Props/BreakFxSystem.luau", -- piece 47 flying chunks (3D world parts)
	"src/client/Progression/CoinView.luau",
	"src/client/Zone/ZoneBoundary.luau",
}
local LEGACY = {
	"src/client/Bots/BotBannerSystem.luau",
	"src/client/Character/LookPickerSystem.luau",
	"src/client/Combat/HealthBars.luau",
	"src/client/Daily/DailyUiSystem.luau",
	"src/client/Emotes/EmoteWheelSystem.luau",
	"src/client/Emotes/WinnerBannerSystem.luau",
	"src/client/Lobby/LoadoutPanel.luau",
	"src/client/Lobby/LobbyClientSystem.luau",
	"src/client/MapVote/MapVoteClientSystem.luau",
	"src/client/Match/ResultsClientSystem.luau",
	"src/client/Match/SpectateClientSystem.luau",
	"src/client/Onboarding/IntroView.luau",
	"src/client/Progression/ClaimUiSystem.luau",
	"src/client/Progression/ProgressUi.luau",
	"src/client/Progression/TrackPanel.luau",
	"src/client/Social/InviteButtonSystem.luau",
	"src/client/Stats/StatsClientSystem.luau",
	"src/client/Upgrades/UpgradeCardsSystem.luau",
	"src/client/Zone/ZoneHud.luau",
}

local LOOK_PATTERNS = {
	"Color3%.fromRGB%(",
	"Color3%.new%(",
	'Color3%.fromHex%(%s*"',
	"Enum%.Font%.",
	"Palette%.",
	'"#%x%x%x%x%x%x"',
}

local function luauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local function listed(path: string, list: { string }): boolean
	for _, entry in list do
		if string.sub(path, 1, #entry) == entry then
			return true
		end
	end
	return false
end

local function writesLooks(source: string): string?
	for _, pattern in LOOK_PATTERNS do
		if string.find(source, pattern) then
			return pattern
		end
	end
	return nil
end

Harness.test("ui look/logic: only the look layer writes colours and fonts", function()
	local files = {}
	luauFiles("src/client", files)
	for _, path in files do
		if not (listed(path, LOOK_LAYER) or listed(path, WORLD_ART) or listed(path, LEGACY)) then
			local hit = writesLooks(fs.readFile(path))
			Harness.eq(hit, nil, `{path} writes its own look; use Ui/Components or Ui/Tokens roles`)
		end
	end
end)

Harness.test("ui look/logic: the legacy list only shrinks", function()
	for _, path in LEGACY do
		if fs.isFile(path) then
			Harness.truthy(
				writesLooks(fs.readFile(path)) ~= nil,
				`{path} is clean now; delete its line from LEGACY in tests/ui_tokens.test.luau`
			)
		end
	end
end)

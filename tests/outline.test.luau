--!strict
-- Toy look (video 3): the fighter outline and the ground ring are pure cosmetics. The only thing
-- Lune can check is the budget: Roblox draws at most 31 Highlights at once.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local ArtKit = require("../src/server/Arena/ArtKit")

local OUT = Config.Art.outline
local ROBLOX_HIGHLIGHT_LIMIT = 31

Harness.test(
	"outline: fighter outlines plus the hit-flash pool fit Roblox's Highlight limit",
	function()
		local fighters = Config.Match.maxParticipants
		Harness.truthy(
			fighters + OUT.fxHighlightPool <= ROBLOX_HIGHLIGHT_LIMIT,
			`{fighters} outlines + {OUT.fxHighlightPool} flashes is over {ROBLOX_HIGHLIGHT_LIMIT}`
		)
	end
)

Harness.test("outline: the hit-flash pool size in Fx matches the Config number", function()
	local fio = require("@lune/fs")
	local source = fio.readFile("src/client/Effects/Fx.luau")
	local n = string.match(source, "local HIGHLIGHT_POOL = (%d+)")
	Harness.eq(tonumber(n), OUT.fxHighlightPool, "update Config.Art.outline.fxHighlightPool")
end)

Harness.test("outline: the outline and the lobby grid are not pickup colors", function()
	Harness.eq(ArtKit.reservedColor(OUT.color), nil, "outline is not gold or violet")
	Harness.eq(ArtKit.reservedColor(Config.Art.lobbyGrid.color), nil, "grid is not gold or violet")
end)

Harness.test("lobby grid: even lines, none on the edge, a small count", function()
	local GridLines = require("../src/shared/GridLines")
	local LobbyLayout = require("../src/shared/LobbyLayout")
	local g = Config.Art.lobbyGrid
	local across = GridLines.offsets(LobbyLayout.width, g.spacing)
	local down = GridLines.offsets(LobbyLayout.depth, g.spacing)
	Harness.truthy(#across + #down <= 80, "a few dozen neon parts at most")
	Harness.truthy(#across >= 3 and #down >= 3, "it really looks like a grid")
	for _, dx in across do
		Harness.truthy(math.abs(dx) < LobbyLayout.width / 2, "inside the plaza")
	end
	Harness.eq(across[1], -across[#across], "symmetrical")
	Harness.eq(#GridLines.offsets(0, 5), 0)
	Harness.eq(#GridLines.offsets(100, 0), 0)
	Harness.eq(#GridLines.offsets(10, 50), 1, "one line through the middle")
end)

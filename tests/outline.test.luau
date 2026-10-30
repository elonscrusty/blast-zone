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

Harness.test("outline: the ring stays thin and is not a pickup color", function()
	Harness.truthy(OUT.ring.thickness <= 0.3, "a thin disc, nothing to trip on or shoot")
	Harness.eq(ArtKit.reservedColor(OUT.ring.color), nil, "ring is not gold or violet")
	Harness.eq(ArtKit.reservedColor(OUT.color), nil, "outline is not gold or violet")
end)

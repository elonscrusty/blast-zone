--!strict
-- Piece 14: the Neon Night city art plan. Checks the rules that keep art harmless: it stays in
-- budget, never floats, never uses pickup colors or shot colors where players walk, never sits on
-- a crate spot or a spawn pad, and always fades together with the wall or roof it is painted on.
local Harness = require("./harness")
local ArtKit = require("../src/server/Arena/ArtKit")
local ArtMap = require("../src/server/Arena/ArtMap")
local ArtPlan = require("../src/server/Arena/ArtPlan")
local Layout = require("../src/server/Arena/Layout")
local SkylineArt = require("../src/server/Arena/SkylineArt")
local Config = require("../src/shared/Config")

local ART = Config.Art
local HEAD = 6 -- studs: anything lower than this is "near the players"
local settings: ArtPlan.Settings = {
	seed = ART.seed,
	towers = ART.skyline.towers,
	innerGap = ART.skyline.innerGap,
	outerReach = ART.skyline.outerReach,
}

local specs = {
	A = require("../src/server/Arena/LayoutA"),
	B = require("../src/server/Arena/LayoutB"),
	C = require("../src/server/Arena/LayoutC"),
}

local function bottomOf(p: ArtKit.Spec): number
	-- tilted parts: use the largest extent, which is the safe side
	if p.rx ~= 0 or p.ry ~= 0 or p.rz ~= 0 then
		return p.y - math.max(p.sx, p.sy, p.sz) / 2
	end
	return p.y - p.sy / 2
end

local function hueOf(hex: string): (number, number, number)
	return ArtKit.hsv(hex)
end

for key, spec in specs do
	local layout = Layout.compile(spec)
	local map = ArtMap.new(layout)
	local result = ArtPlan.build(layout, settings)
	local function t(name: string, fn: () -> ())
		Harness.test(`art {key}: {name}`, fn)
	end

	t("stays inside the phone budget", function()
		Harness.truthy(
			#result.parts <= ART.maxParts,
			`{#result.parts} parts is over {ART.maxParts}`
		)
		Harness.truthy(#result.parts >= 2500, "the city is rich: at least 2500 parts")
		local lights, signs = 0, 0
		for _, p in result.parts do
			if p.light then
				lights += 1
			end
			if p.sign then
				signs += 1
			end
		end
		Harness.truthy(lights <= ART.maxLights, `{lights} lights is over {ART.maxLights}`)
		Harness.truthy(signs <= 26, `{signs} signs is over 26`)
	end)

	t("same seed makes the same city", function()
		local again = ArtPlan.build(layout, settings)
		Harness.eq(#again.parts, #result.parts, "part count")
		for i = 1, #result.parts, 37 do
			local a, b = result.parts[i] :: ArtKit.Spec, again.parts[i] :: ArtKit.Spec
			Harness.eq(a.name, b.name, "name")
			Harness.near(a.x + a.y + a.z, b.x + b.y + b.z, 1e-9, "position")
		end
	end)

	t("part names are unique and sizes are real", function()
		local seen: { [string]: boolean } = {}
		for _, p in result.parts do
			Harness.truthy(not seen[p.name], `duplicate name {p.name}`)
			seen[p.name] = true
			Harness.truthy(p.sx > 0 and p.sy > 0 and p.sz > 0, `{p.name} has no size`)
			Harness.truthy(p.sx == p.sx and p.y == p.y and p.z == p.z, `{p.name} is NaN`)
		end
	end)

	t("nothing floats between the ground and head height", function()
		local checked = 0
		for _, p in result.parts do
			if p.group == "Skyline" then
				continue
			end
			local bottom = bottomOf(p)
			if bottom > 0.8 and bottom < ART.lowestFloatingStuds then
				checked += 1
				local hx, hz = p.sx / 2 + ART.flushStuds, p.sz / 2 + ART.flushStuds
				Harness.truthy(
					map:rectHitsSolid(p.x - hx, p.z - hz, p.x + hx, p.z + hz, 0),
					`{p.name} floats at y {bottom} ({p.x}, {p.z})`
				)
			end
		end
		Harness.truthy(checked > 100, "the check really looked at parts")
	end)

	t("no gold or violet low down (those mean pickups)", function()
		for _, p in result.parts do
			if p.group == "Skyline" or bottomOf(p) >= HEAD then
				continue
			end
			Harness.eq(ArtKit.reservedColor(p.color), nil, `{p.name} {p.color} looks like a pickup`)
			if p.neon then
				Harness.eq(ArtKit.reservedColor(p.neon.on), nil, `{p.name} glows {p.neon.on}`)
				Harness.eq(ArtKit.reservedColor(p.neon.off), nil, `{p.name} dims to {p.neon.off}`)
			end
		end
	end)

	t("no thin cyan glow streaks low down (those mean shots)", function()
		for _, p in result.parts do
			if p.neon == nil or bottomOf(p) >= 3 then
				continue
			end
			-- a streak is a line (long, and thin both ways); a flat ring or plate is not
			local dims = { p.sx, p.sy, p.sz }
			table.sort(dims)
			local thin, mid, long = dims[1] :: number, dims[2] :: number, dims[3] :: number
			if long >= 3 and long / thin >= 8 and long / mid >= 4 then
				local h, s = hueOf(p.neon.on)
				Harness.truthy(
					not (h >= 165 and h <= 200 and s >= 0.5),
					`{p.name} is a cyan streak`
				)
			end
		end
	end)

	t("crate spots and spawn pads stay clear", function()
		local points: { Layout.Point } = {}
		for _, c in layout.containers do
			table.insert(points, c)
		end
		for _, s in layout.spawns do
			table.insert(points, s)
		end
		for _, pt in points do
			for _, p in result.parts do
				local paint = p.y < 0.5 and math.min(p.sx, p.sy, p.sz) <= 0.25
				if p.group == "Skyline" or paint then
					continue -- paint lying on the ground is fine
				end
				if bottomOf(p) < 3 then
					local inX = math.abs(p.x - pt.x) < p.sx / 2 + 2
					local inZ = math.abs(p.z - pt.z) < p.sz / 2 + 2
					Harness.truthy(not (inX and inZ), `{p.name} sits on {pt.id}`)
				end
			end
		end
	end)

	t("stays inside the arena, the skyline stays outside", function()
		local half = layout.half
		for _, p in result.parts do
			local reachX = math.abs(p.x) + p.sx / 2
			local reachZ = math.abs(p.z) + p.sz / 2
			if p.group == "Skyline" then
				if p.name ~= "SkylineGround" then
					Harness.truthy(
						math.abs(p.x) - p.sx / 2 > half or math.abs(p.z) - p.sz / 2 > half,
						`{p.name} is inside the wall`
					)
				end
			else
				Harness.truthy(
					reachX <= half + 8 and reachZ <= half + 8,
					`{p.name} leaves the arena`
				)
			end
		end
	end)

	t("a gray box is only hidden when art really stands in its place", function()
		local hidden = 0
		for _, s in layout.solids do
			if ArtPlan.replaces(s) then
				hidden += 1
				local found = false
				for _, p in result.parts do
					if
						p.x >= s.x0
						and p.x <= s.x1
						and p.z >= s.z0
						and p.z <= s.z1
						and p.y - p.sy / 2 < s.h
					then
						found = true
						break
					end
				end
				Harness.truthy(found, `{s.id} would vanish with nothing drawn in its place`)
			end
			if
				s.kind == "wall"
				or s.kind == "partition"
				or s.kind == "fence"
				or s.kind == "boundary"
			then
				Harness.truthy(not ArtPlan.replaces(s), `{s.id} must stay visible as the body`)
			end
		end
		Harness.truthy(hidden > 5, "some boxes are redrawn")
	end)

	t("everything that fades names a real wall or roof", function()
		local occluders: { [string]: boolean } = {}
		for _, s in layout.solids do
			if s.occluder then
				occluders[s.id] = true
			end
		end
		for _, r in layout.roofs do
			occluders[r.id] = true
		end
		local followers = 0
		for _, p in result.parts do
			if p.fadeWith ~= nil then
				followers += 1
				Harness.truthy(occluders[p.fadeWith] == true, `{p.name} follows {p.fadeWith}`)
			end
		end
		Harness.truthy(followers > 300, "roofs and walls really carry art")
	end)

	t("skyline towers never overlap and the south ones stay low", function()
		local towers = SkylineArt.layoutTowers(ArtKit.newPlan(ART.seed), layout.half, ART.skyline)
		Harness.truthy(#towers >= 10, "enough towers")
		for i, a in towers do
			Harness.truthy(
				math.abs(a.x) - a.w / 2 > layout.half or math.abs(a.z) - a.d / 2 > layout.half,
				"tower outside the wall"
			)
			if a.side == "S" then
				Harness.truthy(a.h <= 9, "south tower low (camera looks north)")
			end
			for j = i + 1, #towers do
				local b = towers[j] :: SkylineArt.Tower
				local apart = math.abs(a.x - b.x) >= (a.w + b.w) / 2
					or math.abs(a.z - b.z) >= (a.d + b.d) / 2
				Harness.truthy(apart, "towers overlap")
			end
		end
	end)
end

Harness.test(
	"art: the plan is a pure picture of the layout (no collision fields at all)",
	function()
		local layout = Layout.compile(specs.C)
		local before = #layout.solids
		local solidsBefore = {}
		for _, s in layout.solids do
			table.insert(solidsBefore, `{s.id}:{s.x0},{s.z0},{s.x1},{s.z1},{s.h}`)
		end
		ArtPlan.build(layout, settings)
		Harness.eq(#layout.solids, before, "solid count unchanged")
		for i, s in layout.solids do
			Harness.eq(
				`{s.id}:{s.x0},{s.z0},{s.x1},{s.z1},{s.h}`,
				solidsBefore[i],
				"solid unchanged"
			)
		end
	end
)

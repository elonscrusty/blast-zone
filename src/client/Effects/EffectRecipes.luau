--!strict
-- What each fight effect is made of, in the "Sticker Punch" look (carter's pick): bright, chunky, and
-- outlined in navy, so it reads at a glance on a phone and never hides who is who.
-- Pure data plus `resolve`, so the tests can check the rules. `Fx.luau` turns a resolved recipe into
-- particles, billboards and flat rings.
--
-- Rules every recipe follows:
--   * Short. Nothing lives longer than MAX_SECONDS.
--   * Small on purpose. The biggest burst is a few dozen particles, and `FxBudget` caps the total.
--   * Strobing things (white flashes that repeat with every shot) are marked `strobe` and are dropped
--     when the player turns on Fewer flashes. Big one-off bursts are marked `flashy` and fade lighter.

export type Range = { number }

export type Particles = {
	kind: string, -- "chip" (confetti bits), "puff" (soft cloud) or "spark"
	count: number,
	life: Range,
	speed: Range,
	size: Range, -- start and end size in studs
	colors: { string }, -- hex; "@tier" means the color of the container tier
	gravity: number, -- studs per second squared, pulling down
	spread: number, -- degrees
	direction: string, -- "along" the way the effect points, "side" (casings), or "out" in every direction
	drag: number?,
	light: number?, -- LightEmission 0..1
	radiusScale: boolean?, -- sizes scale with the blast radius
	index: number?, -- set by resolve: which emitter this group uses
}

export type Star = {
	size: Range, -- start and end width in studs
	life: number,
	fill: string,
	spin: number?, -- degrees per second
	along: number?, -- studs in front of the position
	strobe: boolean?,
	flashy: boolean?,
	radiusScale: boolean?,
}

export type Word = { texts: { string }, size: number, life: number, color: string, rise: number? }
export type RingPlan = {
	style: string,
	diameter: Range,
	life: number,
	color: string?,
	radiusScale: boolean?,
}

export type Recipe = {
	particles: { Particles },
	stars: { Star },
	words: { Word },
	rings: { RingPlan },
	shake: string?, -- a key of Config.Effects.trauma
	fov: string?, -- a key of Config.Effects.fovKick
	flash: number?, -- screen flash, 0 to 1
}

export type Options = {
	reduceFlashes: boolean?,
	scale: number?, -- multiplies the counts, for example 0.5 when the arena is busy
	tierColor: string?, -- replaces "@tier"
}

local MAX_SECONDS = 2.5

local NAVY = "#14243A"
local CYAN = "#36D9E8"
local GOLD = "#FFC44D"
local CORAL = "#F15B64"
local WHITE = "#FFFFFF"
local LILAC = "#B58CFF"
local ORANGE = "#FF9A3C"
local YELLOW = "#FFE27A"
local BRASS = "#D9A441"
local DUST = "#C8A675"

local CONFETTI = { GOLD, CORAL, CYAN, WHITE }

-- Confetti is one emitter per color (a particle cannot pick its own color), so a burst of
-- `count` bits is split evenly over the colors.
local function confetti(
	count: number,
	life: Range,
	speed: Range,
	spread: number,
	gravity: number,
	direction: string,
	colors: { string }?
): { Particles }
	local list = colors or CONFETTI
	local out = {}
	local each = math.max(1, math.floor(count / #list + 0.5))
	for _, color in list do
		table.insert(out, {
			kind = "chip",
			count = each,
			life = life,
			speed = speed,
			size = { 0.7, 0.35 },
			colors = { color },
			gravity = gravity,
			spread = spread,
			direction = direction,
		})
	end
	return out
end

local function join(...: { Particles }): { Particles }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

local function puffs(
	count: number,
	life: Range,
	speed: Range,
	size: Range,
	spread: number,
	color: string?,
	radiusScale: boolean?
): Particles
	return {
		kind = "puff",
		count = count,
		life = life,
		speed = speed,
		size = size,
		colors = { color or WHITE },
		gravity = 0,
		spread = spread,
		direction = "out",
		drag = 3,
		radiusScale = radiusScale,
	}
end

local KO_WORDS = { "KO!" }

local Recipes: { [string]: Recipe } = {
	-- A flash of gold at the barrel, a little white puff, and a brass casing that pops out sideways.
	muzzle = {
		particles = {
			puffs(2, { 0.25, 0.4 }, { 4, 7 }, { 0.5, 1.7 }, 25, WHITE),
			{
				kind = "chip",
				count = 1,
				life = { 0.6, 0.9 },
				speed = { 13, 17 },
				size = { 0.35, 0.35 },
				colors = { BRASS },
				gravity = 60,
				spread = 25,
				direction = "side",
			},
		},
		stars = {
			{
				size = { 3.2, 4.4 },
				life = 0.1,
				fill = GOLD,
				spin = 300,
				along = 0.6,
				strobe = true,
			},
		},
		words = {},
		rings = {},
		shake = "shot",
		fov = "shot",
	},

	-- A shot that hit a body: a white star, a spray of confetti, two puffs.
	hit = {
		particles = join(
			confetti(8, { 0.5, 0.9 }, { 7, 13 }, 60, 40, "along"),
			{ puffs(2, { 0.3, 0.45 }, { 3, 6 }, { 0.5, 2 }, 40, WHITE) }
		),
		stars = { { size = { 2.6, 4.6 }, life = 0.22, fill = WHITE, spin = 200, strobe = true } },
		words = {},
		rings = {},
	},

	-- A big hit (a mortar blast, or anything over Config.Effects.numbers.bigAmount): bigger star and a BAM!
	hitBig = {
		particles = join(
			confetti(12, { 0.5, 0.9 }, { 8, 15 }, 70, 40, "along"),
			{ puffs(3, { 0.3, 0.5 }, { 3, 7 }, { 0.6, 2.6 }, 50, WHITE) }
		),
		stars = { { size = { 3.2, 6.2 }, life = 0.25, fill = WHITE, spin = 200, flashy = true } },
		words = { { texts = { "BAM!" }, size = 6, life = 0.7, color = WHITE } },
		rings = {},
	},

	-- A shot that stopped at a wall or the ground.
	hitSurface = {
		particles = join(
			confetti(4, { 0.4, 0.7 }, { 6, 11 }, 60, 40, "along", { GOLD, WHITE }),
			{ puffs(1, { 0.4, 0.6 }, { 1, 3 }, { 0.7, 2.4 }, 40, DUST) }
		),
		stars = { { size = { 1.8, 3 }, life = 0.18, fill = GOLD, spin = 200 } },
		words = {},
		rings = {},
	},

	-- A knockout: gold star, a big confetti burst, white clouds, a ring and KO!
	kill = {
		particles = join(
			confetti(30, { 1, 1.5 }, { 7, 15 }, 180, 22, "out", { GOLD, CORAL, CYAN, WHITE, LILAC }),
			{ puffs(6, { 0.5, 0.8 }, { 3, 7 }, { 1, 4 }, 180, WHITE) }
		),
		stars = { { size = { 4, 13 }, life = 0.5, fill = GOLD, spin = 80, flashy = true } },
		words = { { texts = KO_WORDS, size = 9, life = 1.1, color = WHITE, rise = 1.2 } },
		rings = { { style = "sticker", diameter = { 2, 15 }, life = 0.5 } },
		shake = "kill",
		fov = "kill",
		flash = 0.12,
	},

	slideStart = {
		particles = { puffs(3, { 0.4, 0.6 }, { 2, 4 }, { 1, 3 }, 120, WHITE) },
		stars = {},
		words = {},
		rings = {},
		shake = "slide",
		fov = "slide",
	},

	-- Dropped behind the sliding body every few hundredths of a second.
	slideStep = {
		particles = { puffs(1, { 0.4, 0.5 }, { 1, 2 }, { 0.8, 2.6 }, 120, WHITE) },
		stars = {},
		words = {},
		rings = {},
	},

	-- A hit on a supply container, in the color of its tier.
	containerHit = {
		particles = join(confetti(6, { 0.6, 1 }, { 6, 11 }, 70, 30, "along", { "@tier", WHITE })),
		stars = { { size = { 2.4, 4.4 }, life = 0.2, fill = "@tier", spin = 200 } },
		words = {},
		rings = {},
	},

	-- A container breaking open.
	containerBreak = {
		particles = join(
			confetti(18, { 1, 1.5 }, { 6, 13 }, 180, 22, "out", { "@tier", GOLD, WHITE }),
			{ puffs(5, { 0.5, 0.7 }, { 3, 6 }, { 1, 4 }, 180, WHITE) }
		),
		stars = { { size = { 3, 9 }, life = 0.4, fill = "@tier", spin = 90, flashy = true } },
		words = { { texts = { "SMASH!" }, size = 7, life = 0.9, color = WHITE } },
		rings = { { style = "sticker", diameter = { 2, 12 }, life = 0.45, color = "@tier" } },
		shake = "crateBreak",
	},

	-- An XP orb that someone else took (or that timed out).
	orbPop = {
		particles = confetti(4, { 0.4, 0.7 }, { 4, 8 }, 180, 20, "out", { GOLD }),
		stars = { { size = { 1.4, 2.4 }, life = 0.25, fill = GOLD, spin = 200 } },
		words = {},
		rings = {},
	},

	-- You picked up an orb.
	pickupMine = {
		particles = confetti(4, { 0.4, 0.7 }, { 4, 8 }, 180, 20, "out", { GOLD }),
		stars = { { size = { 3, 5 }, life = 0.3, fill = GOLD, spin = 200 } },
		words = {},
		rings = { { style = "sticker", diameter = { 2, 7 }, life = 0.3, color = GOLD } },
	},

	-- The blast itself. Sizes follow the blast radius.
	blast = {
		particles = join(
			confetti(
				25,
				{ 1, 1.6 },
				{ 8, 18 },
				180,
				22,
				"out",
				{ GOLD, CORAL, CYAN, WHITE, YELLOW }
			),
			{
				puffs(4, { 0.5, 0.9 }, { 4, 9 }, { 2, 8 }, 180, ORANGE, true),
				puffs(3, { 0.5, 0.9 }, { 4, 9 }, { 2, 8 }, 180, YELLOW, true),
				puffs(3, { 0.5, 0.9 }, { 4, 9 }, { 2, 8 }, 180, WHITE, true),
			}
		),
		stars = {
			{
				size = { 0.8, 2.4 },
				life = 0.55,
				fill = GOLD,
				spin = 70,
				flashy = true,
				radiusScale = true,
			},
		},
		words = { { texts = { "BOOM!" }, size = 11, life = 1, color = WHITE, rise = 2 } },
		rings = {
			{ style = "sticker", diameter = { 1, 2.6 }, life = 0.5, radiusScale = true },
		},
		shake = "blast",
		fov = "blast",
		flash = 0.3,
	},
}

local RecipeBook = {}

RecipeBook.recipes = Recipes
RecipeBook.maxSeconds = MAX_SECONDS
RecipeBook.navy = NAVY
RecipeBook.tierPlaceholder = "@tier"

-- Which recipes exist, sorted, for tests and for pre-building pools.
function RecipeBook.names(): { string }
	local out = {}
	for name in Recipes do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function resolveColor(color: string, opts: Options): string
	if color == "@tier" then
		return opts.tierColor or GOLD
	end
	return color
end

-- Gives back a copy of the recipe ready to play: colors filled in, counts scaled, and strobing parts
-- removed when the player asked for fewer flashes. The first group keeps the index it had, so the
-- emitter built for it can be found again.
function RecipeBook.resolve(name: string, opts: Options?): Recipe
	local base = Recipes[name]
	if base == nil then
		error("EffectRecipes: no recipe called '" .. name .. "'", 2)
	end
	local o: Options = opts or {}
	local scale = math.max(0, o.scale or 1)
	local reduce = o.reduceFlashes == true
	local out: Recipe = {
		particles = {},
		stars = {},
		words = base.words,
		rings = {},
		shake = base.shake,
		fov = base.fov,
		flash = if reduce then 0 else base.flash,
	}
	for i, g in base.particles do
		local count = math.floor(g.count * scale + 0.5)
		if g.count > 0 and scale > 0 then
			count = math.max(1, count)
		end
		if count > 0 then
			local colors = {}
			for _, c in g.colors do
				table.insert(colors, resolveColor(c, o))
			end
			local copy = table.clone(g)
			copy.count = count
			copy.colors = colors
			copy.index = i
			table.insert(out.particles, copy)
		end
	end
	for _, s in base.stars do
		if not (reduce and s.strobe == true) then
			local copy = table.clone(s)
			copy.fill = resolveColor(s.fill, o)
			table.insert(out.stars, copy)
		end
	end
	for _, r in base.rings do
		local copy = table.clone(r)
		if r.color ~= nil then
			copy.color = resolveColor(r.color, o)
		end
		table.insert(out.rings, copy)
	end
	return out
end

-- How many particles one play of this recipe asks for (before the budget trims it).
function RecipeBook.particleTotal(recipe: Recipe): number
	local total = 0
	for _, g in recipe.particles do
		total += g.count
	end
	return total
end

-- The longest anything in the recipe lives, in seconds.
function RecipeBook.longestSeconds(recipe: Recipe): number
	local longest = 0
	for _, g in recipe.particles do
		longest = math.max(longest, g.life[2])
	end
	for _, s in recipe.stars do
		longest = math.max(longest, s.life)
	end
	for _, w in recipe.words do
		longest = math.max(longest, w.life)
	end
	for _, r in recipe.rings do
		longest = math.max(longest, r.life)
	end
	return longest
end

return RecipeBook

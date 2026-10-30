--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local FxBudget = require("../src/client/Effects/FxBudget")
local ShakeMath = require("../src/client/Effects/ShakeMath")
local Recipes = require("../src/client/Effects/EffectRecipes")

-- ===== budget =====

Harness.test("budget gives out up to the cap and no more", function()
	local b = FxBudget.new({ particles = 100 })
	Harness.eq(FxBudget.tryTake(b, "particles", 60, 0, 1), 60)
	Harness.eq(FxBudget.tryTake(b, "particles", 60, 0, 1), 40) -- only what is left
	Harness.eq(FxBudget.tryTake(b, "particles", 10, 0, 1), 0)
	Harness.eq(FxBudget.used(b, "particles", 0.5), 100)
end)

Harness.test("budget gives room back when the effects have ended", function()
	local b = FxBudget.new({ particles = 100 })
	FxBudget.tryTake(b, "particles", 100, 0, 1)
	Harness.eq(FxBudget.used(b, "particles", 1), 0)
	Harness.eq(FxBudget.tryTake(b, "particles", 30, 1, 1), 30)
end)

Harness.test("budget counts whole things and ignores nonsense asks", function()
	local b = FxBudget.new({ parts = 10 })
	Harness.eq(FxBudget.tryTake(b, "parts", 2.9, 0, 1), 2)
	Harness.eq(FxBudget.tryTake(b, "parts", 0, 0, 1), 0)
	Harness.eq(FxBudget.tryTake(b, "parts", -5, 0, 1), 0)
	Harness.eq(FxBudget.used(b, "parts", 0), 2)
end)

Harness.test("budget refuses a category it does not know", function()
	local b = FxBudget.new({ parts = 10 })
	local ok = pcall(FxBudget.tryTake, b, "sparkles", 1, 0, 1)
	Harness.eq(ok, false)
end)

Harness.test("budget clear forgets everything", function()
	local b = FxBudget.new({ parts = 10 })
	FxBudget.tryTake(b, "parts", 10, 0, 5)
	FxBudget.clear(b)
	Harness.eq(FxBudget.used(b, "parts", 0), 0)
end)

-- ===== shake =====

Harness.test("shake does nothing when the Camera shake setting is 0", function()
	local s = ShakeMath.new()
	ShakeMath.addTrauma(s, 0.5, 0)
	ShakeMath.addFov(s, 3, 0, 5)
	Harness.eq(s.trauma, 0)
	Harness.eq(s.fov, 0)
	local x, y, roll = ShakeMath.sample(s, 1.234, Config.Effects.shake)
	Harness.eq(x, 0)
	Harness.eq(y, 0)
	Harness.eq(roll, 0)
end)

Harness.test("shake never goes past its limits, even when hit again and again", function()
	local s = ShakeMath.new()
	for _ = 1, 50 do
		ShakeMath.addTrauma(s, 0.55, 1)
		ShakeMath.addFov(s, 3.5, 1, Config.Effects.fovKick.maxDegrees)
	end
	Harness.eq(s.trauma, 1)
	Harness.eq(s.fov, Config.Effects.fovKick.maxDegrees)
	local cfg = Config.Effects.shake
	for i = 1, 200 do
		local x, y, roll = ShakeMath.sample(s, i * 0.013, cfg)
		Harness.truthy(math.abs(x) <= cfg.maxOffsetStuds + 1e-9, "x too big")
		Harness.truthy(math.abs(y) <= cfg.maxOffsetStuds + 1e-9, "y too big")
		Harness.truthy(math.abs(roll) <= cfg.maxRollDegrees + 1e-9, "roll too big")
	end
end)

Harness.test("shake fades back to nothing by itself", function()
	local s = ShakeMath.new()
	ShakeMath.addTrauma(s, 1, 1)
	ShakeMath.addFov(s, 5, 1, 5)
	for _ = 1, 120 do
		ShakeMath.step(
			s,
			1 / 60,
			Config.Effects.shake.decayPerSecond,
			Config.Effects.fovKick.decayPerSecond
		)
	end
	Harness.eq(s.trauma, 0)
	Harness.eq(s.fov, 0)
end)

Harness.test("small bumps stay small: shake grows with the square of trauma", function()
	local small, big = ShakeMath.new(), ShakeMath.new()
	small.trauma = 0.1
	big.trauma = 0.5
	local cfg = Config.Effects.shake
	local sx = 0
	local bx = 0
	for i = 1, 100 do
		sx = math.max(sx, math.abs((ShakeMath.sample(small, i * 0.05, cfg))))
		bx = math.max(bx, math.abs((ShakeMath.sample(big, i * 0.05, cfg))))
	end
	Harness.truthy(bx > sx * 10, "a 5x bigger trauma should shake about 25x more")
end)

Harness.test("blast shake falls off with distance", function()
	local f = Config.Effects.falloff
	Harness.eq(ShakeMath.distanceScale(0, f.fullStuds, f.noneStuds), 1)
	Harness.eq(ShakeMath.distanceScale(f.fullStuds, f.fullStuds, f.noneStuds), 1)
	Harness.eq(ShakeMath.distanceScale(f.noneStuds, f.fullStuds, f.noneStuds), 0)
	Harness.eq(ShakeMath.distanceScale(f.noneStuds * 3, f.fullStuds, f.noneStuds), 0)
	local mid = ShakeMath.distanceScale((f.fullStuds + f.noneStuds) / 2, f.fullStuds, f.noneStuds)
	Harness.near(mid, 0.5)
end)

-- ===== recipes =====

local REQUIRED = {
	"blast",
	"containerBreak",
	"containerHit",
	"hit",
	"hitBig",
	"hitSurface",
	"kill",
	"muzzle",
	"orbPop",
	"pickupMine",
	"slideStart",
	"slideStep",
}

Harness.test("every effect the game asks for has a recipe", function()
	local names = Recipes.names()
	for _, need in REQUIRED do
		Harness.truthy(table.find(names, need) ~= nil, "missing recipe " .. need)
	end
end)

Harness.test("every recipe is short and small", function()
	for _, name in Recipes.names() do
		local r = Recipes.resolve(name, { tierColor = "#B58CFF" })
		Harness.truthy(
			Recipes.longestSeconds(r) <= Recipes.maxSeconds,
			name .. " lives longer than " .. Recipes.maxSeconds .. "s"
		)
		Harness.truthy(
			Recipes.particleTotal(r) <= Config.Effects.caps.particles / 2,
			name .. " asks for too many particles at once"
		)
	end
end)

Harness.test("the tier color replaces the placeholder everywhere", function()
	for _, name in Recipes.names() do
		local r = Recipes.resolve(name, { tierColor = "#B58CFF" })
		for _, g in r.particles do
			for _, c in g.colors do
				Harness.truthy(c ~= Recipes.tierPlaceholder, name .. " still has " .. c)
			end
		end
		for _, s in r.stars do
			Harness.truthy(
				s.fill ~= Recipes.tierPlaceholder,
				name .. " star still has a placeholder"
			)
		end
		for _, ring in r.rings do
			Harness.truthy(
				ring.color ~= Recipes.tierPlaceholder,
				name .. " ring still has a placeholder"
			)
		end
	end
end)

Harness.test("Fewer flashes drops strobing stars and the screen flash, keeps the rest", function()
	local strobes = 0
	for _, name in Recipes.names() do
		local base = Recipes.resolve(name, {})
		local calm = Recipes.resolve(name, { reduceFlashes = true })
		Harness.eq(calm.flash or 0, 0, name .. " still flashes the screen")
		for _, s in calm.stars do
			Harness.truthy(s.strobe ~= true, name .. " still has a strobe star")
		end
		for _, s in base.stars do
			if s.strobe == true then
				strobes += 1
			end
		end
		Harness.eq(#calm.particles, #base.particles, name .. " lost particles")
		Harness.truthy(#calm.stars <= #base.stars)
	end
	Harness.truthy(
		strobes > 0,
		"the muzzle flash should be a strobe star, or this rule tests nothing"
	)
end)

Harness.test("resolve copies: playing a recipe never changes the recipe", function()
	local before = Recipes.recipes.blast.particles[1].count
	local r = Recipes.resolve("blast", { scale = 0.25 })
	r.particles[1].count = 9999
	Harness.eq(Recipes.recipes.blast.particles[1].count, before)
end)

Harness.test("a busy arena halves the bursts but never to nothing", function()
	local full = Recipes.resolve("kill", { scale = 1 })
	local half = Recipes.resolve("kill", { scale = 0.5 })
	Harness.truthy(Recipes.particleTotal(half) < Recipes.particleTotal(full))
	Harness.truthy(Recipes.particleTotal(half) > 0)
	for _, g in half.particles do
		Harness.truthy(g.count >= 1)
	end
end)

Harness.test("an unknown recipe name is an error, not a silent nothing", function()
	local ok = pcall(Recipes.resolve, "nope", {})
	Harness.eq(ok, false)
end)

Harness.test("recipe shake and fov keys are real config keys", function()
	local trauma = Config.Effects.trauma :: { [string]: number }
	local fov = Config.Effects.fovKick :: { [string]: number }
	for _, name in Recipes.names() do
		local r = Recipes.resolve(name, {})
		if r.shake ~= nil then
			Harness.truthy(trauma[r.shake] ~= nil, name .. " uses unknown shake " .. r.shake)
		end
		if r.fov ~= nil then
			Harness.truthy(fov[r.fov] ~= nil, name .. " uses unknown fov kick " .. r.fov)
		end
	end
end)

-- ===== config =====

Harness.test("effect caps line up with the performance caps", function()
	Harness.eq(Config.Effects.caps.numbers, Config.Perf.maxDamageNumbers)
	Harness.eq(Config.Effects.caps.parts, Config.Perf.maxLiveEffects)
	Harness.truthy(Config.Effects.caps.particles > 0)
	Harness.truthy(Config.Effects.caps.banners >= 1)
end)

Harness.test("shake is gentle: the camera never leaves its place by more than a stud", function()
	Harness.truthy(Config.Effects.shake.maxOffsetStuds <= 1)
	Harness.truthy(Config.Effects.shake.maxRollDegrees <= 2)
	Harness.truthy(Config.Effects.fovKick.maxDegrees <= 6)
end)

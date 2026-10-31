--!strict
-- Feel pass 2: health that comes back, always-run, aim help on the phone, and the 5 minute clock.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RegenRules = require("../src/shared/RegenRules")
local AimAssist = require("../src/shared/AimAssist")
local ZoneModel = require("../src/server/Zone/ZoneModel")

local cfg = Config.Regen

local function rules()
	return RegenRules.new(cfg)
end

-- Runs the rules once per tick for `seconds`, with the fighter at `hp`, healing as the server would.
local function run(r: any, hp: number, max: number, from: number, seconds: number): (number, number)
	local now = from
	local last = from + seconds
	local tick = cfg.tickSeconds
	while now < last - 1e-9 do
		now += tick
		local give = r:step("a", hp, max, now)
		hp = math.min(max, hp + give)
		r:applied("a", hp)
	end
	return hp, now
end

Harness.test("regen: on by default, with the quiz numbers", function()
	Harness.truthy(cfg.enabled)
	Harness.eq(cfg.delaySeconds, 5)
	Harness.eq(cfg.perSecond, 4)
end)

Harness.test("regen: a full bar gets nothing", function()
	local r = rules()
	Harness.eq(r:step("a", 100, 100, 0), 0)
	Harness.eq(r:step("a", 100, 100, 10), 0)
end)

Harness.test("regen: nothing during the wait after a hit", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	Harness.eq(r:step("a", 60, 100, 1), 0, "just hurt")
	local hp, now = run(r, 60, 100, 1, cfg.delaySeconds - 0.6)
	Harness.eq(hp, 60, "still waiting")
	Harness.truthy(now < 1 + cfg.delaySeconds)
end)

Harness.test("regen: after the wait it gives 4 a second, whole points", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	r:step("a", 40, 100, 1)
	local hp, now = run(r, 40, 100, 1, cfg.delaySeconds - cfg.tickSeconds)
	Harness.eq(hp, 40, "still inside the wait")
	local hp2 = run(r, hp, 100, now, 3 + cfg.tickSeconds)
	Harness.eq(hp2, 40 + 12 + 2, "the tick that ends the wait counts, then 3 seconds at 4 a second")
	Harness.eq(hp2 % 1, 0, "never a fraction")
end)

Harness.test("regen: never goes over the top", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	r:step("a", 97, 100, 1)
	local hp = run(r, 97, 100, 1, 30)
	Harness.eq(hp, 100)
end)

Harness.test("regen: a new hit starts the wait over", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	r:step("a", 50, 100, 1)
	local hp, now = run(r, 50, 100, 1, 8)
	Harness.truthy(hp > 50, "it was healing")
	local hurt = hp - 10
	Harness.eq(r:step("a", hurt, 100, now + 0.5), 0, "hurt again")
	local after = run(r, hurt, 100, now + 0.5, cfg.delaySeconds - 1)
	Harness.eq(after, hurt, "waiting again")
end)

Harness.test("regen: zone damage counts as a hit", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	-- Hurt a little every tick (the zone), so the wait never ends.
	local hp = 80
	local now = 0
	for _ = 1, 40 do
		now += cfg.tickSeconds
		hp -= 1
		Harness.eq(r:step("a", hp, 100, now), 0)
		r:applied("a", hp)
	end
end)

Harness.test("regen: the dead and the switched-off get nothing", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	Harness.eq(r:step("a", 0, 100, 20), 0)
	local off = RegenRules.new({ enabled = false, delaySeconds = 0, perSecond = 10 })
	off:step("a", 50, 100, 0)
	Harness.eq(off:step("a", 50, 100, 10), 0)
end)

Harness.test("regen: each fighter has their own wait", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	r:step("b", 100, 100, 0)
	r:step("a", 50, 100, 1)
	r:step("b", 50, 100, 1)
	r:step("a", 50, 100, 6.5)
	Harness.eq(r:step("a", 50, 100, 7), 2, "a waited long enough")
	r:step("b", 20, 100, 6.9)
	Harness.eq(r:step("b", 20, 100, 7), 0, "b was hurt a moment ago")
end)

Harness.test("regen: reset forgets a fighter", function()
	local r = rules()
	r:step("a", 100, 100, 0)
	r:step("a", 10, 100, 1)
	r:reset("a")
	Harness.eq(r:step("a", 10, 100, 2), 0, "first sight again")
end)

Harness.test("regen: the fight is longer than the wait, so it can matter", function()
	Harness.truthy(cfg.delaySeconds * 2 < Config.Match.finalPressureAtSeconds)
	Harness.truthy(cfg.perSecond * 10 < Config.Health.max, "not a full heal in 10 seconds")
end)

-- ===== always run =====

Harness.test("run: the run button is off, everyone has the one speed", function()
	Harness.eq(Config.Sprint.enabled, false)
end)

-- ===== the 5 minute match =====

Harness.test("clock: the whole match is about 5 minutes", function()
	local m = Config.Match.targetMatchSeconds
	Harness.truthy(m >= 285 and m <= 320, `target match is {m}s`)
	Harness.truthy(Config.Match.finalPressureAtSeconds < m)
	Harness.truthy(m < Config.Match.maxActiveSeconds)
end)

Harness.test("clock: only times stretched, the circle is as wide as before", function()
	local live: any = Config.Zone
	local base: any = Config.zoneAt(Config.Arena.scale)
	Harness.eq(live.initialRadius, base.initialRadius)
	for i, stage in live.stages do
		Harness.eq(stage.targetRadius, base.stages[i].targetRadius)
		Harness.truthy(stage.closeAt > base.stages[i].closeAt)
		Harness.near(stage.closeAt / base.stages[i].closeAt, Config.MatchPace, 0.03)
	end
	Harness.eq(live.suddenDeath.targetRadius, base.suddenDeath.targetRadius)
end)

Harness.test(
	"clock: the circle finishes inside the match, sudden death before the safety net",
	function()
		local live: any = Config.Zone
		local timeline = ZoneModel.build(live)
		Harness.truthy(live.suddenDeath.startsAt < Config.Match.maxActiveSeconds)
		Harness.truthy(live.suddenDeath.startsAt > Config.Match.finalPressureAtSeconds - 5)
		local last = ZoneModel.sample(timeline, Config.Match.maxActiveSeconds)
		Harness.near(last.radius, live.suddenDeath.targetRadius, 0.5, "closed by the safety net")
	end
)

-- ===== aim help =====

local assist = Config.AimAssist

Harness.test("aim help: nobody near the aim means the aim stays", function()
	local x, z, pulled = AimAssist.adjust(assist, 0, 0, 1, 0, { { x = 0, z = 20 } }, 34)
	Harness.eq(pulled, false)
	Harness.near(x, 1)
	Harness.near(z, 0)
end)

Harness.test("aim help: a rival just off the aim pulls it toward them", function()
	-- Aiming along +x; the rival is a little toward +z.
	local angle = math.rad(assist.coneDegrees * 0.8)
	local target = { x = 20 * math.cos(angle), z = 20 * math.sin(angle) }
	local x, z, pulled = AimAssist.adjust(assist, 0, 0, 1, 0, { target }, 34)
	Harness.eq(pulled, true)
	local after = math.atan2(z, x)
	Harness.truthy(after > 0 and after < angle, "leans toward them but not past")
	Harness.near(after, angle * assist.strength, 1e-6)
	Harness.near(math.sqrt(x * x + z * z), 1, 1e-9, "still a unit aim")
end)

Harness.test("aim help: works on the other side of the aim too", function()
	local angle = -math.rad(assist.coneDegrees * 0.5)
	local target = { x = 15 * math.cos(angle), z = 15 * math.sin(angle) }
	local x, z, pulled = AimAssist.adjust(assist, 0, 0, 1, 0, { target }, 34)
	Harness.eq(pulled, true)
	Harness.truthy(math.atan2(z, x) < 0)
end)

Harness.test("aim help: too wide, too far, or behind does nothing", function()
	local wide = math.rad(assist.coneDegrees + 5)
	local _, _, a = AimAssist.adjust(
		assist,
		0,
		0,
		1,
		0,
		{ { x = 20 * math.cos(wide), z = 20 * math.sin(wide) } },
		34
	)
	Harness.eq(a, false, "outside the cone")
	local _, _, b = AimAssist.adjust(assist, 0, 0, 1, 0, { { x = 50, z = 1 } }, 34)
	Harness.eq(b, false, "out of reach")
	local _, _, c = AimAssist.adjust(assist, 0, 0, 1, 0, { { x = -20, z = 0 } }, 34)
	Harness.eq(c, false, "behind")
end)

Harness.test("aim help: picks the rival closest to the aim", function()
	local near = { x = 20 * math.cos(math.rad(3)), z = 20 * math.sin(math.rad(3)) }
	local far = { x = 20 * math.cos(math.rad(10)), z = 20 * math.sin(math.rad(10)) }
	local x, z = AimAssist.adjust(assist, 0, 0, 1, 0, { far, near }, 34)
	Harness.near(math.deg(math.atan2(z, x)), 3 * assist.strength, 1e-6)
end)

Harness.test("aim help: off means no pull, and a bad aim is left alone", function()
	local off = { enabled = false, coneDegrees = 12, strength = 1 }
	local _, _, pulled = AimAssist.adjust(off, 0, 0, 1, 0, { { x = 20, z = 2 } }, 34)
	Harness.eq(pulled, false)
	local x, z, p2 = AimAssist.adjust(assist, 0, 0, 0, 0, { { x = 20, z = 2 } }, 34)
	Harness.eq(p2, false)
	Harness.eq(x, 0)
	Harness.eq(z, 0)
end)

Harness.test("aim help: strength 1 lands right on the rival", function()
	local snap = { enabled = true, coneDegrees = 12, strength = 1 }
	local x, z = AimAssist.adjust(snap, 5, 5, 1, 0, { { x = 25, z = 8 } }, 34)
	Harness.near(math.atan2(z, x), math.atan2(3, 20), 1e-9)
end)

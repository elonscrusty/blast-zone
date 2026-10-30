--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local SprintRules = require("../src/shared/Movement/SprintRules")
local VaultRules = require("../src/shared/Movement/VaultRules")
local SlideBook = require("../src/shared/Movement/SlideBook")
local MoveState = require("../src/client/Movement/MoveState")
local Bindings = require("../src/client/Controls/Bindings")
local Layout = require("../src/client/Hud/Layout")
local RemoteDefs = require("../src/shared/RemoteDefs")

local cfg = Config.Sprint

-- Runs the sprint for `seconds` in 0.1 s ticks, starting at clock `t0`. Returns the clock after.
local function run(s: SprintRules.State, seconds: number, t0: number, moving: boolean?): number
	local t = t0
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		t += 0.1
		SprintRules.step(s, cfg, 0.1, t, moving ~= false, true)
	end
	return t
end

Harness.test("sprint: running empties the breath in the set time, then stops", function()
	local s = SprintRules.new()
	Harness.eq(SprintRules.request(s, cfg, true), true)
	local t = run(s, cfg.staminaSeconds - 0.5, 0)
	Harness.truthy(s.running)
	Harness.truthy(s.stamina > 0)
	run(s, 1, t)
	Harness.eq(s.running, false)
	Harness.eq(s.locked, true)
	Harness.eq(s.wants, false)
	Harness.near(s.stamina, 0, 0.001)
end)

Harness.test("sprint: a winded runner cannot start until breath is back", function()
	local s = SprintRules.new()
	SprintRules.request(s, cfg, true)
	local t = run(s, cfg.staminaSeconds + 0.5, 0)
	Harness.eq(SprintRules.request(s, cfg, true), false)
	t = run(s, cfg.regenSeconds * cfg.restartAt + cfg.regenDelaySeconds + 0.3, t)
	Harness.eq(SprintRules.request(s, cfg, true), true)
	Harness.truthy(s.stamina >= cfg.restartAt)
	run(s, 0.3, t)
	Harness.truthy(s.running)
end)

Harness.test(
	"sprint: standing still or being out of a fight costs no breath and does not run",
	function()
		local s = SprintRules.new()
		SprintRules.request(s, cfg, true)
		run(s, 2, 0, false)
		Harness.eq(s.running, false)
		Harness.near(s.stamina, 1, 0.0001)
		SprintRules.step(s, cfg, 0.1, 5, true, false)
		Harness.eq(s.wants, false) -- dead or not in a fight: the wish is dropped
		Harness.eq(s.running, false)
	end
)

Harness.test("sprint: a shot slows you to a walk for a moment, then you run again", function()
	local s = SprintRules.new()
	SprintRules.request(s, cfg, true)
	local t = run(s, 0.5, 0)
	Harness.truthy(s.running)
	SprintRules.noteFire(s, t)
	t = run(s, 0.2, t)
	Harness.eq(s.running, false)
	run(s, cfg.afterFireSeconds, t)
	Harness.truthy(s.running)
end)

Harness.test("sprint: breath comes back only after a short pause", function()
	local s = SprintRules.new()
	SprintRules.request(s, cfg, true)
	local t = run(s, 1.5, 0)
	local low = s.stamina
	SprintRules.request(s, cfg, false)
	t = run(s, cfg.regenDelaySeconds - 0.3, t)
	Harness.near(s.stamina, low, 0.0001)
	run(s, 1, t)
	Harness.truthy(s.stamina > low)
	Harness.truthy(s.stamina <= 1)
end)

Harness.test("sprint: speed is boosted, capped, and unchanged when not running", function()
	Harness.eq(SprintRules.speed(20, false, 1.4, 100), 20)
	Harness.near(SprintRules.speed(20, true, 1.4, 100), 28)
	Harness.eq(SprintRules.speed(40, true, 1.4, 45), 45)
	-- the real cap is still a sane multiple of the walk speed
	local cap = Config.Movement.walkSpeed
		* Config.Movement.maxSpeedUpgradeMultiplier
		* cfg.speedMultiplier
	Harness.truthy(cap < Config.Movement.walkSpeed * 3)
end)

Harness.test("vault: only a square-on approach counts", function()
	Harness.eq(VaultRules.headOn(0, 1, 0, -1, 0.5), true) -- walking +Z into a face that points -Z
	Harness.eq(VaultRules.headOn(1, 1, 0, -1, 0.5), true) -- 45 degrees is still fine at 0.5 (0.707)
	Harness.eq(VaultRules.headOn(1, 0, 0, -1, 0.5), false) -- along the wall
	Harness.eq(VaultRules.headOn(0, -1, 0, -1, 0.5), false) -- walking away from it
	Harness.eq(VaultRules.headOn(0, 0, 0, -1, 0.5), false) -- not walking
end)

Harness.test("vault: thin enough hops, thick or backwards ones do not", function()
	Harness.near(VaultRules.depth(0, 2, 6) :: number, 2)
	Harness.eq(VaultRules.depth(0, 7, 6), nil)
	Harness.eq(VaultRules.depth(1, 1, 6), nil)
	Harness.eq(VaultRules.depth(2, 1, 6), nil)
	Harness.eq(VaultRules.depth(0, nil, 6), nil)
end)

Harness.test(
	"vault: the arc starts and ends on the floor and clears the top in the middle",
	function()
		local x0, y0, z0 = VaultRules.arc(0, 3, 0, 0, 3, 8, 5, 0)
		Harness.near(x0, 0)
		Harness.near(y0, 3)
		Harness.near(z0, 0)
		local _, ym, zm = VaultRules.arc(0, 3, 0, 0, 3, 8, 5, 0.5)
		Harness.near(ym, 8)
		Harness.near(zm, 4)
		local _, y1, z1 = VaultRules.arc(0, 3, 0, 0, 3, 8, 5, 1)
		Harness.near(y1, 3)
		Harness.near(z1, 8)
		local _, yOver = VaultRules.arc(0, 3, 0, 0, 3, 8, 5, 1.7) -- past the end stays at the end
		Harness.near(yOver, 3)
	end
)

Harness.test("vault: the peak clears the top but never goes wild", function()
	Harness.near(VaultRules.peak(4, 0, 1, 6.5), 5)
	Harness.eq(VaultRules.peak(0.2, 0, 1, 6.5), 1.5)
	Harness.eq(VaultRules.peak(20, 0, 1, 6.5), 6.5)
end)

Harness.test("vault: an end spot too far away is caught", function()
	local v = Config.Vault
	Harness.eq(VaultRules.endPlausible(0, 0, 0, 6, 6, 20, v.endGrace, v.endTolerance), true)
	Harness.eq(VaultRules.endPlausible(0, 0, 0, 60, 6, 20, v.endGrace, v.endTolerance), false)
end)

Harness.test("vault: the numbers are sane and the hop is not a way over tall walls", function()
	local v = Config.Vault
	Harness.truthy(v.maxHeight < 6 and v.maxHeight >= 3)
	Harness.truthy(v.maxDepth > 0 and v.landingPad > 0)
	Harness.truthy(v.durationSeconds > 0 and v.durationSeconds < 1)
	Harness.truthy(v.cooldownSeconds >= v.durationSeconds)
	Harness.truthy(v.maxPeak > v.clearance)
	-- a hop never takes the body farther than one slide could
	Harness.truthy(v.reach + v.maxDepth + v.landingPad < 20)
	Harness.eq(Config.Tags.Vaultable, "Vaultable")
	Harness.eq(Config.CollisionGroups.Vaulting, "Vaulting")
end)

Harness.test("slide: two charges, one at a time, each back after the cooldown", function()
	local book = SlideBook.new()
	local max = Config.Slide.charges
	Harness.eq(max, 2)
	Harness.eq((book:charges("a", 0, max)), 2)
	book:commit("a", 0, 0.4, 5, max)
	Harness.eq((book:charges("a", 0.5, max)), 1)
	Harness.eq(book:isReady("a", 0.5), true)
	book:commit("a", 0.5, 0.4, 5, max)
	Harness.eq((book:charges("a", 1, max)), 0)
	Harness.eq(book:isReady("a", 1), false)
	Harness.near(book:readyAt("a"), 5)
	Harness.eq(book:check("a", 1, true, true), "cooldown")
	-- the first charge returns at 5, the second at 10
	Harness.eq((book:charges("a", 5.1, max)), 1)
	Harness.eq(book:check("a", 5.1, true, true), nil)
	Harness.eq((book:charges("a", 10.1, max)), 2)
	Harness.eq((book:charges("a", 99, max)), 2) -- never more than the most
end)

Harness.test("slide: one fighter's charges never touch another's", function()
	local book = SlideBook.new()
	book:commit("a", 0, 0.4, 5, 2)
	book:commit("a", 1, 0.4, 5, 2)
	Harness.eq((book:charges("a", 2, 2)), 0)
	Harness.eq((book:charges("b", 2, 2)), 2)
end)

Harness.test("slide: a dead body is not refreshed by cancel", function()
	local book = SlideBook.new()
	book:commit("a", 0, 0.4, 5, 2)
	book:commit("a", 0.5, 0.4, 5, 2)
	book:cancel("a", 1)
	Harness.eq((book:charges("a", 1.1, 2)), 0)
end)

Harness.test(
	"move state: the toggle flips, a winded runner cannot turn it on, locked turns it off",
	function()
		MoveState.clearSprint()
		Harness.eq(MoveState.toggleSprint(), true)
		Harness.eq(MoveState.toggleSprint(), false)
		MoveState.toggleSprint()
		MoveState.setSprint(0, false, true)
		Harness.eq(MoveState.get().wantsSprint, false)
		Harness.eq(MoveState.toggleSprint(), false)
		MoveState.clearSprint()
		Harness.eq(MoveState.get().stamina, 1)
		MoveState.setSlide(5, 2)
		Harness.eq(MoveState.get().slideCharges, 2)
		MoveState.setSlide(-3, 2)
		Harness.eq(MoveState.get().slideCharges, 0)
	end
)

Harness.test("sprint: key, pad and touch button exist and clash with nothing", function()
	local sprint = Bindings.actions.sprint
	Harness.eq(sprint.touch, "sprint")
	Harness.eq(Bindings.actionFor("LeftShift"), "sprint")
	Harness.eq(Bindings.actionFor("ButtonL3"), "sprint")
	local seen: { [string]: string } = {}
	for _, name in Bindings.actionOrder do
		local b = Bindings.actions[name]
		for _, code in b.keyboard do
			Harness.eq(seen[code], nil, `{code} is used twice`)
			seen[code] = name
		end
		for _, code in b.gamepad do
			Harness.eq(seen[code], nil, `{code} is used twice`)
			seen[code] = name
		end
	end
	local r = Layout.regions.sprint
	Harness.truthy(r.w >= Layout.MIN_TOUCH and r.h >= Layout.MIN_TOUCH)
	Harness.eq(r.w, r.h)
	Harness.truthy(Layout.circles.sprint)
end)

Harness.test("fast feet: the new remotes are listed and the client may only ask", function()
	local byName = RemoteDefs.byName
	for _, name in { "SprintRequest", "VaultRequest" } do
		Harness.truthy(byName[name], name)
		Harness.eq(byName[name].direction, "toServer", name)
	end
	for _, name in { "SprintState", "VaultFx", "VaultDenied" } do
		Harness.truthy(byName[name], name)
		Harness.eq(byName[name].direction, "toClient", name)
	end
end)

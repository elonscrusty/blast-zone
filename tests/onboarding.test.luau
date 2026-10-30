--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Bindings = require("../src/client/Controls/Bindings")
local IntroSteps = require("../src/client/Onboarding/IntroSteps")
local DataNotice = require("../src/client/Onboarding/DataNotice")
local OnboardingModel = require("../src/client/Onboarding/OnboardingModel")

local cfg = Config.Onboarding

local ctx: IntroSteps.Context = {
	slideKey = Bindings.actions.slide.keyboard[1],
	slideButton = Bindings.actions.slide.gamepad[1],
	slideSeconds = Config.Slide.cooldown,
}

Harness.test("intro teaches move, aim, fire, slide in that order on every device", function()
	for _, device in { "touch", "keyboard", "gamepad" } do
		local steps = IntroSteps.build(device :: IntroSteps.Device, ctx)
		Harness.eq(#steps, 4)
		Harness.eq(steps[1].id, "move")
		Harness.eq(steps[2].id, "aim")
		Harness.eq(steps[3].id, "fire")
		Harness.eq(steps[4].id, "slide")
		for _, s in steps do
			Harness.truthy(#s.text > 0 and #s.text <= 40, `{device}/{s.id} text length`)
		end
	end
end)

Harness.test("slide words use the real binding and the real cooldown", function()
	local keyboard = IntroSteps.build("keyboard", ctx)[4].text
	Harness.truthy(string.find(keyboard, Bindings.actions.slide.keyboard[1], 1, true), keyboard)
	Harness.truthy(string.find(keyboard, tostring(Config.Slide.cooldown), 1, true), keyboard)
	local pad = IntroSteps.build("gamepad", ctx)[4].text
	Harness.truthy(string.find(pad, "Press A ", 1, true), pad)
	local touch = IntroSteps.build("touch", ctx)[4].text
	Harness.truthy(string.find(touch, "SLIDE", 1, true), touch)
	local half = IntroSteps.build(
		"touch",
		{ slideKey = "Space", slideButton = "ButtonA", slideSeconds = 2.5 }
	)
	Harness.truthy(string.find(half[4].text, "2.5 s", 1, true), half[4].text)
end)

Harness.test("every control named in the intro has a touch button", function()
	-- CLAUDE.md: phone first. The touch words must not mention keys, and the slide action has a widget.
	for _, s in IntroSteps.build("touch", ctx) do
		Harness.eq(string.find(s.text, "WASD", 1, true), nil, s.id)
		Harness.eq(string.find(s.text, "mouse", 1, true), nil, s.id)
	end
	Harness.truthy(Bindings.actions.slide.touch ~= "")
end)

Harness.test("config: intro flag is the one piece 17 seeds", function()
	Harness.eq(cfg.introFlag, "introSeen")
	Harness.truthy(cfg.slowLoadSeconds > 0 and cfg.retryCooldownSeconds > 0)
end)

Harness.test(
	"notice words: failed keeps the promise, lost has no retry, slow load waits",
	function()
		local failed = DataNotice.forStatus("failed", false) :: DataNotice.Notice
		Harness.eq(failed.kind, "bad")
		Harness.eq(failed.button, "TRY AGAIN")
		Harness.truthy(string.find(failed.body, "safe", 1, true))
		local lost = DataNotice.forStatus("lost", false) :: DataNotice.Notice
		Harness.eq(lost.button, nil)
		Harness.eq(DataNotice.forStatus("ready", false), nil)
		Harness.eq(DataNotice.forStatus("none", true), nil)
		Harness.eq(DataNotice.forStatus("loading", false), nil)
		local slow = DataNotice.forStatus("loading", true) :: DataNotice.Notice
		Harness.eq(slow.kind, "wait")
	end
)

Harness.test("new player in a ready save sees the intro once, in the lobby only", function()
	local m = OnboardingModel.new(true, 0)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false) -- still loading
	OnboardingModel.applyStatus(m, { state = "ready", flags = {} }, 1)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false) -- phase not known yet
	OnboardingModel.setPhase(m, "Waiting")
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), true)
	OnboardingModel.setPhase(m, "Countdown")
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false)
	OnboardingModel.setPhase(m, "Waiting")
	Harness.eq(OnboardingModel.finishIntro(m), true) -- ask the server to save the flag
	Harness.eq(OnboardingModel.finishIntro(m), false) -- second tap asks nothing
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false)
end)

Harness.test("returning player (flag set) never sees the intro", function()
	local m = OnboardingModel.new(true, 0)
	OnboardingModel.setPhase(m, "Waiting")
	OnboardingModel.applyStatus(m, { state = "ready", flags = { introSeen = true } }, 1)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false)
end)

Harness.test("failed load: intro still shows once, and nothing is asked of the server", function()
	local m = OnboardingModel.new(true, 0)
	OnboardingModel.setPhase(m, "Waiting")
	OnboardingModel.applyStatus(m, { state = "failed", flags = { introSeen = true } }, 3)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), true) -- flags from a failed load are not trusted
	Harness.eq(OnboardingModel.finishIntro(m), false)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false)
end)

Harness.test("save arrives while the intro is open: a late flag does not close it", function()
	local m = OnboardingModel.new(true, 0)
	OnboardingModel.setPhase(m, "Waiting")
	OnboardingModel.applyStatus(m, { state = "ready", flags = {} }, 1)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), true)
	-- a repeat status with the same content must not hide or re-show it
	OnboardingModel.applyStatus(m, { state = "ready", flags = {} }, 2)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), true)
end)

Harness.test("no save system: intro once per join, no notice, no write", function()
	local m = OnboardingModel.new(false, 0)
	OnboardingModel.setPhase(m, "Waiting")
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), true)
	Harness.eq(OnboardingModel.notice(m, cfg, 100), nil)
	Harness.eq(OnboardingModel.finishIntro(m), false)
	Harness.eq(OnboardingModel.shouldShowIntro(m, cfg), false)
end)

Harness.test("slow load shows a waiting notice after the limit, and only then", function()
	local m = OnboardingModel.new(true, 10)
	Harness.eq(OnboardingModel.notice(m, cfg, 10 + cfg.slowLoadSeconds - 1), nil)
	local n = OnboardingModel.notice(m, cfg, 10 + cfg.slowLoadSeconds) :: DataNotice.Notice
	Harness.eq(n.kind, "wait")
	-- a repeated "loading" does not restart the clock
	OnboardingModel.applyStatus(m, { state = "loading" }, 20)
	Harness.truthy(OnboardingModel.notice(m, cfg, 10 + cfg.slowLoadSeconds) ~= nil)
	OnboardingModel.applyStatus(m, { state = "ready", flags = {} }, 30)
	Harness.eq(OnboardingModel.notice(m, cfg, 40), nil)
end)

Harness.test(
	"retry button: only when failed, with a wait between taps, and recovery clears it",
	function()
		local m = OnboardingModel.new(true, 0)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 1), false)
		OnboardingModel.applyStatus(m, { state = "failed" }, 2)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 2), true)
		OnboardingModel.markRetry(m, cfg, 2)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 3), false)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 2 + cfg.retryCooldownSeconds), true)
		OnboardingModel.applyStatus(m, { state = "ready", flags = {} }, 8)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 100), false)
		Harness.eq(OnboardingModel.notice(m, cfg, 100), nil)
		-- lost has no button, so never a retry
		OnboardingModel.applyStatus(m, { state = "lost" }, 9)
		Harness.eq(OnboardingModel.canRetry(m, cfg, 100), false)
	end
)

Harness.test("bad status payloads are ignored and never crash", function()
	local m = OnboardingModel.new(true, 0)
	OnboardingModel.applyStatus(m, nil, 1)
	OnboardingModel.applyStatus(m, "ready", 1)
	OnboardingModel.applyStatus(m, { state = "banana" }, 1)
	OnboardingModel.applyStatus(
		m,
		{ state = "ready", flags = { 5, introSeen = "yes", x = true } },
		2
	)
	Harness.eq(m.status, "ready")
	Harness.eq(m.flags.introSeen, nil) -- only literal true counts
	Harness.eq(m.flags.x, true)
end)

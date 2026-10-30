--!strict
-- Wires the first-time intro and the "data did not load" strip to the game.
--   Save status: piece 17's `ProfileStatus` remote ({ state, flags }). We ask once at start
--   (`ProfileStatusRequest`) so a late join never misses it. The server owns the save; we only
--   show words, ask `RetryProfileLoadRequest`, and ask `SetFlagRequest("introSeen", true)`.
--   Until piece 17 lands (no such remote), the intro shows once per join and nothing is saved.
--   Phase: the same `MatchState` the match screens read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local RemoteDefs = require(Shared.RemoteDefs)

local Net = require(script.Parent.Parent.Core.Net)
local Bindings = require(script.Parent.Parent.Controls.Bindings)
local Controls = require(script.Parent.Parent.Controls.Controls)
local DataNotice = require(script.Parent.DataNotice)
local IntroSteps = require(script.Parent.IntroSteps)
local IntroView = require(script.Parent.IntroView)
local OnboardingModel = require(script.Parent.OnboardingModel)
local StatusStripView = require(script.Parent.StatusStripView)

local OnboardingClientSystem = {}
OnboardingClientSystem.order = 70

local cfg: OnboardingModel.Config = Config.Onboarding

local function remoteExists(name: string, direction: string): boolean
	local def = RemoteDefs.byName[name]
	return def ~= nil and def.direction == direction
end

-- The notice shows between matches. During a match the HUD owns the top of the screen.
local function noticeVisible(phase: string): boolean
	return phase ~= MatchPhase.Spawning
		and phase ~= MatchPhase.Active
		and phase ~= MatchPhase.FinalPressure
end

function OnboardingClientSystem.start()
	local hasSave = remoteExists("ProfileStatus", "toClient")
		and remoteExists("SetFlagRequest", "toServer")
	local model = OnboardingModel.new(hasSave, os.clock())

	local function context(): IntroSteps.Context
		return {
			slideKey = Bindings.actions.slide.keyboard[1],
			slideButton = Bindings.actions.slide.gamepad[1],
			slideSeconds = Config.Slide.cooldown,
		}
	end

	local function steps(): { IntroSteps.Step }
		return IntroSteps.build(Controls.device(), context())
	end

	local function sendRetry()
		local now = os.clock()
		if not OnboardingModel.canRetry(model, cfg, now) then
			return
		end
		OnboardingModel.markRetry(model, cfg, now)
		if remoteExists("RetryProfileLoadRequest", "toServer") then
			Net.send("RetryProfileLoadRequest")
		end
	end

	local function onIntroDone(_skipped: boolean)
		if OnboardingModel.finishIntro(model) and remoteExists("SetFlagRequest", "toServer") then
			Net.send("SetFlagRequest", cfg.introFlag, true)
		end
	end

	local function refresh()
		local now = os.clock()
		local wantIntro = OnboardingModel.shouldShowIntro(model, cfg)
		if wantIntro and not IntroView.isOpen() then
			IntroView.show(steps(), onIntroDone)
		elseif not wantIntro and IntroView.isOpen() then
			IntroView.hide() -- a match began or the save said we already know: not marked seen here
		end
		StatusStripView.set(
			OnboardingModel.notice(model, cfg, now),
			noticeVisible(model.phase),
			sendRetry
		)
	end

	Net.on("MatchState", function(state: any)
		if type(state) == "table" and type(state.phase) == "string" then
			OnboardingModel.setPhase(model, state.phase)
			refresh()
		end
	end)

	if hasSave then
		Net.on("ProfileStatus", function(payload: any)
			OnboardingModel.applyStatus(model, payload, os.clock())
			refresh()
		end)
		if remoteExists("ProfileStatusRequest", "toServer") then
			Net.send("ProfileStatusRequest")
		end
	end

	Controls.DeviceChanged:connect(function()
		if IntroView.isOpen() then
			IntroView.setSteps(steps())
		end
	end)

	-- The slow-load words appear by the clock, not by a message, so check once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			if model.status == "loading" then
				refresh()
			end
		end
	end)

	refresh()
end

return OnboardingClientSystem

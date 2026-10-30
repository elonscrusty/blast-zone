--!strict
-- Decisions for the first-time intro and the data notice, with no Roblox calls so Lune can test it.
-- The server (piece 17) owns the save. This only decides what to show and when to ask.
--
-- Rules:
--   * The intro shows only in the lobby (phase Waiting), only once per join, and only when the
--     save has said "introSeen" is not set. While loading we wait (the notice covers slow loads).
--   * If the save failed or was lost we still show the intro once (we cannot tell who is new).
--     It is skippable. Nothing is written.
--   * Done or Skip both mean "seen". The flag is asked for only when the save is ready.
--   * With no save system installed ("none") the intro shows once per join and nothing is saved.

local DataNotice = require("./DataNotice")

export type Config = {
	introFlag: string,
	slowLoadSeconds: number,
	retryCooldownSeconds: number,
}

export type Model = {
	status: DataNotice.Status,
	flags: { [string]: boolean },
	introDone: boolean, -- finished or skipped in this join
	loadingSince: number?,
	nextRetryAt: number,
	phase: string,
}

local OnboardingModel = {}

function OnboardingModel.new(hasSaveSystem: boolean, now: number): Model
	return {
		status = if hasSaveSystem then "loading" else "none",
		flags = {},
		introDone = false,
		loadingSince = if hasSaveSystem then now else nil,
		nextRetryAt = 0,
		phase = "Waiting",
	}
end

-- payload is untrusted shape from the ProfileStatus remote: { state: string, flags: { [string]: boolean }? }
function OnboardingModel.applyStatus(m: Model, payload: any, now: number)
	if type(payload) ~= "table" or not DataNotice.isStatus(payload.state) then
		return
	end
	local state = payload.state :: DataNotice.Status
	if state == "loading" then
		if m.status ~= "loading" then
			m.loadingSince = now
		end
	else
		m.loadingSince = nil
	end
	m.status = state
	local flags: { [string]: boolean } = {}
	if type(payload.flags) == "table" then
		for k, v in payload.flags do
			if type(k) == "string" and v == true then
				flags[k] = true
			end
		end
	end
	m.flags = flags
end

function OnboardingModel.setPhase(m: Model, phase: string)
	m.phase = phase
end

function OnboardingModel.isSlow(m: Model, cfg: Config, now: number): boolean
	return m.status == "loading"
		and m.loadingSince ~= nil
		and now - m.loadingSince >= cfg.slowLoadSeconds
end

function OnboardingModel.notice(m: Model, cfg: Config, now: number): DataNotice.Notice?
	return DataNotice.forStatus(m.status, OnboardingModel.isSlow(m, cfg, now))
end

function OnboardingModel.shouldShowIntro(m: Model, cfg: Config): boolean
	if m.introDone or m.phase ~= "Waiting" or m.status == "loading" then
		return false
	end
	if m.status == "ready" and m.flags[cfg.introFlag] == true then
		return false
	end
	return true
end

-- Returns true when the caller should now ask the server to save the flag.
function OnboardingModel.finishIntro(m: Model): boolean
	if m.introDone then
		return false
	end
	m.introDone = true
	return m.status == "ready"
end

-- The retry button is visible only while the notice has one, and waits between taps.
function OnboardingModel.canRetry(m: Model, cfg: Config, now: number): boolean
	local n = OnboardingModel.notice(m, cfg, now)
	return n ~= nil and n.button ~= nil and now >= m.nextRetryAt
end

function OnboardingModel.markRetry(m: Model, cfg: Config, now: number)
	m.nextRetryAt = now + cfg.retryCooldownSeconds
end

return OnboardingModel

--!strict
-- Decides which analytics events to send. Pure: the sink does the real sending (Roblox AnalyticsService).
-- Privacy: only counts and short labels (cause, gun id, step). Never names, user ids, chat or positions.

export type Sink = {
	custom: (player: any, eventName: string, value: number, fields: { string }) -> (),
	funnel: (player: any, step: number, stepName: string) -> (),
}

export type Participant = { id: string, kind: string, player: any?, alive: boolean }

local AnalyticsTracker = {}
AnalyticsTracker.__index = AnalyticsTracker

-- Order matters: the number is the funnel step. Other pieces call `funnelStep(player, name)` with one of these.
AnalyticsTracker.FunnelSteps = { "joined", "pressedPlay", "firstMatchStarted", "firstElimination", "firstMatchEnded" }

AnalyticsTracker.Events = {
	matchStart = "match_start",
	matchEnd = "match_end",
	death = "death",
	gunPick = "gun_pick",
}

local KNOWN_CAUSES = { bullet = true, explosion = true, zone = true, disconnect = true, other = true }

function AnalyticsTracker.new(sink: Sink, knownGuns: { string }, clock: () -> number): any
	local guns = {}
	for _, id in knownGuns do
		guns[id] = true
	end
	return setmetatable({
		_sink = sink,
		_guns = guns,
		_clock = clock,
		_sentSteps = {} :: { [any]: { [string]: boolean } },
		_matchStartedAt = 0,
		_matchId = 0,
	}, AnalyticsTracker)
end

local function humans(list: { Participant }): { Participant }
	local out = {}
	for _, p in list do
		if p.kind == "player" and p.player ~= nil then
			table.insert(out, p)
		end
	end
	return out
end

-- One event per human, so the dashboard counts players. Bot count rides along as a label.
function AnalyticsTracker.matchStarted(self: any, matchId: number, participants: { Participant })
	self._matchId = matchId
	self._matchStartedAt = self._clock()
	local all = #participants
	local people = humans(participants)
	for _, p in people do
		self._sink.custom(p.player, AnalyticsTracker.Events.matchStart, all, { `bots{all - #people}` })
		self:funnelStep(p.player, "firstMatchStarted")
	end
end

-- outcome: "win" | "draw" | "abandoned" (from the match results). Survivors of a win get "win", the rest "out".
function AnalyticsTracker.matchEnded(self: any, matchId: number, participants: { Participant }, outcome: string)
	if matchId ~= self._matchId then
		return
	end
	local seconds = math.floor(math.max(0, self._clock() - self._matchStartedAt))
	for _, p in humans(participants) do
		local result = if outcome == "win" and p.alive then "win" elseif outcome == "win" then "out" else outcome
		self._sink.custom(p.player, AnalyticsTracker.Events.matchEnd, seconds, { result })
		self:funnelStep(p.player, "firstMatchEnded")
	end
end

-- Counts deaths of human players by cause. killer is "player", "bot" or "none".
function AnalyticsTracker.died(self: any, player: any, cause: string, killer: string, weaponId: string?)
	local safeCause = if KNOWN_CAUSES[cause] then cause else "other"
	local weapon = if weaponId and self._guns[weaponId] then weaponId else "none"
	self._sink.custom(player, AnalyticsTracker.Events.death, 1, { safeCause, killer, weapon })
	self:funnelStep(player, "firstElimination")
end

-- Which gun a player chose. Unknown ids are counted as "other" so a bad id cannot make new event labels.
function AnalyticsTracker.gunPicked(self: any, player: any, gunId: string)
	local label = if self._guns[gunId] then gunId else "other"
	self._sink.custom(player, AnalyticsTracker.Events.gunPick, 1, { label })
end

-- Each step is sent once per player per session (the funnel counts people, not repeats).
function AnalyticsTracker.funnelStep(self: any, player: any, stepName: string)
	local number = table.find(AnalyticsTracker.FunnelSteps, stepName)
	if number == nil then
		return
	end
	local sent = self._sentSteps[player]
	if sent == nil then
		sent = {}
		self._sentSteps[player] = sent
	end
	if sent[stepName] then
		return
	end
	sent[stepName] = true
	self._sink.funnel(player, number, stepName)
end

function AnalyticsTracker.forget(self: any, player: any)
	self._sentSteps[player] = nil
end

return AnalyticsTracker

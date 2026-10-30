--!strict
-- The match state machine (brief §16). No Roblox objects in here, so Lune can run whole matches in a blink.
-- MatchSystem.luau plugs it into Players, remotes and the arena.
--
--   Waiting -> Countdown -> Spawning -> Active -> FinalPressure -> Finished -> Results -> Resetting -> Waiting
--
-- It drives the shared MatchContext (phase + matchId) and the shared roster (Core/Participants). It is the only
-- caller of ctx:beginMatch() / ctx:setPhase() and the only one that enrolls and clears participants.
-- Time: it reads `deps.clock` (os.clock on the server). The roster and context use the same clock.
--
-- Identity: ids are "p<userId>" / "b<n>". Everything carries a matchId, and anything from an old match is dropped.

export type Point = { x: number, y: number, z: number }

export type Row = {
	participantId: string,
	displayName: string,
	isBot: boolean,
	placement: number,
	eliminations: number,
	survivedSeconds: number,
}

export type Outcome = "win" | "draw" | "abandoned"

export type Result = {
	matchId: number,
	outcome: Outcome,
	winnerId: string?,
	reason: string, -- "last_standing" | "timeout" | "forfeit"
	rows: { Row }, -- best first
	activeSeconds: number,
}

export type World = {
	getSpawnPoints: () -> { Point },
	getCenter: () -> Point,
	-- Put a participant on its spawn. Players: load/move the character. Bots: nothing (piece 09 listens).
	place: (participant: any, point: Point, lookAt: Point) -> (),
	-- Remove characters and effects, reset the arena. Called once per match, in Resetting.
	cleanup: (participants: { any }) -> (),
	publish: (state: any) -> (), -- PublicMatchState for every client
	announce: (kind: string, text: string) -> (),
	sendEliminated: (payload: any) -> (), -- everyone sees who fell (public info)
	sendResults: (id: string, payload: any) -> (),
	sendSpectate: (id: string, targetId: string?) -> (),
	grantReward: (id: string, amount: number, place: number, matchId: number) -> (),
	toServerTime: (t: number) -> number, -- clock time -> workspace:GetServerTimeNow() time
	random: ((n: number) -> number)?,
	log: ((message: string) -> ())?,
}

export type Deps = {
	config: any, -- shared Config
	rules: any, -- MatchRules
	ctx: any, -- shared MatchContext instance
	registry: any, -- shared ParticipantRegistry instance
	phases: any, -- shared MatchPhase
	ids: any, -- shared Ids
	clock: () -> number,
	world: World,
}

export type Controller = {
	update: () -> (),
	addHuman: (player: any, userId: number, name: string) -> (),
	removeHuman: (id: string) -> (),
	setReady: (id: string, ready: boolean) -> (),
	requestBots: (count: number) -> number,
	onEliminated: (event: any) -> (),
	cycleSpectate: (id: string, step: number) -> (),
	enterFinalPressure: (matchId: number) -> (),
	claimResults: (id: string, matchId: number) -> boolean,
	getResult: () -> Result?,
	getBotsRequested: () -> number,
	isReady: (id: string) -> boolean,
}

type Human = {
	id: string,
	player: any,
	userId: number,
	name: string,
	ready: boolean,
	decision: string?,
}
type Departed = { id: string, name: string, eliminatedAt: number, forfeit: boolean }

local MatchController = {}

function MatchController.new(deps: Deps): Controller
	local cfg = deps.config
	local M = cfg.Match
	local rules, ctx, registry, phases, world, clock =
		deps.rules, deps.ctx, deps.registry, deps.phases, deps.world, deps.clock

	local humans: { [string]: Human } = {}
	local humanOrder: { string } = {}
	local pendingIds: { string } = {} -- ready humans gathered during Countdown
	local botsRequested = 0
	local botsPlanned = 0 -- frozen when the Countdown begins
	local gatherStart: number? = nil
	local note = "press_play"
	local blocked = false

	-- Per-match record (cleared in Resetting)
	local kills: { [string]: number } = {}
	local departed: { Departed } = {}
	local humanParticipants: { [string]: boolean } = {} -- human ids that were enrolled this match
	local startedTotal = 0
	local activeStartedAt: number? = nil
	local settleUntil: number? = nil
	local resultsStartedAt: number? = nil
	local result: Result? = nil
	local pendingRewards: { [string]: { amount: number, place: number } } = {}
	local spectateTarget: { [string]: string } = {}
	local ledger = rules.newLedger()
	local lastKey = ""

	local self = {} :: Controller

	local function log(message: string)
		if world.log then
			world.log(message)
		end
	end

	local function phase(): string
		return ctx:getPhase()
	end

	local function totalNow(): number
		if phase() == phases.Countdown then
			return #pendingIds + botsPlanned
		end
		return startedTotal
	end

	local function publish()
		local endsAt: number? = ctx:getPhaseEndsAt()
		local state = {
			matchId = ctx:getMatchId(),
			phase = phase(),
			phaseEndsAt = if endsAt then world.toServerTime(endsAt) else nil,
			aliveCount = registry:aliveCount(),
			totalCount = totalNow(),
			serverNow = world.toServerTime(clock()),
			note = note,
		}
		local key =
			`{state.matchId}|{state.phase}|{endsAt or 0}|{state.aliveCount}|{state.totalCount}|{note}`
		if key == lastKey then
			return
		end
		lastKey = key
		world.publish(state)
	end

	local function setPhase(new: string, seconds: number?, newNote: string): boolean
		local ok = ctx:setPhase(new, seconds)
		if not ok then
			log(`illegal phase move {phase()} -> {new}`)
			return false
		end
		note = newNote
		publish()
		return true
	end

	local function readyHumanIds(): { string }
		local out: { string } = {}
		for _, id in humanOrder do
			if humans[id].ready then
				table.insert(out, id)
			end
		end
		return out
	end

	local function presentHumanParticipants(): number
		local n = 0
		for id in humanParticipants do
			if humans[id] then
				n += 1
			end
		end
		return n
	end

	-- ===== spectating (server decides who watches whom) =====
	local function canSpectate(id: string): boolean
		if not cfg.Features.spectate or not humans[id] then
			return false
		end
		local p = phase()
		if not (p == phases.Spawning or phases.isCombat(p) or p == phases.Finished) then
			return false
		end
		local mine = registry:get(id)
		return mine == nil or not mine.alive
	end

	local function setTarget(id: string, target: string?)
		if spectateTarget[id] == target then
			return
		end
		spectateTarget[id] = target :: any
		world.sendSpectate(id, target)
	end

	local function refreshSpectators()
		local alive = registry:aliveList()
		for _, id in humanOrder do
			if canSpectate(id) then
				local current = spectateTarget[id]
				local ok = false
				for _, p in alive do
					if p.id == current then
						ok = true
					end
				end
				if not ok then
					local first = alive[1]
					setTarget(id, if first then first.id else nil)
				end
			elseif spectateTarget[id] ~= nil then
				setTarget(id, nil)
			end
		end
	end

	function self.cycleSpectate(id: string, step: number)
		if not canSpectate(id) then
			return
		end
		local aliveIds: { string } = {}
		for _, p in registry:aliveList() do
			table.insert(aliveIds, p.id)
		end
		setTarget(id, rules.cycleTarget(aliveIds, spectateTarget[id], step))
	end

	-- ===== end of match =====
	local function buildResult(reason: string): Result
		local now = clock()
		local entries = {}
		local info: { [string]: { name: string, isBot: boolean, kills: number, out: number } } = {}
		for _, p in registry:list() do
			table.insert(
				entries,
				{ id = p.id, alive = p.alive, left = false, eliminatedAt = p.eliminatedAt }
			)
			info[p.id] = {
				name = p.displayName,
				isBot = p.kind == "bot",
				kills = kills[p.id] or 0,
				out = p.eliminatedAt or now,
			}
		end
		for _, d in departed do
			table.insert(
				entries,
				{ id = d.id, alive = false, left = d.forfeit, eliminatedAt = d.eliminatedAt }
			)
			info[d.id] =
				{ name = d.name, isBot = false, kills = kills[d.id] or 0, out = d.eliminatedAt }
		end
		local ranked = rules.rank(entries, now, M.simultaneousEliminationWindow)
		local start = activeStartedAt or now
		local rows: { Row } = {}
		for _, id in ranked.order do
			local i = info[id]
			table.insert(rows, {
				participantId = id,
				displayName = i.name,
				isBot = i.isBot,
				placement = ranked.place[id],
				eliminations = i.kills,
				survivedSeconds = math.max(0, i.out - start),
			})
		end
		return {
			matchId = ctx:getMatchId(),
			outcome = ranked.outcome,
			winnerId = ranked.winnerId,
			reason = reason,
			rows = rows,
			activeSeconds = math.max(0, now - start),
		}
	end

	local function finish(reason: string)
		if not setPhase(phases.Finished, M.finishedHoldSeconds, "match_over") then
			return
		end
		settleUntil = nil
		result = buildResult(reason)
		refreshSpectators()
	end

	local function toResults()
		local res = result :: Result
		if not setPhase(phases.Results, M.resultsSeconds, "results") then
			return
		end
		resultsStartedAt = clock()
		for _, id in humanOrder do
			if spectateTarget[id] ~= nil then
				setTarget(id, nil)
			end
		end
		local endsAt = ctx:getPhaseEndsAt()
		for _, row in res.rows do
			local forfeit = false
			for _, d in departed do
				if d.id == row.participantId and d.forfeit then
					forfeit = true
				end
			end
			if not row.isBot and not forfeit then
				pendingRewards[row.participantId] = {
					amount = rules.rewardFor(row.placement, row.eliminations, cfg.Rewards),
					place = row.placement,
				}
			end
		end
		for _, id in humanOrder do
			local mine: Row? = nil
			for _, row in res.rows do
				if row.participantId == id then
					mine = row
				end
			end
			local pending = pendingRewards[id]
			world.sendResults(id, {
				matchId = res.matchId,
				rows = res.rows,
				draw = res.outcome ~= "win",
				outcome = res.outcome,
				winnerId = res.winnerId,
				endsAt = if endsAt then world.toServerTime(endsAt) else nil,
				you = if mine
					then {
						placement = mine.placement,
						eliminations = mine.eliminations,
						survivedSeconds = mine.survivedSeconds,
						reward = if pending then pending.amount else 0,
					}
					else nil,
			})
		end
	end

	-- Rewards are granted once: on ClaimResults, or at reset for anyone who did not tap it. The ledger refuses repeats.
	local function grant(id: string, matchId: number): boolean
		local pending = pendingRewards[id]
		if not pending then
			return false
		end
		pendingRewards[id] = nil
		if not ledger:commit(matchId, id, pending.amount) then
			return false
		end
		world.grantReward(id, pending.amount, pending.place, matchId)
		return true
	end

	function self.claimResults(id: string, matchId: number): boolean
		if matchId ~= ctx:getMatchId() then
			return false
		end
		local p = phase()
		if p ~= phases.Results and p ~= phases.Finished then
			return false
		end
		return grant(id, matchId)
	end

	local function beginReset(reason: string)
		if not setPhase(phases.Resetting, M.resettingSeconds, "resetting") then
			return
		end
		log(`reset: {reason}`)
		local matchId = ctx:getMatchId()
		for id in table.clone(pendingRewards) do
			grant(id, matchId)
		end
		for _, id in humanOrder do
			if spectateTarget[id] ~= nil then
				setTarget(id, nil)
			end
		end
		world.cleanup(registry:list())
		registry:clear()
		ledger:forgetBefore(matchId - 2)
		for id in humanParticipants do
			local h = humans[id]
			if h then
				if h.decision ~= "play" then
					h.ready = false
				end
				h.decision = nil
			end
		end
		kills, departed, humanParticipants = {}, {}, {}
		pendingIds = {}
		pendingRewards = {}
		result = nil
		activeStartedAt, settleUntil, resultsStartedAt = nil, nil, nil
		botsRequested, botsPlanned, startedTotal = 0, 0, 0
		gatherStart = nil
		publish()
	end

	local function checkEnd()
		local p = phase()
		if not phases.isCombat(p) then
			return
		end
		if presentHumanParticipants() == 0 then
			beginReset("no humans left") -- nobody to show results to
			return
		end
		local now = clock()
		local alive = registry:aliveCount()
		local start = activeStartedAt or now
		if alive == 0 then
			finish("last_standing")
		elseif alive == 1 then
			-- A shot already in flight gets a moment to land; if it takes the last one too, the rank tie rule decides.
			if settleUntil == nil then
				settleUntil = now + M.settleSeconds
			elseif now >= settleUntil then
				finish("last_standing")
			end
		elseif now - start >= M.maxActiveSeconds then
			finish("timeout")
		elseif
			p == phases.Active
			and (alive <= M.finalPressureAliveCount or now - start >= M.finalPressureAtSeconds)
		then
			setPhase(phases.FinalPressure, nil, "final_pressure")
		end
	end

	-- ===== starting a match =====
	local function beginSpawning()
		local matchId = ctx:getMatchId()
		if not setPhase(phases.Spawning, M.spawnPresentationSeconds, "get_ready") then
			return
		end
		kills, departed = {}, {}
		humanParticipants = {}
		local list: { any } = {}
		for _, id in pendingIds do
			local h = humans[id]
			if h then
				local p = registry:enrollPlayer(matchId, h.player, h.userId, h.name)
				if p then
					humanParticipants[id] = true
					table.insert(list, p)
				end
			end
		end
		local names = cfg.Bots.names
		for i = 1, botsPlanned do
			local label = cfg.Bots.labelPrefix .. names[(i - 1) % #names + 1]
			local p = registry:enrollBot(matchId, i, label)
			if p then
				table.insert(list, p)
			end
		end
		startedTotal = #list
		local rng = world.random or function(n: number): number
			return math.random(1, n)
		end
		local center = world.getCenter()
		local pick =
			rules.pickSpawns(world.getSpawnPoints(), #list, center, cfg.Arena.size * 0.3, rng)
		if pick.usedFallback or pick.minDistance < cfg.Arena.spawnMinSeparation then
			log(`spawns: closest pair {pick.minDistance} studs, fallback ring {pick.usedFallback}`)
		end
		local slots = pick.points
		for i = #slots, 2, -1 do
			local j = rng(i)
			slots[i], slots[j] = slots[j], slots[i]
		end
		for i, p in list do
			world.place(p, slots[i], center)
		end
		botsRequested = 0
		refreshSpectators() -- late joiners may watch
		publish()
	end

	local function beginCountdown(ready: { string })
		ctx:beginMatch()
		pendingIds = table.clone(ready)
		botsPlanned = math.min(botsRequested, math.max(0, M.maxParticipants - #ready))
		gatherStart = nil
		setPhase(phases.Countdown, M.countdownSeconds, "match_starting")
	end

	local function updateWaiting()
		local ready = readyHumanIds()
		if #ready == 0 then
			gatherStart = nil
			blocked = false
			if note ~= "press_play" then
				note = "press_play"
				publish()
			end
			return
		end
		local now = clock()
		if gatherStart == nil then
			gatherStart = now
		end
		local everyoneReady = #ready == #humanOrder
		local full = #ready + botsRequested >= M.maxParticipants
		if not (everyoneReady or full or now - (gatherStart :: number) >= M.fillWaitSeconds) then
			return
		end
		if #ready + botsRequested < M.minToStart then
			-- Not enough yet: wait for a friend or for bots (piece 09 asks for them). Say so once.
			if not blocked then
				blocked = true
				note = "waiting_players"
				publish()
			end
			return
		end
		blocked = false
		beginCountdown(ready)
	end

	local function updateCountdown()
		local keep: { string } = {}
		for _, id in pendingIds do
			if humans[id] and humans[id].ready then
				table.insert(keep, id)
			end
		end
		if #keep ~= #pendingIds then
			pendingIds = keep
			publish()
		end
		if #keep == 0 or #keep + botsPlanned < M.minToStart then
			botsRequested, botsPlanned, pendingIds = 0, 0, {}
			blocked = false
			setPhase(phases.Waiting, nil, "aborted_too_few")
			return
		end
		local endsAt = ctx:getPhaseEndsAt()
		if endsAt and clock() >= endsAt then
			beginSpawning()
		end
	end

	function self.update()
		local p = phase()
		local endsAt = ctx:getPhaseEndsAt()
		local due = endsAt ~= nil and clock() >= endsAt
		if p == phases.Waiting then
			updateWaiting()
		elseif p == phases.Countdown then
			updateCountdown()
		elseif p == phases.Spawning then
			if presentHumanParticipants() == 0 then
				beginReset("everyone left during spawn")
			elseif due then
				activeStartedAt = clock()
				setPhase(phases.Active, nil, "fight")
			end
		elseif phases.isCombat(p) then
			checkEnd()
		elseif p == phases.Finished then
			if presentHumanParticipants() == 0 then
				beginReset("everyone left")
			elseif due then
				toResults()
			end
		elseif p == phases.Results then
			local everyoneChose = true
			for id in humanParticipants do
				local h = humans[id]
				if h and h.decision == nil then
					everyoneChose = false
				end
			end
			if
				due or (everyoneChose and clock() - (resultsStartedAt or 0) >= M.resultsMinSeconds)
			then
				beginReset("results done")
			end
		elseif p == phases.Resetting then
			if due then
				blocked = false
				setPhase(phases.Waiting, nil, "press_play")
			end
		end
	end

	-- ===== people coming and going =====
	function self.addHuman(player: any, userId: number, name: string)
		local id = deps.ids.player(userId)
		if humans[id] then
			return
		end
		humans[id] = {
			id = id,
			player = player,
			userId = userId,
			name = name,
			ready = false,
			decision = nil,
		}
		table.insert(humanOrder, id)
		refreshSpectators() -- joining mid-match means watching until the next one
	end

	function self.removeHuman(id: string)
		local h = humans[id]
		if not h then
			return
		end
		humans[id] = nil
		table.remove(humanOrder, table.find(humanOrder, id) :: number)
		spectateTarget[id] = nil
		local p = registry:get(id)
		if p then
			-- Leaving counts as being out at this moment, with no killer credit (Config.Policies.disconnect).
			local forfeit = p.alive
			table.insert(departed, {
				id = id,
				name = p.displayName,
				eliminatedAt = p.eliminatedAt or clock(),
				forfeit = forfeit,
			})
			registry:remove(id)
			if forfeit then
				world.announce("kill", `{p.displayName} left the match`)
				publish()
				refreshSpectators()
				if phases.isCombat(phase()) then
					checkEnd()
				end
			end
		end
		if phase() == phases.Countdown then
			local at = table.find(pendingIds, id)
			if at then
				table.remove(pendingIds, at)
				publish()
			end
		end
	end

	function self.setReady(id: string, ready: boolean)
		local h = humans[id]
		if not h then
			return
		end
		h.ready = ready
		local p = phase()
		if (p == phases.Finished or p == phases.Results) and humanParticipants[id] then
			h.decision = if ready then "play" else "loadout"
		elseif p == phases.Countdown then
			local at = table.find(pendingIds, id)
			if ready and not at and #pendingIds + botsPlanned < M.maxParticipants then
				table.insert(pendingIds, id)
				publish()
			elseif not ready and at then
				table.remove(pendingIds, at)
				publish()
			end
		end
	end

	-- Piece 09 asks for bots while the lobby waits. Returns how many are now requested.
	function self.requestBots(count: number): number
		local p = phase()
		if p ~= phases.Waiting and p ~= phases.Countdown then
			return botsRequested
		end
		local room = M.maxParticipants
			- (if p == phases.Countdown then #pendingIds else #readyHumanIds())
		local wanted = math.clamp(math.floor(count), 0, math.max(0, room))
		if p == phases.Countdown then
			botsPlanned = wanted
		end
		botsRequested = wanted
		publish()
		return botsRequested
	end

	-- Damage.Eliminated lands here. The roster has already flipped alive=false and the damage door has already
	-- dropped stale, non-combat and double eliminations.
	function self.onEliminated(e: any)
		if e.matchId ~= ctx:getMatchId() or not phases.isCombat(phase()) then
			return
		end
		local victim = registry:get(e.victimId)
		if not victim then
			return
		end
		local killerId: string? = e.killerId
		local killer = if killerId then registry:get(killerId) else nil
		local killerKnown = killer ~= nil
		if killerId and killerId ~= e.victimId and not killerKnown then
			for _, d in departed do
				if d.id == killerId then
					killerKnown = true -- a disconnected attacker keeps credit for kills already made
				end
			end
		end
		if killerId and killerId ~= e.victimId and killerKnown then
			kills[killerId] = (kills[killerId] or 0) + 1
		else
			killerId = nil
		end
		local placement = registry:aliveCount() + 1
		local start = activeStartedAt or clock()
		world.sendEliminated({
			matchId = e.matchId,
			victimId = e.victimId,
			victimName = victim.displayName,
			killerId = killerId,
			killerName = if killer then killer.displayName else nil,
			cause = e.cause,
			placement = placement,
			eliminations = kills[e.victimId] or 0,
			survivedSeconds = math.max(0, (victim.eliminatedAt or clock()) - start),
		})
		if killer then
			world.announce("kill", `{killer.displayName} eliminated {victim.displayName}`)
		else
			world.announce("kill", `{victim.displayName} was eliminated`)
		end
		publish()
		refreshSpectators()
		checkEnd()
	end

	-- The zone's last warning moves the match to Final pressure (piece 06 calls this through MatchSystem).
	function self.enterFinalPressure(matchId: number)
		if matchId == ctx:getMatchId() and phase() == phases.Active then
			setPhase(phases.FinalPressure, nil, "final_pressure")
		end
	end

	function self.getResult(): Result?
		return result
	end
	function self.getBotsRequested(): number
		return botsRequested
	end
	function self.isReady(id: string): boolean
		return humans[id] ~= nil and humans[id].ready
	end

	return self
end

return MatchController

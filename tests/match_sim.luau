--!strict
-- A whole server in miniature, for the end-to-end match tests (piece 41).
--
-- Every pure piece is real: the match flow (MatchController), the roster, the damage door, health,
-- ammo, spawn shields, run XP, upgrades, the zone, crates and orbs, the bot brains and auto-fill,
-- the arena layout (walls block shots and walking), coins, stats and daily challenges. They are
-- wired the same way the *System files wire them in the game, in the same start order. Only Roblox
-- itself is faked: bodies are points on the ground that walk at walkSpeed, and shots are flat lines.
--
-- Simulated people play like bots (the same BotBrain stands in for their thumbs) but also walk to
-- crates and shoot them, take their orbs, pick upgrade cards and tap Play again when told to.

local Config = require("../src/shared/Config")
local HeroRoster = require("../src/shared/HeroRoster")
local Heroes = require("../src/shared/Heroes")
local Ids = require("../src/shared/Ids")
local MatchPhase = require("../src/shared/MatchPhase")
local MatchContext = require("../src/shared/MatchContext")
local ParticipantRegistry = require("../src/shared/ParticipantRegistry")
local DamageRouter = require("../src/shared/DamageRouter")
local RunXp = require("../src/shared/RunXp")
local StatBook = require("../src/shared/StatBook")
local UpgradeDefs = require("../src/shared/UpgradeDefs")
local SpawnShield = require("../src/shared/SpawnShield")
local Signal = require("../src/shared/Signal")
local StatsRules = require("../src/shared/Stats/StatsRules")
local StatsBook = require("../src/shared/Stats/StatsBook")
local ProgressService = require("../src/shared/Progression/ProgressService")
local ProgressMemoryStore = require("../src/shared/Progression/MemoryStore")
local DailyService = require("../src/shared/Daily/DailyService")
local DailyMemoryStore = require("../src/shared/Daily/DailyMemoryStore")
local DailyDefs = require("../src/shared/Daily/DailyDefs")
local Receipts = require("../src/shared/Profile/Receipts")

local MatchRules = require("../src/server/Match/MatchRules")
local MatchController = require("../src/server/Match/MatchController")
local HealthBook = require("../src/server/Combat/HealthBook")
local WeaponState = require("../src/server/Combat/WeaponState")
local WeaponCatalog = require("../src/server/Combat/WeaponCatalog")
local Ballistics = require("../src/server/Combat/Ballistics")
local ZoneModel = require("../src/server/Zone/ZoneModel")
local ContainerRules = require("../src/server/Pickups/ContainerRules")
local PickupRules = require("../src/server/Pickups/PickupRules")
local RunUpgrades = require("../src/server/Upgrades/RunUpgrades")
local BotTuning = require("../src/server/Bots/BotTuning")
local BotRoster = require("../src/server/Bots/BotRoster")
local BotRunner = require("../src/server/Bots/BotRunner")
local Layout = require("../src/server/Arena/Layout")

local LAYOUTS: { [string]: any } = {
	A = require("../src/server/Arena/LayoutA"),
	B = require("../src/server/Arena/LayoutB"),
	C = require("../src/server/Arena/LayoutC"),
}

local MatchSim = {}

MatchSim.TICK = 0.1 -- MatchSystem ticks the controller every 0.1 s; bots think every 0.1 s too
local BODY = 1.5 -- studs a walking body keeps from walls
local CRATE_REACH = 9 -- people stop this close to a crate and shoot it

export type Options = {
	seed: number?,
	layout: string?, -- "A" | "B" | "C" (default: Config.Arena.layout)
	config: any?, -- a patched copy of Config
	heroes: { [number]: string }?, -- hero id by user id (piece 44); everyone else plays the default hero
}

type Body = { x: number, z: number, vx: number, vz: number }
type Crate = {
	id: string,
	x: number,
	z: number,
	health: number,
	max: number,
	tier: string,
	matchId: number,
}
type Orb = { data: PickupRules.Pickup, x: number, z: number, serverReservedUntil: number }
type Human = { id: string, userId: number, player: any, name: string, crates: boolean }

function MatchSim.new(options: Options?)
	local opts: Options = options or {}
	local cfg: any = opts.config or Config
	local layout = Layout.compile(LAYOUTS[opts.layout or cfg.Arena.layout])

	-- ===== time and luck =====
	local t = 1000 -- os.clock-like; never 0 so "0 = unset" bugs show up
	local function clock(): number
		return t
	end
	local seed = opts.seed or 1
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local function randInt(n: number): number
		return math.floor(rand() * n) + 1
	end

	local sim: any = {
		layout = layout,
		config = cfg,
		errors = {} :: { string },
		phases = {} :: { string },
		eliminations = {} :: { any },
		results = {} :: { [string]: { any } },
		rewards = {} :: { { id: string, amount: number, place: number, matchId: number } },
		announcements = {} :: { string },
		zoneEvents = {} :: { any },
		zoneDamage = {} :: { [string]: number },
		cratesBroken = 0,
		orbsTaken = 0,
		shots = 0,
		hits = 0,
		upgradesTaken = 0,
		botFillAsks = {} :: { number },
		publishedStates = {} :: { any },
		humans = {} :: { [string]: Human },
		gone = {} :: { [string]: Human }, -- people who left (their saves stay readable)
		replay = {} :: { [string]: boolean }, -- tap Play again on the results screen
	}

	local function fail(where: string, err: any)
		table.insert(sim.errors, `{where}: {tostring(err)}`)
	end
	-- Every listener the sim adds is guarded like Signal does, but errors are kept so tests can fail on them.
	local function guarded(where: string, fn: (...any) -> ()): (...any) -> ()
		return function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				fail(where, err)
			end
		end
	end

	-- ===== Core (Main.server.luau requires these first) =====
	local ctx = MatchContext.new(clock)
	local registry = ParticipantRegistry.new(clock)
	local router = DamageRouter.new({
		getMatchId = function()
			return ctx:getMatchId()
		end,
		allowsDamage = function()
			return MatchPhase.allowsDamage(ctx:getPhase())
		end,
		isAlive = function(id: string)
			return registry:isAlive(id)
		end,
		markEliminated = function(id: string)
			return registry:markEliminated(id)
		end,
		clock = clock,
	})
	local runXp = RunXp.new(cfg.Xp)
	local stats = StatBook.new(cfg)
	-- Piece 44: Lobby/LobbySystem installs this modifier and Core/HeroBook; bots play heroes by number.
	local function heroOf(id: string): string
		return HeroRoster.heroOf(cfg, id, function(userId: number): string?
			return (opts.heroes or {})[userId]
		end)
	end
	stats:addModifier(function(id: string, sheet: any)
		Heroes.applyToSheet(cfg, sheet, heroOf(id))
	end)
	sim.heroOf = heroOf
	local shields = SpawnShield.new(clock)
	sim.ctx, sim.registry, sim.router, sim.runXp, sim.shields =
		ctx, registry, router, runXp, shields

	-- Core/Damage: a new match forgets who was eliminated.
	ctx.MatchStarted:connect(guarded("Damage.MatchStarted", function()
		router:reset()
	end))
	-- Core/RunXp: enrolling resets XP, leaving forgets it.
	registry.Enrolled:connect(guarded("RunXp.Enrolled", function(p: any)
		runXp:reset(p.id)
	end))
	registry.Removed:connect(guarded("RunXp.Removed", function(p: any)
		runXp:forget(p.id)
	end))

	-- ===== world state (what Roblox would hold) =====
	local bodies: { [string]: Body } = {}
	local crates: { [string]: Crate } = {}
	local orbs: { [string]: Orb } = {}
	local orbCount = 0
	sim.bodies, sim.crates, sim.orbs = bodies, crates, orbs

	-- ===== MatchSystem (order 50) =====
	local RewardGranted = Signal.new()
	local SpawnAssigned = Signal.new()
	sim.RewardGranted = RewardGranted

	local world: MatchController.World = {
		getSpawnPoints = function()
			local out: { MatchController.Point } = {}
			for _, s in layout.spawns do
				table.insert(out, { x = s.x, y = 3, z = s.z })
			end
			return out
		end,
		getCenter = function()
			return { x = cfg.Arena.centerX, y = 3, z = cfg.Arena.centerZ }
		end,
		place = function(participant, point, lookAt)
			SpawnAssigned:fire(participant, point, lookAt)
			if participant.kind == "player" then
				bodies[participant.id] = { x = point.x, z = point.z, vx = 0, vz = 0 }
			end
		end,
		cleanup = function(_participants)
			-- Players go back to the lobby: their match bodies are gone.
			for id in bodies do
				if Ids.isPlayer(id) then
					bodies[id] = nil
				end
			end
		end,
		publish = function(state)
			table.insert(sim.publishedStates, state)
		end,
		announce = function(_kind, text)
			table.insert(sim.announcements, text)
		end,
		sendEliminated = function(payload)
			table.insert(sim.eliminations, payload)
		end,
		sendResults = function(id, payload)
			sim.results[id] = sim.results[id] or {}
			table.insert(sim.results[id], payload)
		end,
		sendSpectate = function(_id, _target) end,
		grantReward = function(id, amount, place, matchId, won)
			table.insert(
				sim.rewards,
				{ id = id, amount = amount, place = place, matchId = matchId, won = won }
			)
			RewardGranted:fire(id, amount, place, matchId, won)
		end,
		toServerTime = function(x: number): number
			return x
		end,
		random = randInt,
		log = function(_message) end,
	}

	local controller = MatchController.new({
		config = cfg,
		rules = MatchRules,
		ctx = ctx,
		registry = registry,
		phases = MatchPhase,
		ids = Ids,
		clock = clock,
		world = world,
	})
	sim.controller = controller

	router.Eliminated:connect(guarded("Match.onEliminated", function(e: any)
		controller.onEliminated(e)
	end))

	ctx.PhaseChanged:connect(function(phase: string)
		table.insert(sim.phases, phase)
	end)

	-- ===== Combat (order 60): health, ammo, guns =====
	local book = HealthBook.new(cfg.Health.max)
	type Fighter = { matchId: number, hero: string, weapons: WeaponState.State, primary: string }
	local fighters: { [string]: Fighter } = {}
	sim.book, sim.fighters = book, fighters

	local function gunStats(id: string): WeaponCatalog.GunStats
		local f = fighters[id]
		local primary = if f then f.primary else cfg.Weapons.Firearm.id
		return WeaponCatalog.stats(cfg, primary, stats:get(id).firearm)
	end
	local function slotStats(id: string, slot: number): WeaponState.Stats
		local w: any = if slot == 2 then stats:get(id).explosive else gunStats(id)
		return {
			fireInterval = w.fireInterval,
			magazine = w.magazine,
			reloadSeconds = w.reloadSeconds,
		}
	end
	-- Combatants.ensure
	local function ensure(id: string): Fighter?
		local p = registry:get(id)
		if p == nil then
			return nil
		end
		local f = fighters[id]
		if f ~= nil and f.matchId == p.matchId then
			return f
		end
		local sheet = stats:get(id)
		local hero = heroOf(id)
		local primary = Heroes.primaryGun(hero)
		local gun = WeaponCatalog.stats(cfg, primary, sheet.firearm)
		local fresh: Fighter = {
			matchId = p.matchId,
			hero = hero,
			weapons = WeaponState.new(
				{ gun.magazine, sheet.explosive.magazine },
				cfg.Combat.fireTolerance
			),
			primary = primary,
		}
		if not p.alive then
			fresh.weapons:lock()
		end
		fighters[id] = fresh
		book:add(id, Heroes.maxHealth(cfg, hero))
		return fresh
	end
	sim.ensure = ensure

	router:bind(function(req: any): any
		local f = ensure(req.targetId)
		if f == nil then
			return {
				applied = false,
				reason = "no-record",
				dealt = 0,
				remaining = 0,
				eliminated = false,
			}
		end
		local dealt, remaining, dead = book:apply(req.targetId, req.amount, req.sourceId)
		return {
			applied = dealt > 0,
			reason = if dealt > 0 then nil else "no-health",
			dealt = dealt,
			remaining = remaining,
			eliminated = dead,
		}
	end)
	router.Damaged:connect(guarded("Combat.onDamaged", function(e: any)
		if e.request.cause == "zone" then
			local id = e.request.targetId
			sim.zoneDamage[id] = (sim.zoneDamage[id] or 0) + e.result.dealt
		elseif e.request.cause == "bullet" then
			sim.hits += 1
		end
	end))
	router.Eliminated:connect(guarded("Combat.onEliminated", function(e: any)
		local f = fighters[e.victimId]
		if f then
			f.weapons:lock()
		end
	end))
	registry.Enrolled:connect(guarded("Combat.Enrolled", function(p: any)
		ensure(p.id)
	end))
	registry.Removed:connect(guarded("Combat.Removed", function(p: any)
		fighters[p.id] = nil
		book:remove(p.id)
	end))
	ctx.PhaseChanged:connect(guarded("Combat.PhaseChanged", function(phase: string)
		if phase == "Finished" or phase == "Results" or phase == "Resetting" then
			for _, f in fighters do
				f.weapons:lock()
			end
		end
	end))

	-- ===== Progression (order 60): coins. Stats (60): wins, matches, eliminations =====
	local progressStore = ProgressMemoryStore.new()
	local jobId = "sim-job"
	local progress = ProgressService.new({
		store = progressStore,
		maxGrant = cfg.Progression.maxMatchGrant,
		receiptKey = function(matchId: number): string
			return Receipts.matchKey(jobId, matchId)
		end,
		send = function(_player, _state) end,
		applyLook = function(_player, _trail, _tracer) end,
	})
	sim.progressStore = progressStore

	local function playerOf(participantId: string): any?
		local userId = Ids.userIdOf(participantId)
		if userId == nil then
			return nil
		end
		local h = sim.humans[participantId]
		return if h then h.player else nil
	end
	sim.playerOf = playerOf

	RewardGranted:connect(
		guarded(
			"Progression.RewardGranted",
			function(id: string, amount: number, _place: number, matchId: number)
				local player = playerOf(id)
				if player ~= nil then
					progress.onReward(player, amount, matchId)
				end
			end
		)
	)

	local savedStats: { [number]: StatsRules.Stats } = {}
	local statsBook = StatsBook.new({
		save = function(userId: number, delta: StatsRules.Stats): StatsRules.Stats?
			local s = savedStats[userId] or { wins = 0, eliminations = 0, matches = 0 }
			s = {
				wins = s.wins + delta.wins,
				eliminations = s.eliminations + delta.eliminations,
				matches = s.matches + delta.matches,
			}
			savedStats[userId] = s
			return s
		end,
		changed = function(_userId, _shown) end,
		savedWins = function(_userId, _wins) end,
	})
	sim.savedStats = savedStats
	router.Eliminated:connect(guarded("Stats.Eliminated", function(e: any)
		if not ctx:isCurrent(e.matchId) then
			return
		end
		local userId = StatsRules.eliminationCredit(e)
		if userId then
			statsBook:earn(userId, { wins = 0, eliminations = 1, matches = 0 })
		end
	end))
	RewardGranted:connect(
		guarded(
			"Stats.RewardGranted",
			function(id: string, _amount: number, place: number, _m: number, won: boolean?)
				local userId = if Ids.isPlayer(id) then Ids.userIdOf(id) else nil
				if userId then
					statsBook:earn(userId, StatsRules.matchDelta(place, won == true))
				end
			end
		)
	)

	-- ===== Daily (order 70) =====
	local dailyStore = DailyMemoryStore.new()
	local daily = DailyService.new({
		store = dailyStore,
		pay = function(player: any, amount: number, key: string)
			return progress.grant(player, amount, key)
		end,
		send = function(_player, _state) end,
		now = function()
			return 1_790_000_000 + math.floor(t)
		end,
		rewards = cfg.Daily.rewards,
		resetHour = cfg.Daily.resetHourUtc,
	})
	sim.dailyStore = dailyStore
	runXp.Awarded:connect(guarded("Daily.Awarded", function(id: string, reason: string)
		local kind = DailyDefs.kindForXpReason[reason]
		local player = playerOf(id)
		if kind ~= nil and player ~= nil then
			daily.count(player, kind, 1)
		end
	end))
	RewardGranted:connect(
		guarded(
			"Daily.RewardGranted",
			function(id: string, _amount: number, place: number, _m: number, won: boolean?)
				local player = playerOf(id)
				if player == nil then
					return
				end
				daily.count(player, "matches", 1)
				if place >= 1 and place <= 3 then
					daily.count(player, "top3", 1)
				end
				if won == true then
					daily.count(player, "wins", 1)
				end
			end
		)
	)

	-- ===== Pickups (order 100) and RunXp wiring =====
	local function clearOrbs()
		table.clear(orbs)
	end
	local function spawnOrbs(x: number, z: number, count: number, reservedFor: string?)
		local pc = cfg.Pickups
		local offsets = ContainerRules.scatter(count, pc.scatterRadius, rand() * 2 * math.pi)
		for _, o in offsets do
			orbCount += 1
			local id = `o{ctx:getMatchId()}_{orbCount}`
			orbs[id] = {
				data = {
					id = id,
					matchId = ctx:getMatchId(),
					expiresAt = t + pc.lifetimeSeconds,
					reservedFor = reservedFor,
					reservedUntil = if reservedFor then t + pc.reserveSeconds else 0,
					claimed = false,
				},
				x = x + o.x,
				z = z + o.z,
				serverReservedUntil = if reservedFor then t + pc.reserveSeconds else 0,
			}
		end
	end
	local function tryClaim(id: string, pickupId: string): boolean
		if not ctx:isCombat() or not registry:isAlive(id) then
			return false
		end
		local orb = orbs[pickupId]
		local body = bodies[id]
		if orb == nil or body == nil then
			return false
		end
		local dist = math.sqrt((orb.x - body.x) ^ 2 + (orb.z - body.z) ^ 2)
		local ok = PickupRules.check(
			orb.data,
			id,
			t,
			dist,
			cfg.Pickups.collectRadius,
			cfg.Pickups.claimSlack,
			ctx:getMatchId()
		)
		if not ok then
			return false
		end
		orb.data.claimed = true
		runXp:award(id, "orbPickup")
		orbs[pickupId] = nil
		sim.orbsTaken += 1
		return true
	end
	ctx.MatchStarted:connect(guarded("Pickups.MatchStarted", clearOrbs))
	ctx.PhaseChanged:connect(guarded("Pickups.PhaseChanged", function(phase: string)
		if phase == "Resetting" or phase == "Waiting" then
			clearOrbs()
		end
	end))
	router.Eliminated:connect(guarded("RunXp.Eliminated", function(e: any)
		local killerId = e.killerId
		if
			killerId == nil
			or killerId == e.victimId
			or not ctx:isCurrent(e.matchId)
			or not registry:isAlive(killerId)
		then
			return
		end
		runXp:award(killerId, "elimination")
	end))

	-- ===== Containers (order 110) =====
	local function clearCrates()
		table.clear(crates)
	end
	local function spawnCrates(matchId: number)
		clearCrates()
		local cc = cfg.Containers
		for i, spot in layout.containers do
			local tier = ContainerRules.pickTier(cc.tierOrder, function(id: string): number
				return cc.tiers[id].weight
			end, rand())
			local id = `c{matchId}_{i}`
			crates[id] = {
				id = id,
				x = spot.x,
				z = spot.z,
				health = cc.tiers[tier].health,
				max = cc.tiers[tier].health,
				tier = tier,
				matchId = matchId,
			}
		end
	end
	-- ContainerSystem.damage
	local function damageCrate(crateId: string, amount: number, sourceId: string, matchId: number)
		local record = crates[crateId]
		if record == nil then
			return
		end
		local current = ctx:getMatchId()
		if
			not ctx:isCombat()
			or record.matchId ~= current
			or matchId ~= current
			or not registry:isAlive(sourceId)
		then
			return
		end
		local health, broke = ContainerRules.applyDamage(record.health, amount)
		record.health = health
		if broke then
			crates[crateId] = nil
			sim.cratesBroken += 1
			runXp:award(sourceId, "containerBreak")
			spawnOrbs(record.x, record.z, cfg.Containers.tiers[record.tier].orbs, sourceId)
		end
	end
	ctx.MatchStarted:connect(guarded("Containers.MatchStarted", clearCrates))
	ctx.PhaseChanged:connect(
		guarded("Containers.PhaseChanged", function(phase: string, _old: string, matchId: number)
			if phase == "Spawning" then
				spawnCrates(matchId)
			elseif phase == "Resetting" or phase == "Waiting" then
				clearCrates()
			end
		end)
	)

	-- ===== Upgrades (order 120) =====
	local upgradeCtx = {
		base = StatBook.base(cfg),
		hasExplosive = cfg.Features.explosiveWeapon,
		weaponNames = {
			firearm = cfg.Weapons.Firearm.displayName,
			explosive = cfg.Weapons.Explosive.displayName,
		},
	}
	local runUpgrades =
		RunUpgrades.new(UpgradeDefs, upgradeCtx, rand, clock, cfg.Upgrades.selectionLockSeconds)
	sim.runUpgrades = runUpgrades
	stats:setProvider(function(id: string)
		return runUpgrades:sheet(id)
	end)
	local pendingPicks: { { at: number, id: string, matchId: number, offerId: string, option: number } } =
		{}
	local showNext: (id: string) -> ()
	local function tryChoose(id: string, matchId: number, offerId: string, optionIndex: number)
		local participant = registry:get(id)
		if participant == nil or not participant.alive then
			return
		end
		if not ctx:isCombat() or not ctx:isCurrent(matchId) then
			return
		end
		local result = runUpgrades:choose(id, matchId, offerId, optionIndex)
		if result.ok then
			runXp:takeOffer(id)
			stats:invalidate(id)
			sim.upgradesTaken += 1
			showNext(id)
		elseif result.reason == "offer_invalid" then
			showNext(id)
		end
	end
	showNext = function(id: string)
		local state = runXp:get(id)
		local participant = registry:get(id)
		if state == nil or participant == nil or not participant.alive then
			return
		end
		if runUpgrades:hasActive(id) then
			while state.pendingOffers > 1 + cfg.Upgrades.queueMax do
				runXp:takeOffer(id)
			end
			return
		end
		while state.pendingOffers > 0 do
			local payload, reason = runUpgrades:issue(id)
			if payload ~= nil then
				-- Bots pause 0.8-2 s; people read the cards for about as long.
				table.insert(pendingPicks, {
					at = t + 0.8 + rand() * 1.2,
					id = id,
					matchId = payload.matchId,
					offerId = payload.offerId,
					option = randInt(#payload.options),
				})
				return
			end
			if reason ~= "nothing_eligible" then
				return
			end
			runXp:takeOffer(id)
		end
	end
	registry.Enrolled:connect(guarded("Upgrades.Enrolled", function(p: any)
		runUpgrades:enroll(p.id, p.matchId)
		stats:invalidate(p.id)
	end))
	registry.Eliminated:connect(guarded("Upgrades.Eliminated", function(p: any)
		runUpgrades:eliminate(p.id)
	end))
	registry.Removed:connect(guarded("Upgrades.Removed", function(p: any)
		runUpgrades:remove(p.id)
		stats:invalidate(p.id)
	end))
	ctx.PhaseChanged:connect(guarded("Upgrades.PhaseChanged", function(phase: string)
		if phase == "Resetting" then
			runUpgrades:clear()
		end
	end))
	runXp.LevelUp:connect(guarded("Upgrades.LevelUp", function(id: string)
		showNext(id)
	end))

	-- ===== Zone (order 200) =====
	local zone = ZoneModel.newRunner({
		config = cfg.Zone,
		now = clock,
		getTargets = function()
			local out: { ZoneModel.Target } = {}
			for _, p in registry:aliveList() do
				local b = bodies[p.id]
				if b then
					table.insert(out, { id = p.id, x = b.x, z = b.z })
				end
			end
			return out
		end,
		applyDamage = function(id: string, amount: number, _stage: number)
			router:apply({
				matchId = ctx:getMatchId(),
				targetId = id,
				amount = amount,
				cause = "zone",
				sourceId = nil,
			})
		end,
		publish = function(_state) end,
		onEvent = function(event)
			table.insert(sim.zoneEvents, event)
			if event.kind == "FinalPressure" then
				controller.enterFinalPressure(event.matchId)
			end
		end,
	})
	sim.zone = zone
	ctx.PhaseChanged:connect(
		guarded("Zone.PhaseChanged", function(phase: string, _old: string, matchId: number)
			if phase == MatchPhase.Active then
				zone:start(matchId)
			elseif not MatchPhase.isCombat(phase) then
				zone:stop()
			end
		end)
	)

	-- ===== Spawn shield (order 250) =====
	router:addGuard(shields:guard())
	ctx.PhaseChanged:connect(guarded("SpawnShield.PhaseChanged", function(phase: string)
		if phase == MatchPhase.Active then
			for _, p in registry:aliveList() do
				shields:give(p.id, cfg.SpawnShield.seconds)
			end
		elseif not MatchPhase.isCombat(phase) then
			shields:clear()
		end
	end))

	-- ===== shots (Firing.fire for people and bots) =====
	local function wallDistance(
		ox: number,
		oz: number,
		dx: number,
		dz: number,
		range: number
	): number?
		local best: number? = nil
		local ex, ez = ox + dx * range, oz + dz * range
		for _, s in layout.solids do
			if s.blocksShots and Layout.segmentHitsBox(ox, oz, ex, ez, s.x0, s.z0, s.x1, s.z1) then
				-- Entry distance along the ray (slab method).
				local t0 = 0
				for _, axis in { { ox, dx, s.x0, s.x1 }, { oz, dz, s.z0, s.z1 } } do
					local p, d, lo, hi = axis[1], axis[2], axis[3], axis[4]
					if math.abs(d) > 1e-9 then
						local ta, tb = (lo - p) / d, (hi - p) / d
						t0 = math.max(t0, math.min(ta, tb))
					end
				end
				local dist = math.min(t0, range)
				if best == nil or dist < best then
					best = dist
				end
			end
		end
		return best
	end
	local crateRadius = cfg.Containers.size / 2

	local function fire(id: string, dirX: number, dirZ: number): (boolean, string?)
		if not ctx:isCombat() then
			return false, "not-combat"
		end
		if not registry:isAlive(id) then
			return false, "eliminated"
		end
		local f = ensure(id)
		local body = bodies[id]
		if f == nil or body == nil then
			return false, "no-body"
		end
		local dx, dz = Ballistics.flatten(dirX, 0, dirZ)
		if dx == nil or dz == nil then
			return false, "bad-aim"
		end
		local result = f.weapons:tryFire(t, slotStats(id, f.weapons.slot))
		if not result.ok then
			return false, result.reason
		end
		if cfg.SpawnShield.dropOnFire then
			shields:drop(id)
		end
		sim.shots += 1
		local st = gunStats(id)
		local matchId = f.matchId
		local targets: { Ballistics.Target } = {}
		for _, p in registry:aliveList() do
			local b = bodies[p.id]
			if p.id ~= id and b then
				table.insert(targets, { id = p.id, x = b.x, z = b.z, r = cfg.Combat.bodyRadius })
			end
		end
		for crateId, c in crates do
			table.insert(targets, { id = crateId, x = c.x, z = c.z, r = crateRadius })
		end
		for _, d in Ballistics.fan(dx :: number, dz :: number, st.pellets, st.spreadDegrees) do
			local wall = wallDistance(body.x, body.z, d.x, d.z, st.range)
			local hit = Ballistics.firstHit(body.x, body.z, d.x, d.z, st.range, wall, targets)
			if hit.kind == "target" and hit.id ~= nil then
				if crates[hit.id] then
					damageCrate(hit.id, st.damage, id, matchId)
				else
					router:apply({
						matchId = matchId,
						targetId = hit.id,
						amount = st.damage,
						cause = "bullet",
						sourceId = id,
						weaponId = st.id,
					})
				end
			end
		end
		return true, nil
	end
	sim.fire = fire

	local function canSee(a: { x: number, z: number }, b: { x: number, z: number }): boolean
		if Layout.shotBlocked(layout, a.x, a.z, b.x, b.z) then
			return false
		end
		for _, c in crates do
			local r = crateRadius
			if Layout.segmentHitsBox(a.x, a.z, b.x, b.z, c.x - r, c.z - r, c.x + r, c.z + r) then
				-- A crate between them blocks the look (unless one of them is standing in it).
				local inA = math.abs(a.x - c.x) <= r and math.abs(a.z - c.z) <= r
				local inB = math.abs(b.x - c.x) <= r and math.abs(b.z - c.z) <= r
				if not inA and not inB then
					return false
				end
			end
		end
		return true
	end
	sim.canSee = canSee

	-- ===== Bots (order 300) =====
	local tuning = BotTuning.from(cfg)
	local fill = BotRoster.newFill()
	local requested = 0
	local intents: { [string]: { x: number, z: number } } = {}
	-- Crate hunters walk in straight lines, so they give up for a while when a wall holds them.
	local hunt: { [string]: { x: number, z: number, at: number, pauseUntil: number } } = {}
	local function zoneView(): any
		local sample = zone:getSample()
		if sample then
			return {
				center = { x = sample.centerX, z = sample.centerZ },
				radius = math.min(sample.radius, sample.toRadius),
			}
		end
		return nil
	end
	local function visibleEnemy(id: string, range: number): boolean
		local me = bodies[id]
		if me == nil then
			return false
		end
		for _, p in registry:aliveList() do
			local b = bodies[p.id]
			if p.id ~= id and b then
				local d = math.sqrt((b.x - me.x) ^ 2 + (b.z - me.z) ^ 2)
				if d <= range and canSee(me, b) then
					return true
				end
			end
		end
		return false
	end
	local function nearestCrate(id: string): Crate?
		local me = bodies[id]
		if me == nil then
			return nil
		end
		local z = zoneView()
		local best: Crate? = nil
		local bestD = math.huge
		for _, c in crates do
			local safe = z == nil
				or math.sqrt((c.x - z.center.x) ^ 2 + (c.z - z.center.z) ^ 2) < z.radius - 6
			local d = math.sqrt((c.x - me.x) ^ 2 + (c.z - me.z) ^ 2)
			if safe and d < bestD then
				best, bestD = c, d
			end
		end
		return best
	end

	local runner = BotRunner.new(
		{
			now = clock,
			isActive = function()
				return ctx:isCombat()
			end,
			fightSeconds = function()
				if ctx:getPhase() == MatchPhase.Active then
					return ctx:phaseElapsed()
				end
				return math.huge
			end,
			selfState = function(id: string): any
				local b = bodies[id]
				if b == nil or not registry:isAlive(id) then
					return nil
				end
				local f = ensure(id)
				local hp = book:get(id)
				if f == nil or hp == nil then
					return nil
				end
				local slot = f.weapons.slot
				return {
					id = id,
					pos = { x = b.x, z = b.z },
					health = hp,
					maxHealth = book:max_(id) or cfg.Health.max,
					ammo = f.weapons.ammo[slot],
					magazine = slotStats(id, slot).magazine,
					reloading = f.weapons.reloadEndsAt[slot] ~= nil,
					canFire = ctx:isCombat() and f.weapons:canFire(t),
					slideReady = false,
				}
			end,
			others = function(id: string): any
				local out = {}
				for _, p in registry:aliveList() do
					local b = bodies[p.id]
					if p.id ~= id and b then
						table.insert(out, {
							id = p.id,
							pos = { x = b.x, z = b.z },
							shielded = shields:isShielded(p.id),
						})
					end
				end
				return out
			end,
			pickups = function(): any
				local out = {}
				for id, o in orbs do
					local held = o.data.reservedFor ~= nil and o.serverReservedUntil > t
					if not held then
						table.insert(out, { id = id, pos = { x = o.x, z = o.z } })
					end
				end
				return out
			end,
			zone = zoneView,
			weaponRange = function(id: string): number
				return stats:get(id).firearm.range
			end,
			canSee = canSee,
			move = function(id: string, x: number, z: number)
				local h = sim.humans[id]
				local me = bodies[id]
				local zv = zoneView()
				local inside = me ~= nil
					and (
						zv == nil
						or math.sqrt((me.x - zv.center.x) ^ 2 + (me.z - zv.center.z) ^ 2)
							< zv.radius - 4
					)
				local state = hunt[id]
				if me and (state == nil or t - state.at >= 1) then
					-- Held in place for a second while hunting: let the brain steer for a few seconds.
					local walking = intents[id] ~= nil
						and (intents[id].x ~= 0 or intents[id].z ~= 0)
					if
						state
						and walking
						and t >= state.pauseUntil
						and math.abs(me.x - state.x) + math.abs(me.z - state.z) < 1
					then
						state.pauseUntil = t + 4
					end
					hunt[id] = {
						x = me.x,
						z = me.z,
						at = t,
						pauseUntil = if state then state.pauseUntil else 0,
					}
				end
				local paused = hunt[id] ~= nil and t < hunt[id].pauseUntil
				if
					h
					and h.crates
					and inside
					and not paused
					and not visibleEnemy(id, tuning.sightRange)
				then
					-- A person with nobody in sight goes crate hunting.
					local c = nearestCrate(id)
					if c and me then
						local dx, dz = c.x - me.x, c.z - me.z
						local d = math.sqrt(dx * dx + dz * dz)
						if d > CRATE_REACH then
							intents[id] = { x = dx / d, z = dz / d }
						else
							intents[id] = { x = 0, z = 0 }
							fire(id, dx / d, dz / d)
						end
						return
					end
				end
				intents[id] = { x = x, z = z }
			end,
			fire = function(id: string, aimX: number, aimZ: number)
				fire(id, aimX, aimZ)
			end,
			reload = function(id: string)
				local f = fighters[id]
				if f and ctx:isCombat() and registry:isAlive(id) then
					f.weapons:startReload(t, slotStats(id, f.weapons.slot))
				end
			end,
			slide = function(_id, _dx, _dz) end,
		},
		tuning,
		rand,
		function(id: string, msg: string)
			fail(`bot {id} thinking`, msg)
		end
	)
	sim.runner = runner

	local function askForBots(count: number): number
		if count <= 0 then
			return 0
		end
		local accepted = controller.requestBots(count)
		table.insert(sim.botFillAsks, accepted)
		if accepted > 0 then
			requested += accepted
			return accepted
		end
		return 0
	end
	-- BotSystem.humanCount: people in the server, or only those who pressed Play once anyone has.
	local function humanCount(): number
		local n, queued = 0, 0
		for id in sim.humans do
			n += 1
			if controller.isReady(id) then
				queued += 1
			end
		end
		return BotRoster.lobbyHumans(n, queued)
	end
	local function autoFillTick()
		local result = BotRoster.updateFill(
			tuning,
			fill,
			t,
			ctx:getPhase() == MatchPhase.Waiting,
			humanCount()
		)
		if result.action == "fill" then
			askForBots(BotRoster.botsToAdd(tuning, humanCount(), requested))
		end
	end
	sim.addBotsNow = function(): number
		fill.filled = true
		return askForBots(BotRoster.botsToAdd(tuning, humanCount(), requested))
	end
	ctx.PhaseChanged:connect(guarded("Bots.PhaseChanged", function(phase: string)
		if phase == MatchPhase.Resetting or phase == MatchPhase.Waiting then
			runner:clear()
			for id in bodies do
				if Ids.isBot(id) then
					bodies[id] = nil
				end
			end
			requested = 0
		end
	end))
	SpawnAssigned:connect(guarded("Bots.SpawnAssigned", function(participant: any, pos: any)
		if participant.kind == "bot" then
			bodies[participant.id] = { x = pos.x, z = pos.z, vx = 0, vz = 0 }
			runner:add(participant.id)
		else
			-- Simulated people use the same brain for their thumbs.
			runner:add(participant.id)
		end
	end))

	-- ===== moving bodies (Humanoid:Move at walkSpeed, walls stop you) =====
	local function blocked(x: number, z: number): boolean
		local half = layout.half - BODY
		if x < -half or x > half or z < -half or z > half then
			return true
		end
		for _, s in layout.solids do
			if
				s.blocksMove
				and x > s.x0 - BODY
				and x < s.x1 + BODY
				and z > s.z0 - BODY
				and z < s.z1 + BODY
			then
				return true
			end
		end
		for _, c in crates do
			local r = crateRadius + BODY
			if math.abs(x - c.x) < r and math.abs(z - c.z) < r then
				return true
			end
		end
		return false
	end
	local function moveBodies(dt: number)
		if not ctx:isCombat() then
			return
		end
		for id, dir in intents do
			local b = bodies[id]
			if b and registry:isAlive(id) then
				local len = math.sqrt(dir.x * dir.x + dir.z * dir.z)
				if len > 1e-6 then
					local speed = stats:get(id).moveSpeed
					local step = speed * dt / math.max(len, 1)
					local nx, nz = b.x + dir.x * step, b.z + dir.z * step
					if not blocked(nx, nz) then
						b.x, b.z = nx, nz
					elseif not blocked(nx, b.z) then
						b.x = nx
					elseif not blocked(b.x, nz) then
						b.z = nz
					end
				end
			end
		end
	end

	-- People and bots pick up what they stand next to (the client asks; bots ask through the port).
	local function collectNearby()
		for _, p in registry:aliveList() do
			local b = bodies[p.id]
			if b then
				for pickupId, o in orbs do
					if
						math.sqrt((o.x - b.x) ^ 2 + (o.z - b.z) ^ 2) <= cfg.Pickups.collectRadius
					then
						tryClaim(p.id, pickupId)
					end
				end
			end
		end
	end

	-- ===== people =====
	function sim.join(userId: number, name: string?, opts2: { crates: boolean? }?): string
		local id = Ids.player(userId)
		local player = { UserId = userId, Name = name or `P{userId}` }
		sim.humans[id] = {
			id = id,
			userId = userId,
			player = player,
			name = player.Name,
			crates = (opts2 == nil or opts2.crates ~= false),
		}
		controller.addHuman(player, userId, player.Name)
		statsBook:join(userId)
		statsBook:loaded(userId)
		return id
	end
	function sim.leave(id: string)
		local h = sim.humans[id]
		controller.removeHuman(id)
		sim.humans[id] = nil
		bodies[id] = nil
		if h then
			statsBook:leave(h.userId)
			sim.gone[id] = h -- the saved coins stay readable (a real profile is saved, not dropped)
		end
	end
	function sim.press(id: string)
		controller.setReady(id, true)
	end
	function sim.coins(id: string): number
		local h = sim.humans[id] or sim.gone[id]
		local p = if h then progressStore.read(h.player) else nil
		return if p then p.coins else 0
	end
	function sim.daily(id: string): any
		local h = sim.humans[id]
		return if h then dailyStore.read(h.player) else nil
	end
	function sim.now(): number
		return t
	end

	-- ===== the heartbeat =====
	local sinceFill, sinceCollect = 0, 0
	local resultsSeenAt: { [number]: number } = {}
	function sim.step()
		t += MatchSim.TICK
		local ok, err = pcall(controller.update)
		if not ok then
			fail("match update", err)
		end
		sinceFill += MatchSim.TICK
		if sinceFill >= 1 - 1e-9 then
			sinceFill = 0
			local okFill, errFill = pcall(autoFillTick)
			if not okFill then
				fail("bot fill", errFill)
			end
		end
		local okRun, errRun = pcall(function()
			runner:step()
		end)
		if not okRun then
			fail("bot runner", errRun)
		end
		moveBodies(MatchSim.TICK)
		for id, f in fighters do
			if next(f.weapons.reloadEndsAt) ~= nil then
				f.weapons:update(t, function(slot: number)
					return slotStats(id, slot)
				end)
			end
		end
		local okZone, errZone = pcall(function()
			zone:step()
		end)
		if not okZone then
			fail("zone step", errZone)
		end
		sinceCollect += MatchSim.TICK
		if sinceCollect >= 0.25 then
			sinceCollect = 0
			collectNearby()
		end
		for i = #pendingPicks, 1, -1 do
			local pick = pendingPicks[i]
			if t >= pick.at then
				table.remove(pendingPicks, i)
				tryChoose(pick.id, pick.matchId, pick.offerId, pick.option)
			end
		end
		for id, o in table.clone(orbs) do
			if t >= o.data.expiresAt then
				orbs[id] = nil
			end
		end
		-- The results screen: the client claims at once; people who want another go tap Play again.
		if ctx:getPhase() == MatchPhase.Results then
			local matchId = ctx:getMatchId()
			resultsSeenAt[matchId] = resultsSeenAt[matchId] or t
			for id in sim.humans do
				controller.claimResults(id, matchId)
				if sim.replay[id] and t - resultsSeenAt[matchId] >= 2 then
					controller.setReady(id, true)
				end
			end
		end
	end

	-- Steps until `done()` is true or `limit` seconds pass. Returns whether done() became true.
	function sim.runUntil(done: () -> boolean, limit: number): boolean
		local stop = t + limit
		while t < stop do
			if done() then
				return true
			end
			sim.step()
		end
		return done()
	end
	function sim.untilPhase(phase: string, limit: number): boolean
		return sim.runUntil(function()
			return ctx:getPhase() == phase
		end, limit)
	end

	return sim
end

return MatchSim

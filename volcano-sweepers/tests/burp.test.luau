--!strict
local BurpDirector = require("../src/shared/Burp/BurpDirector")
local BurpTuning = require("../src/shared/Burp/BurpTuning")
local Config = require("../src/shared/Config")
local Harness = require("./harness")
local Layout = require("../src/shared/Ash/Layout")
local Rng = require("../src/shared/Rng")
local Types = require("../src/shared/Types")

type Event = BurpDirector.BurpEvent
type Bomb = Types.Bomb

local DT = 0.5
local hub = Config.World.hub
local HUB_SAFE = hub.clearRadius + BurpTuning.hubSafeMargin

type Fake = { userId: number, x: number, z: number, zone: number }

local function fakePlayers(rng: Rng.Rng, count: number): { Fake }
	local out: { Fake } = {}
	for k = 1, count do
		local zone = rng:int(1, 5)
		local def = Config.World.zones[zone]
		local r = rng:range(def.inner + 3, def.outer - 3)
		local a = rng:range(0, 6.28)
		table.insert(out, { userId = k, x = r * math.cos(a), z = r * math.sin(a), zone = zone })
	end
	return out
end

local function wander(rng: Rng.Rng, p: Fake)
	local a = rng:range(0, 6.28)
	p.x += math.cos(a) * 3
	p.z += math.sin(a) * 3
	local r = math.sqrt(p.x * p.x + p.z * p.z)
	local target = math.clamp(r, 35, 245)
	p.x, p.z = p.x * target / r, p.z * target / r
	p.zone = Layout.zoneAt(p.x, p.z) or p.zone
end

type Log = {
	events: { { t: number, ev: Event } },
	phases: { Event },
	rumbleStarts: { number },
	bombs: { { bomb: Bomb, t: number, nearest: number } },
	perfects: { { t: number, untilAt: number } },
	hits: number,
	burpHits: { [number]: boolean }, -- rumble index -> someone was hit
	rumbles: number,
	lastLanded: number,
}

-- Run the director against fake players the way the server glue will.
local function simulate(
	seed: number,
	seconds: number,
	opts: {
		players: number,
		clean: number,
		dodge: boolean?,
		presentFrom: number?,
		presentUntil: number?,
		overrides: { [string]: any }?,
	}
): (Log, BurpDirector.BurpDirector)
	local rng = Rng.new(seed)
	local director = BurpDirector.new(Rng.new(seed + 1), opts.overrides)
	local players = fakePlayers(rng, opts.players)
	local log: Log = {
		events = {},
		phases = {},
		rumbleStarts = {},
		bombs = {},
		perfects = {},
		hits = 0,
		burpHits = {},
		rumbles = 0,
		lastLanded = 0,
	}
	local live: { [number]: Bomb } = {}
	local t = 0
	while t <= seconds do
		local present = (opts.presentFrom == nil or t >= opts.presentFrom)
			and (opts.presentUntil == nil or t < opts.presentUntil)
		local positions: { BurpDirector.PlayerPos } = {}
		if present then
			for _, p in players do
				wander(rng, p)
				table.insert(positions, { userId = p.userId, x = p.x, z = p.z, zone = p.zone })
			end
		end
		local events = director:step(t, {
			playerPositions = positions,
			cleanTotal = opts.clean,
			playerCount = if present then #players else 0,
		})
		for _, ev in events do
			table.insert(log.events, { t = t, ev = ev })
			if ev.kind == "phase" then
				table.insert(log.phases, ev)
				if ev.phase == "rumble" then
					log.rumbles += 1
					table.insert(log.rumbleStarts, ev.startsAt :: number)
				end
			elseif ev.kind == "bombs" then
				for _, b in ev.bombs :: { Bomb } do
					live[b.id] = b
					local nearest = math.huge
					for _, p in positions do
						nearest = math.min(nearest, math.sqrt((p.x - b.x) ^ 2 + (p.z - b.z) ^ 2))
					end
					table.insert(log.bombs, { bomb = b, t = t, nearest = nearest })
				end
				if opts.dodge then
					-- dodgers step out of every circle they are standing in
					for _, p in players do
						for _ = 1, 12 do
							local moved = false
							for _, b in live do
								local dx, dz = p.x - b.x, p.z - b.z
								local d = math.sqrt(dx * dx + dz * dz)
								if d < b.radius + 4 then
									local push = b.radius + 6 - d
									if d < 0.01 then
										dx, dz, d = 1, 0, 1
									end
									p.x += dx / d * push
									p.z += dz / d * push
									moved = true
								end
							end
							if not moved then
								break
							end
						end
					end
				end
			elseif ev.kind == "land" then
				local b = live[ev.bombId :: number]
				Harness.truthy(b ~= nil, "land refers to a known bomb")
				Harness.truthy(b.landsAt <= t + 1e-9, "never lands early")
				live[b.id] = nil
				for _, p in players do
					if present and director:hitTest(b, p.x, p.z) then
						log.hits += 1
						log.burpHits[log.rumbles] = true
						director:reportHit(p.userId, t)
					end
				end
			elseif ev.kind == "perfect" then
				table.insert(log.perfects, { t = t, untilAt = ev.untilAt :: number })
			end
		end
		t += DT
	end
	return log, director
end

local function mean(list: { number }): number
	local s = 0
	for _, v in list do
		s += v
	end
	return s / #list
end

local NEXT: { [string]: string } =
	{ calm = "rumble", rumble = "event", event = "recover", recover = "calm" }

Harness.test("burp: 2 hours always follow calm > rumble > event > recover", function()
	local log = simulate(1, 7200, { players = 6, clean = 0.5 })
	Harness.truthy(#log.phases > 100, "many phase changes")
	Harness.eq(log.phases[1].phase, "calm")
	local kindSeen: { [string]: number } = {}
	for k = 2, #log.phases do
		local prev, cur = log.phases[k - 1], log.phases[k]
		Harness.eq(cur.phase, NEXT[prev.phase :: string], `phase {k}`)
		Harness.truthy((cur.startsAt :: number) >= (prev.startsAt :: number))
		Harness.near(
			cur.startsAt :: number,
			prev.endsAt :: number,
			1.0,
			"phases chain end to start"
		)
		Harness.truthy((cur.endsAt :: number) > (cur.startsAt :: number))
		if cur.phase == "rumble" then
			Harness.near((cur.endsAt :: number) - (cur.startsAt :: number), BurpTuning.rumble, 1e-9)
			Harness.truthy(cur.burpKind ~= nil)
		elseif cur.phase == "event" then
			Harness.eq(cur.burpKind, prev.burpKind, "event keeps the rumble's kind")
			kindSeen[cur.burpKind :: string] = (kindSeen[cur.burpKind :: string] or 0) + 1
		elseif cur.phase == "recover" then
			Harness.eq(cur.burpKind, prev.burpKind)
			Harness.near(
				(cur.endsAt :: number) - (cur.startsAt :: number),
				BurpTuning.recover,
				1e-9
			)
		else
			Harness.eq(cur.burpKind, nil, "calm has no kind")
		end
	end
	for _, kind in { "pops", "ashStorm", "golden", "geysers" } do
		Harness.truthy((kindSeen[kind] or 0) >= 5, `{kind} happens`)
	end
	-- pops are the most common, geysers the least (weights 40 vs 15)
	Harness.truthy(kindSeen.pops > kindSeen.geysers)
end)

Harness.test("burp: event durations match tuning", function()
	local log = simulate(2, 7200, { players = 4, clean = 0.5 })
	local want: { [string]: number } = {
		pops = BurpTuning.popsDuration,
		ashStorm = BurpTuning.stormDuration,
		golden = BurpTuning.goldenDuration,
		geysers = BurpTuning.geyserDuration,
	}
	for _, ph in log.phases do
		if ph.phase == "event" then
			local d = (ph.endsAt :: number) - (ph.startsAt :: number)
			Harness.near(d, want[ph.burpKind :: string], 1e-9, ph.burpKind)
		end
	end
end)

Harness.test("burp: no players, no burps; sleeps, then waits again for the first burp", function()
	local log = simulate(3, 3000, { players = 5, clean = 0.5, presentFrom = 1e9 })
	Harness.eq(#log.events, 0, "nobody there: no events at all")
	-- first player at t=1000: first rumble no earlier than 75 s later
	local log2 = simulate(4, 3000, { players = 3, clean = 0.5, presentFrom = 1000 })
	Harness.truthy(#log2.rumbleStarts > 0)
	Harness.truthy(log2.rumbleStarts[1] >= 1000 + 75, `first rumble at {log2.rumbleStarts[1]}`)
	Harness.truthy(log2.events[1].t >= 1000, "nothing before the first player")
	-- everybody leaves in the middle: it calms down, stays silent, and restarts the 75 s wait
	for seed = 10, 14 do
		local log3 = simulate(seed, 3000, { players = 4, clean = 0.5, presentUntil = 700 })
		local last = log3.events[#log3.events]
		Harness.eq(log3.phases[#log3.phases].phase, "calm", "ends calm")
		Harness.truthy(last.t <= 700 + DT, "silent after everyone left")
	end
	local gapLog = simulate(15, 2000, { players = 4, clean = 0.5, presentUntil = 700 })
	Harness.truthy(#gapLog.rumbleStarts >= 1)
end)

Harness.test("burp: first burp waits 75 s for many seeds", function()
	for seed = 1, 40 do
		local log = simulate(seed * 7, 400, { players = 2, clean = 1 })
		Harness.truthy(log.rumbleStarts[1] ~= nil, "first rumble comes")
		Harness.truthy(
			log.rumbleStarts[1] >= 75,
			`seed {seed}: first rumble at {log.rumbleStarts[1]}`
		)
		Harness.truthy(log.rumbleStarts[1] <= 75 + BurpTuning.firstBurpJitter + DT)
	end
end)

Harness.test(
	"burp: rumble-to-rumble gap follows the tuning and shrinks as the island gets clean",
	function()
		local function gaps(clean: number, seed: number): { number }
			local log = simulate(seed, 14400, { players = 5, clean = clean })
			local out: { number } = {}
			for k = 2, #log.rumbleStarts do
				table.insert(out, log.rumbleStarts[k] - log.rumbleStarts[k - 1])
			end
			return out
		end
		local dirty, clean = gaps(0, 5), gaps(1, 6)
		local mid = gaps(0.5, 7)
		for _, g in dirty do
			Harness.truthy(
				g >= 0.9 * BurpTuning.gapMax - 1 and g <= 1.1 * BurpTuning.gapMax + 1,
				`dirty gap {g}`
			)
		end
		for _, g in clean do
			Harness.truthy(
				g >= 0.9 * BurpTuning.gapMin - 1 and g <= 1.1 * BurpTuning.gapMin + 3,
				`clean gap {g}`
			)
		end
		Harness.near(mean(dirty), 140, 6, "dirty mean")
		Harness.near(mean(clean), 82, 6, "clean mean")
		Harness.near(mean(mid), 110, 6, "half clean mean")
		Harness.truthy(mean(dirty) > mean(mid) and mean(mid) > mean(clean))
	end
)

Harness.test("burp: bombs are fair, aimed and on the island", function()
	local log = simulate(8, 7200, { players = 5, clean = 0.5 })
	Harness.truthy(#log.bombs > 300, `{#log.bombs} bombs`)
	local close = 0
	local hubX = hub.radius * math.cos(math.rad(hub.angleDeg))
	local hubZ = hub.radius * math.sin(math.rad(hub.angleDeg))
	local seen: { [number]: boolean } = {}
	for _, rec in log.bombs do
		local b = rec.bomb
		Harness.truthy(not seen[b.id], "unique ids")
		seen[b.id] = true
		Harness.truthy(b.landsAt - rec.t >= 1.5 - 1e-9, `telegraph {b.landsAt - rec.t}`)
		Harness.near(b.radius, BurpTuning.bombRadius)
		local r = math.sqrt(b.x * b.x + b.z * b.z)
		Harness.truthy(r >= Layout.innerRadius and r <= Layout.outerRadius, "on the island")
		-- the island is big: every bomb (decoys too) lands near somebody
		Harness.truthy(
			rec.nearest <= BurpTuning.decoyOffsetMax + 2,
			`bomb {rec.nearest} studs from the nearest player`
		)
		Harness.truthy(
			math.sqrt((b.x - hubX) ^ 2 + (b.z - hubZ) ^ 2) > HUB_SAFE,
			"never at the hub"
		)
		if rec.nearest <= BurpTuning.aimOffsetMax + 1 then
			close += 1
		end
	end
	Harness.truthy(close / #log.bombs > 0.6, `{close}/{#log.bombs} bombs aimed at a player`)
	-- every bomb lands, in the order it was announced
	local lands = 0
	local lastId = 0
	for _, rec in log.events do
		if rec.ev.kind == "land" then
			lands += 1
			Harness.truthy((rec.ev.bombId :: number) > lastId, "landing order")
			lastId = rec.ev.bombId :: number
		end
	end
	Harness.truthy(lands >= #log.bombs - 20)
end)

Harness.test("burp: a late server step never shortens the warning", function()
	local director = BurpDirector.new(Rng.new(5), { firstBurpDelay = 1, firstBurpJitter = 0 })
	local ctx = {
		playerPositions = { { userId = 1, x = 0, z = -120, zone = 3 } },
		cleanTotal = 0,
		playerCount = 1,
	}
	local seen = 0
	local t = 0
	while t < 600 do
		-- steps are 1 second apart: waves are often found already a bit old
		for _, ev in director:step(t, ctx) do
			if ev.kind == "bombs" then
				for _, b in ev.bombs :: { Bomb } do
					seen += 1
					Harness.truthy(b.landsAt - t >= BurpTuning.minTelegraph - 1e-9, "warning kept")
				end
			end
		end
		t += 1
	end
	Harness.truthy(seen > 5)
end)

Harness.test("burp: perfect dodge only when nobody was hit", function()
	-- wandering players get hit sometimes
	local log = simulate(9, 14400, { players = 6, clean = 0.5 })
	local popsEnds = 0
	local perfect = 0
	local rumbleIdx = 0
	local perfectAt: { [number]: boolean } = {}
	local ends: { [number]: Event } = {}
	for _, rec in log.events do
		local ev = rec.ev
		if ev.kind == "phase" and ev.phase == "rumble" then
			rumbleIdx += 1
		elseif ev.kind == "phase" and ev.phase == "recover" then
			ends[rumbleIdx] = ev
		elseif ev.kind == "perfect" then
			perfect += 1
			perfectAt[rumbleIdx] = true
			Harness.truthy(not log.burpHits[rumbleIdx], "perfect awarded after a hit")
			Harness.eq(
				ends[rumbleIdx] ~= nil and ends[rumbleIdx].burpKind,
				"pops",
				"only lava pops award it"
			)
			Harness.near((ev.untilAt :: number) - rec.t, BurpTuning.perfectBuffSeconds, 1e-6)
		end
	end
	for idx, ev in ends do
		if ev.burpKind == "pops" then
			popsEnds += 1
			if log.burpHits[idx] then
				Harness.truthy(not perfectAt[idx], "hit means no perfect")
			end
		end
	end
	Harness.truthy(log.hits > 0, "someone got hit in the wandering run")
	-- dodgers: no hits, so perfect comes after (nearly) every lava pops event
	local dodgeLog = simulate(10, 14400, { players = 6, clean = 0.5, dodge = true })
	local dPops, dPerfect = 0, 0
	for _, ph in dodgeLog.phases do
		if ph.phase == "recover" and ph.burpKind == "pops" then
			dPops += 1
		end
	end
	dPerfect = #dodgeLog.perfects
	Harness.truthy(dPops > 10)
	Harness.truthy(
		dPerfect >= dPops - dodgeLog.hits,
		`{dPerfect} perfect for {dPops} pops, {dodgeLog.hits} hits`
	)
	Harness.truthy(dPerfect > 0)
	Harness.truthy(popsEnds > 10 and perfect >= 0)
end)

Harness.test("burp: reportHit before the end blocks the perfect buff", function()
	for _, hitIt in { true, false } do
		local d = BurpDirector.new(Rng.new(21), {
			firstBurpDelay = 1,
			firstBurpJitter = 0,
			kindWeights = { pops = 1, ashStorm = 0, golden = 0, geysers = 0 },
			repeatPenalty = 1,
		})
		local ctx = {
			playerPositions = { { userId = 7, x = 0, z = -120, zone = 3 } },
			cleanTotal = 0.5,
			playerCount = 1,
		}
		local perfect = false
		local landed = 0
		local t = 0
		while t < 90 and not perfect do
			for _, ev in d:step(t, ctx) do
				if ev.kind == "land" then
					landed += 1
					if hitIt and landed == 2 then
						d:reportHit(7, t)
					end
				elseif ev.kind == "perfect" then
					perfect = true
				end
			end
			t += 0.25
		end
		Harness.truthy(landed > 5, "bombs landed")
		Harness.eq(perfect, not hitIt)
		-- a hit while calm is ignored
		local calm = BurpDirector.new(Rng.new(1))
		calm:reportHit(1, 0)
		Harness.eq(calm:getState().phase, "calm")
	end
end)

Harness.test("burp: hitTest uses radius plus body radius", function()
	local d = BurpDirector.new(Rng.new(1))
	local bomb: Bomb = { id = 1, x = 10, z = 20, radius = 7, landsAt = 5 }
	Harness.eq(d:hitTest(bomb, 10, 20), true)
	Harness.eq(d:hitTest(bomb, 10 + 7, 20), true)
	Harness.eq(d:hitTest(bomb, 10 + 7.4, 20), true, "body radius counts")
	Harness.eq(d:hitTest(bomb, 10 + 7.6, 20), false, "outside the drawn ring is safe")
	Harness.eq(d:hitTest(bomb, 10, 20 - 9), false)
end)

Harness.test("burp: event contents (storm pulses, golden, geysers)", function()
	local log = simulate(11, 14400, { players = 5, clean = 0.5 })
	local phaseOf: { [number]: Event } = {}
	local current: Event? = nil
	local rain: { number } = {}
	local goldenCount, geyserWaves = 0, 0
	local stormEvents, goldenEvents, geyserEvents = 0, 0, 0
	for _, rec in log.events do
		local ev = rec.ev
		if ev.kind == "phase" then
			if ev.phase == "event" then
				current = ev
				if ev.burpKind == "ashStorm" then
					stormEvents += 1
				elseif ev.burpKind == "golden" then
					goldenEvents += 1
				elseif ev.burpKind == "geysers" then
					geyserEvents += 1
				end
			end
		elseif ev.kind == "rain" then
			Harness.eq((current :: Event).burpKind, "ashStorm")
			Harness.near(ev.fraction :: number, BurpTuning.stormFraction)
			table.insert(rain, rec.t)
		elseif ev.kind == "golden" then
			goldenCount += 1
			Harness.eq((current :: Event).burpKind, "golden")
			Harness.near(ev.untilAt :: number, (current :: Event).endsAt :: number, 1e-9)
			Harness.truthy(
				(ev.cells :: number) >= BurpTuning.goldenBaseCells
					and (ev.cells :: number) <= BurpTuning.goldenMaxCells
			)
		elseif ev.kind == "geysers" then
			geyserWaves += 1
			Harness.eq((current :: Event).burpKind, "geysers")
			local spots = ev.spots :: { BurpDirector.Spot }
			Harness.truthy(#spots >= 1 and #spots <= BurpTuning.geyserSpotsMax)
			for _, s in spots do
				local r = math.sqrt(s.x * s.x + s.z * s.z)
				Harness.truthy(r >= Layout.innerRadius and r <= Layout.outerRadius)
				Harness.truthy(
					math.sqrt((s.x - Layout.hubX) ^ 2 + (s.z - Layout.hubZ) ^ 2) > HUB_SAFE
				)
			end
		end
		phaseOf[#phaseOf + 1] = ev
	end
	Harness.eq(#rain, stormEvents * 5, "5 rain pulses per ash storm")
	Harness.eq(goldenCount, goldenEvents, "one golden event per golden burp")
	Harness.eq(geyserWaves, geyserEvents * 2, "2 geyser waves per geyser burp")
	Harness.truthy(stormEvents > 3 and goldenEvents > 3 and geyserEvents > 3)
end)

Harness.test("burp: same rng, same events; different rng, different events", function()
	local function fingerprint(seed: number): string
		local log = simulate(seed, 3600, { players = 4, clean = 0.3 })
		local parts: { string } = {}
		for _, rec in log.events do
			local ev = rec.ev
			local extra = ""
			if ev.bombs then
				local b = (ev.bombs :: { Bomb })[1]
				extra = string.format("%.3f,%.3f", b.x, b.z)
			end
			table.insert(parts, `{rec.t}:{ev.kind}:{ev.phase or ""}:{ev.burpKind or ""}:{extra}`)
		end
		return table.concat(parts, "|")
	end
	Harness.eq(fingerprint(30), fingerprint(30))
	Harness.truthy(fingerprint(30) ~= fingerprint(31))
end)

Harness.test("burp: survives a huge time jump and keeps the order", function()
	local d = BurpDirector.new(Rng.new(2))
	local ctx = {
		playerPositions = { { userId = 1, x = 0, z = -150, zone = 2 } },
		cleanTotal = 0.5,
		playerCount = 1,
	}
	d:step(0, ctx)
	local events = d:step(100000, ctx)
	Harness.truthy(#events > 100)
	local prev: string? = nil
	for _, ev in events do
		if ev.kind == "phase" then
			if prev ~= nil then
				Harness.eq(ev.phase, NEXT[prev])
			end
			prev = ev.phase
		end
	end
	local st = d:getState()
	Harness.eq(st.awake, true)
	Harness.truthy(#d:activeBombs() >= 0)
end)

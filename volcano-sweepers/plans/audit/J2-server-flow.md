# J2 - Server integration trace (read-only judge)

Lens: follow each server flow across modules and check every call against the callee's real signature,
field names, tags, remote names, load order, return values and the Rojo tree. Method: read every file on
the paths below, then confirmed doubtful points by running small throwaway Lune scripts against the real
`src/shared` modules (scratch dir only, nothing under `src/` or `tests/` was touched).
State of the tree when judged: `lune run tests/run` = 465 passed, 0 failed. `rojo build` ok.
`rojo sourcemap` shows `ServerScriptService/Server` (Folder) with `Main` (Script) and the 9 service folders,
`StarterPlayerScripts/Client` (Folder) with `Main` (LocalScript), `ReplicatedStorage/Shared` (Folder).

Summary: no verified BLOCKER on the single-player path. 3 MAJOR, 8 MINOR, 1 unverifiable release gate.

---------------------------------------------------------------------------------------------------
## 0. Release gate that cannot be checked without Studio (not counted as a finding)

G1. Every file under `src/shared` pulls its neighbours with string requires (`require("./Config")`,
`require("../Rules/StatsCalc")`, e.g. `src/shared/Rules/StatsCalc.luau:27-32`), while server and client use
instance requires (`require(Shared.Rules.StatsCalc)`). If the Studio carter publishes from does not have
relative string `require` switched on, EVERY shared module errors on load and the whole game is dead (all
server services fail their pcall(require) in `Main.server.luau:46`, the client prints a warning per module).
Lune accepts these paths, so the 465 green tests prove nothing about it.
Check (30 seconds): build the .rbxl, press Run once, look at Output for "[Boot] server ready: 14 services started, 0 skipped".
Fallback if it fails: mechanical swap to `require(script.Parent.X)` (shared pure files never use `script`, so tests would need a shim).

---------------------------------------------------------------------------------------------------
## 1. MAJOR

### M1. `PlayerState.setBuff` throws while any player is still loading: party/perfect/golden buffs break for everyone
- `src/server/Player/PlayerState.luau:173-185` (`setBuff`), `:150-155` (`recompute`), `:334-348` (`newState`), `:355-364` (`track`).
- Why: `track` creates a State for every player the moment they join (`PlayerAdded`), with `profile = {}` and
  `derived = {}` (the `blank` table, lines 335-341) until Profile load + ClientReady finish (seconds; up to ~20 s
  when the profile is still locked by a previous server, see `ProfileStore.load` lock retries).
  `setBuff` loops over ALL `states` (not `PlayerState.all()`) and calls `recompute`, which calls
  `StatsCalc.compute(s.profile, ...)`. With `profile = {}` that dies at `src/shared/Rules/StatsCalc.luau:73`
  (`level()` does `map[id]` with `map = profile.upgrades = nil`).
  Confirmed by running `StatsCalc.compute({}, {}, 0)` in Lune: `attempt to index nil with 'sell'`.
- Failing scenario (4 callers: `AshService.luau:158` party, `BurpService.luau:311` golden, `:316` perfect, and the
  expiry `task.delay` inside setBuff itself): 8 friends are playing, a 9th joins; during the ~5-20 s his state is
  blank, the island hits a 25% milestone. `celebrate` runs `ProgressRules.update` first (milestone already consumed),
  then `setBuff` throws on the blank state: the error aborts `celebrate` (no gift coins, no `Party` remote, no toast, caught
  by `guarded` at AshService.luau:198) AND `setBuff` itself stops mid-loop: players earlier in the (unordered) `pairs` order got
  recomputed, later ones did not, and the `task.delay(...)` on line 180 was never scheduled, so the x2 never expires for the
  ones who did get it (they keep `derived.sellMult` doubled until some unrelated `recompute`, e.g. any purchase).
  Same hole for Perfect Dodge and Golden. In a 16-player server joins are constant, so this fires often.
- Fix: iterate ready states only. In `setBuff` use `for _, s in PlayerState.all() do` (both loops, lines 175 and 181), or guard
  inside `recompute` with `if not s.ready then return end`. Also make the expiry timer schedule BEFORE the loop so one bad
  state can never skip it. One-line extra safety: wrap each `recompute` in `pcall`.

### M2. Golden cells are invisible on every cell that was bare ground (client drops them: remote arrives before the level delta)
- Server: `src/server/Burp/BurpService.luau:307-309`. Client: `src/client/Ash/AshRenderer.luau:317-323`.
- Why: `spawnGolden` (`AshGrid.luau:405-427`) picks random cells in unlocked zones regardless of level and tops each up to
  >= 6 (`write` -> dirty list). `BurpService` fires `Golden` immediately, but the level change only goes out in the next
  AshDelta flush (`AshService.luau:275-278`, up to 0.1 s later, a different remote, same ordered channel after Golden).
  The client's Golden handler only accepts a cell when `levels[i] > 0 or not AshRenderer.loaded` (line 321). A cell that was
  bare on the client still reads 0 when Golden arrives, so it is skipped. The golden flag then never comes back
  (the later AshDelta only raises the level; nothing re-applies the flag).
- Failing scenario: the co-op "race for gold" is most likely when the island is already fairly clean, which is exactly when most
  chosen cells are 0. If 60% of the allowed cells are bare, 60% of the gold is not drawn, but the server still pays 5x on them
  (`AshGrid.sweep` uses `goldenSet`). Players see a handful of gold cells, sweep random bare-looking cells and get surprise
  5x: feels like a bug,.
- Fix (either): (a) client: drop the `levels[i] > 0` test at AshRenderer.luau:321 (a flagged cell that is 0 simply stays hidden until the
  delta raises it; `setGolden(i,false)` already fires when a delta sets it to 0). (b) server: flush the grid before firing, e.g. expose
  `AshService.flushNow()` (call the existing `flushDelta()`), call it just before `Net.fireAll("Golden", ...)` at BurpService.luau:309.
  Do (a); (b) is belt and braces.

### M3. The cone ignores `reach` and `arc` for everything within 8 studs: Reach upgrade levels 1-3 do nothing, Push Broom is +8% not "a whole row"
- `src/shared/Ash/AshGrid.luau:146` (`local near2 = cs * cs`) and `:169` (`local ok = d2 <= near2`).
- Why: any cell whose CENTRE is within `cellSize` (8 studs) of the player is taken regardless of facing or reach, so the cone only
  matters beyond 8 studs. The Twig Broom has reach 7, the Push Broom 9.
  Measured with the real `AshGrid:queryCone`, 6,000 sampled positions/facings in zone 1 (average cells hit per swing):
  twig 3.03 | twig with Reach +4/+8/+12% (7.28/7.56/7.84) 3.03 | push_broom (9, 110 deg) 3.29 | leaf_blower 4.00 |
  dust_vac 4.04 | turbo_vac 5.17 | lava_mop 5.17 (identical to turbo: same reach/arc) | dragon_vac 6.03 | volcano_vac 18.09.
  A circle of radius 8 on an 8-stud grid is pi cells = 3.14: that is what you get with any tool under reach 8.
- Failing scenario (first 5 minutes): the kid buys Reach (120 coins, the "clear and obvious" first upgrade) and gets zero visible
  change for 3 purchases (reach must exceed 8.0 = Twig needs +15% = level 4). Buys the 130-coin Push Broom whose blurb says "clears
  a whole row at once" and sweeps 8.6% more cells; turning does nothing for arc either (the arc test `AshGrid.luau:170-173` is skipped
  for the nearby circle). Violates CONTRACTS "nothing is a trap, higher level strictly helps" and lens 3/10 clarity.
- Fix: measure range to the cell EDGE and shrink the always-hit core to the player's own cell. In `collectCone` replace
  `near2 = cs*cs` with `near2 = (cs * 0.5)^2` (only the cell you stand on / next to) and test `d2 <= (reach + cs*0.5)^2` for the
  cone (`reach2` at line 145). Then twig reach 7 with a 80 deg arc is a real forward fan, Reach +4% adds cells at the fringe, and Push
  Broom/arc are visible. Re-run `tests/ash.test.luau` (it asserts cone membership) and `tests/pacing.test.luau`: first-sale and
  first-upgrade timings will move, so retune `power`/`capacityBonus` or accept. Also give Lava Mop a different shape from Turbo Vac.

---------------------------------------------------------------------------------------------------
## 2. MINOR

m1. Goal "Island Regular" (3600 s play) cannot complete inside a session. `stats.playSeconds` is only added in `Profiles.onLeaving`
(`PlayerState.luau:368-372`); nothing ticks it. A 70-minute session shows 0/3600 and the 10 s ready-check in `GoalService.luau` never
sees it; a crash loses the time. Fix: a 10 s loop (or reuse GoalService's) doing `PlayerState.addStat(player, "playSeconds", 10)` for ready
players, delete the leave-time addition (or add only the remainder).

m2. Spark perk "Long Buffs" ("Party and Perfect Dodge boosts last longer", `SparkPerks.luau:91-94`) only stretches Perfect. Party uses a fixed
`PARTY_SECONDS = 60` (`AshService.luau:37,158`); CONTRACTS says `60 s x buffTime`. Fix:
`PlayerState.setBuff("party", now + PARTY_SECONDS * best)` where `best` is the largest `derived.buffTime` over `PlayerState.all()`, clamped to `BurpGlue.maxBuffMult` (same idea as `bestBuffTime`, BurpService.luau:252-261).

m3. Lava hit radius is wider than the drawn ring and is judged late. Ring drawn at `bomb.radius` = 7 (`Vfx.luau:806`), `hitTest` uses `radius + bodyRadius`
= 8.5 (`BurpDirector.luau:446`, `BurpTuning.luau:82`), positions are sampled on the 0.25 s tick after `landsAt` (`BurpService.luau:322-362`,
`TICK_SECONDS`), with no latency allowance. A player visibly 1 stud outside the ring gets bonked. Fix: draw the ring at `radius + bodyRadius`
(send `radius = tun.bombRadius + tun.bodyRadius` or set `bodyRadius = 0.5`), and step the director at 0.1 s while a bomb is within 0.5 s of landing.

m4. Helper bots never call `AshService.noteSwept`, although `AshService.luau:7` says they do. `HelperService.luau:233` removes ash, but the adaptive
regrow (`regrowStep`) only counts player swings, so a server of mostly bot income regrows at the slow base rate. Fix: `AshService.noteSwept(result.units)` after line 233
(HelperService already lazy-requires the AshService module).

m5. `default.project.json:43` sets `StarterGui.ScreenOrientation = "LandscapeSensor"`. DESIGN.md and CONTRACTS UI rules say "Landscape and portrait
both usable" and test at 360x640 portrait; this locks phones to landscape. Fix: `"Sensor"` if portrait is intended, or update the docs if landscape-only is the decision.

m6. Bounce is applied from the server: `BurpService.luau:187-193` sets `AssemblyLinearVelocity` and calls `ChangeState(Freefall)` on a client-owned character. Both are inside
`pcall`, so it cannot throw, but whether the client honours it cannot be verified without Studio (S3 handoff already says so). The knockback is the only
"feel" of a hit. Safer: the existing `BurpHit` remote (or a new field in it: `vx,vy,vz`) lets the owning client apply the impulse to its own character; the server keeps the
drop/shield/stat authority.

m7. `Hub.build` / `Gates.build` are all-or-nothing: `folder.Parent = root` is the LAST statement (`src/server/World/Hub.luau:~243`, `Gates.luau:~148`) and `World.init` only
wraps the whole call in `run(...)` (`World.luau:241-247`). One API slip inside `buildHut`/`buildSpawns` removes ALL spawn pads, the hut and the sell prompt (Sell still works through the
remote + `SweepRules.hubXZ` fallback, but with no `SpawnLocation` every player spawns at the origin = inside the volcano core). Nobody has run this code. Fix: parent the folder first and
`pcall` each `buildX` separately; add `workspace.SpawnLocation`-style fallback (a plain `SpawnLocation` at `World.spawnPositions[1]` created before the risky steps).

m8. Handoff/doc drift: S3 handoff item 6 says no remote tells clients which cells are golden. `Golden` exists (`RemoteDefs.luau`) and is used. Update the handoff so the next author does not re-add it.

---------------------------------------------------------------------------------------------------
## 3. Flow-by-flow result (what was traced and found consistent)

1. Boot (`Main.server.luau`). All 14 entries in BOOT_ORDER resolve against the Rojo tree (`Core/Net`, `Profile/Profiles`, `Player/PlayerState`,
   `World/World`, `Ash/AshService`, `Sweep/SweepService`, `Sweep/SellService`, `Finds/FindsService`, `Burp/BurpService`, `Player/PurchaseService`,
   `Helpers/HelperService`, `Player/DailyService`, `GoalService`, `CoolDownService`); each exports `init`. Every `require(Shared.X.Y)` in `src/server` (checked by script)
   exists under `src/shared`. No require cycles (Net <- PlayerState <- Ash <- Sweep; Finds <- Geyser <- Burp; Helper/CoolDown/Burp use lazy pcall-requires). No
   yielding Signal listener (all `onReady`/`onLeaving`/`Loaded` listeners are synchronous; Daily uses `task.delay`). Shared pure code contains no `game`,
   `Instance`, `Color3`, `Vector3`, `task`, `os.time` (grep clean; only `Remotes.luau`, which is glue by design, touches services).
2. Join (Profiles -> PlayerState -> ClientReady -> fullSync -> AshSnapshot). Handlers are registered before any client can reach them (Net.init first, `ClientReady` in
   `PlayerState.init`, no yield in Main). Both orders (profile first / ClientReady first) end in `tryReady`; services started after a player is ready cover them via
   `PlayerState.all()` loops (Ash `welcome`, Sweep `readyPlayers`). Snapshot vs delta race is safe: deltas are absolute levels, the snapshot is taken at ready time
   (`AshService.luau:263`). Client sends `ClientReady` last (`Main.client.luau:109`) after every `Net.on` is attached.
3. Sweep. `SweepService.onSweep` -> `AshGrid:sweep(px,pz,dx,dz,tool,allowed,room,rng,sweet,zoneValues)` matches the signature (AshGrid.luau:249-261);
   `removedUnits`/`valueUnits`/`clearedCells` fields exist; `addCarried` clamps with the same `capacity - carried` as `room`, so value and units stay paired;
   `FindsService.onCleared(player, zoneId, count)` signature and `countByZone` reuse are correct (`rec.cleared` is zeroed every call); `SweepFx` goes only to others.
   Server uses HRP position + LookVector, never client data. Only M3 above.
4. Sell. `Sell` remote and the `VSSellPrompt` tag (added to the prompt before it is parented, hooked by `GetInstanceAddedSignal` + `GetTagged`) both land in one `sell()`;
   `takeCarried` before pay (no double sell), range uses the real pad positions (+4 slack) and the prompt's 14-stud reach on the counter is inside it. F key sends
   both the remote and the prompt: second call is dropped by the 0.25 s `allowEvery` before the empty-toast, so no spurious toast.
5. Buy. Client sends `Buy(kind, id)` as strings, including `"helper",""` and zone `tostring(id)`, which pass `Guard` (maxLen 16/32). `PurchaseRules.buy` re-quotes, spends and applies in one
   synchronous call. All 10 upgrade ids, 8 spark-perk ids, tools and zones used by `StatsCalc`/`Pricing` exist in the catalogs. Gate prompt: tag `VSGate`, attribute `ZoneId` (number),
   child `GatePrompt` created by `Gates.luau:134-144`, hooked with a 15 s `WaitForChild`; distance re-checked on the server. A throwaway sim bought every upgrade/tool/zone/helper/perk to max:
   profile stays `ProfileSchema.isValid`, `Serializable.check` passes, `coolDownReset` and `DailyRules.apply` copies stay valid (so Daily/Cool Down never get stuck on "invalid").
6. Burp cycle. `BurpDirector:step/reportHit/hitTest/getState` and the `BurpGlue.buildCommands` command fields match their use in `BurpService.execute`; bomb Parts, hit, shield,
   `dropCarried` -> `AshService.dropAround`, `BurpHit`, `burpHits/burpDodged`, perfect buff, geyser spawn/poll/pickup via `FindsService.grantGeyserGem`, `GeyserGems` two shapes handled by
   the client (`Vfx.luau:1229`). Golden: M2. No dangling remote names: every `Net.fire*/onRequest` string in `src/server` is in `RemoteDefs`.
7. Helpers. `HelperRules` and `BotModel` signatures match; bots are paid straight to the owner, only in unlocked zones; reconcile follows `profile.helpers`/`tool` each tick so Buy and Cool Down
   need no explicit call; leave cleans up (PlayerRemoving + PlayerState.onLeaving); 60-body cap shared fairly. Only m4.
8. Daily / Goal / ClaimSet / Cool Down. Daily pays through `grantOnce` with key `daily:<day>` (key validated), UTC day from `os.time()`, no yield between check and pay. Goal claim is
   check+flag+pay in one call. Cool Down runs inside `Profiles.update`, `ProfileSchema.assign` keeps the top-level table identity, then `takeCarried`, `recompute`, `fullSync`,
   `CoolDownDone`, `saveNow` in `task.spawn`. m1, m2 aside, correct.
9. Leave / save / rejoin. `PlayerRemoving` -> `m:leave` -> `Leaving` -> `PlayerState` adds playSeconds into the live profile -> background `release` (final save always writes, not only when dirty);
   autosave 60 s, BindToClose 25 s parallel, rejoin waits (<= 30 s) for the old release via `active[key]`, offline stand-in is `locked` and can never overwrite real data. Per-player tables in
   Net, Sweep, Sell, Finds, Purchase, Goal, Helper are all cleared on leave.
10. Mutation hazards. `Profiles.update/grantOnce` and Cool Down keep the top-level profile table but REPLACE the sub-tables (`ProfileSchema.assign`, `ProfileStore.luau:~452`). Grepped every server
    use of `profile.zones/upgrades/toolsOwned/stats/settings/finds/setsClaimed/goalsClaimed/sparkPerks/daily`: all are read fresh at the call, none is held across a yield or stored in a module table.
    Clean. The only held references are `PlayerState.State.profile` (the stable top-level table) and `buffs` (module table, never reassigned).

---------------------------------------------------------------------------------------------------
## 4. Scores (1-10, lens: server integration; "raise" = single biggest change)

| # | Line | Score | Why | Biggest raise |
|---|------|-------|-----|---------------|
| 1 | Core feel of sweeping | 6 | Server sweep path is sound and fast, but the 8-stud always-hit circle makes reach/arc/tool shape nearly invisible for the first tools (M3). | Fix `collectCone` core radius (M3). |
| 2 | Economy / pacing | 7 | Sell, buy, party gifts, find pay and bots all route through the same multipliers and tested rules; pacing sim is idealised and was not built on the real cone cell counts. | Re-run pacing after M3 and make the sim use `queryCone` cell counts. |
| 3 | Upgrade variety / clarity | 6 | Every catalog stat is wired to a server effect, but Reach 1-3 is a dud (M3), Push Broom/Lava Mop shapes overlap, and Long Buffs is half-wired (m2). | M3 plus m2. |
| 4 | Phone UI quality | 7 | Server side gives a short kid-friendly Toast for every accept and reject path; orientation is locked to landscape against the doc (m5); client UI itself not judged here. | Decide portrait vs landscape (m5). |
| 5 | Co-op feel | 6 | Shared grid, snapshots, deltas, party and gem pickup are consistent, but a joining player breaks party/perfect/golden buffs for the whole server (M1) and golden cells vanish (M2). | M1. |
| 6 | Volcano events fun / fairness | 6 | Director/glue integration is clean and bombs are server-authoritative; gold is half-invisible (M2), hits land outside the ring (m3), the bounce is unverified (m6). | M2, then m3. |
| 7 | Visual polish of the island | 7 (low confidence) | Only the build code was read: no API errors found, tags/lighting fine; look unseen; Hub/Gates all-or-nothing (m7). | Per-step pcall + spawn fallback (m7), then a Studio look. |
| 8 | Reliability (no errors, saves safe) | 7 | Save path is excellent (session lock, retry, release, offline lock, rejoin wait); the verified runtime error is M1; boot depends on unverified string requires (G1). | Fix M1 and run the 30-second boot check (G1). |
| 9 | Security (server decides) | 9 | Every remote goes through `Net` (schema + token bucket), handlers re-check state, position, range, price; client never sends position or amounts. Only soft spot: no speed/teleport sanity on HRP position. | Add a max-distance-per-second check on the Sweep/Sell position. |
| 10 | First 5 minutes | 7 | Spawn is 4 studs from the first cells, backpack fills in ~3 s (30 capacity / ~9 units/s measured above), first zone-1 party after roughly 1,200 swept units (estimate, not simulated); but the first two purchases (Reach, Push Broom) feel like nothing (M3). | M3. |

## 5. BLOCKER list
None verified. Conditional gate: G1 (string requires must be confirmed in Studio before anything else).

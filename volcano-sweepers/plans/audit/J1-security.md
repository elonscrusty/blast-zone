# J1 audit: server security and exploits (Volcano Sweepers)

Judge: J1. Lens: remotes, server authority, races, once-only grants, DataStore safety, bad numbers, memory per player.
Method: read every file under `src/server`, `src/shared/{RemoteDefs,Guard,Remotes,SaveRetry,Signal}.luau`, `src/shared/Profile/*`,
`src/shared/Player/*`, `src/shared/Rules/*`, `src/shared/Sweep/*`, `src/shared/Burp/BurpGlue.luau`. `lune run tests/run` = 465 passed, 0 failed.
Two findings were also proven by running small read-only Lune probes (in the scratchpad, nothing under src/ or tests/ was touched).

## Scores (1-10)

| Quality-bar line | Score | Why | Biggest single thing that raises it |
|---|---|---|---|
| 9 Security (server decides) | 7 | The remote surface is excellent (string/boolean-only args, rate limit before validation, no RemoteFunctions, every grant server-computed), but the character position is trusted with no movement check, and Island Party gifts go to people who did nothing. | Add a server movement monitor (M1) and pay party gifts only to recent sweepers (M2). |
| 8 Reliability, saves (my part) | 8 | Session lock, blank-overwrite protection, SaveRetry on every DataStore call, one-shot grants saved with their receipt, BindToClose all verified. Held back by the "locked for 3 minutes means a blank offline session" case (M3). | Background re-load (or a polite kick) for players whose profile is still locked (M3). |
| 8 Reliability, server runtime paths (my part) | 6 | One verified runtime error (B1) silently kills Island Party gifts and the party/perfect multipliers for the whole server whenever any player is still loading, and one idle account can do it forever. | Fix B1 (a 2-line `ready` guard). |

## BLOCKER

### B1. `PlayerState.recompute` / `setBuff` throw while any player is still loading: Island Party, Perfect Dodge and buff timers silently break server-wide, and one never-ready account can grief everyone
- Files: `src/server/Player/PlayerState.luau:150-155` (`recompute` has no `s.ready` check), `:173-185` (`setBuff` loops ALL `states`, then a `task.delay` loops them again), `:334-340` (`newState` sets `profile = blank` = `{}` and `derived = blank`), `:357-361` (`track` creates a state for every joiner at PlayerAdded), `:386` (a state only becomes ready after the profile loaded AND the client sent `ClientReady`).
- Proof: `src/shared/Rules/StatsCalc.luau:73` does `map[id]` with `map = profile.upgrades`, which is nil for the blank profile. I ran `StatsCalc.compute({}, {}, 0)` in Lune: `attempt to index nil with 'sell'`. So `recompute` throws for every unready state, and `setBuff` calls it for every state.
- Callers that die: `src/server/Ash/AshService.luau:158` (`celebrate` calls `setBuff("party")` BEFORE the gift loop at `:159-161` and before `Net.fireAll("Party")`), `src/server/Burp/BurpService.luau:311` (golden) and `:316` (perfect, the gold toast at `:318` is skipped too).
- Worse, the milestone is spent before the party runs: `AshService.luau:187-190` calls `ProgressRules.update` (which writes `tracker.celebrated`, `ProgressRules.luau:70`) and only then `celebrate`. A failed party is never retried.
- Exact scenario 1 (natural): 8 players, player H joins and spends 6 to 30 s loading. Player A pushes Fern Forest to 25%. `progressStep` -> `celebrate` -> `setBuff` throws at H -> no gift, no Party remote, no toast, no x2, and the 25% milestone is marked done forever. Same for the "Perfect Dodge" buff and toast.
- Scenario 2 (stuck multiplier): a party starts while everyone is ready, so all players get x2. A new player then joins and is still loading when the 60 s buff ends. The expiry callback (`:179-184`) loops `states` in table order, throws at the unready state, and skips everyone after it, so those players keep the x2 `derived.sellMult` until something else (a purchase, an equip) triggers `recompute`.
- Scenario 3 (grief exploit): a client that never fires `ClientReady` (executor user joins and kills its own `Main.client`, or a phone whose client init crashed) stays unready for the whole visit. Every `setBuff` in that server now throws for everyone ordered after that state. One account disables the co-op reward loop for 15 other people.
- Fix (2 lines): in `PlayerState.recompute` start with `if s == nil or not s.ready then return end`; in `setBuff` and its delayed callback loop `if s.ready then ... end`. `tryReady` sets `s.ready = true` (`:328`) before it calls `recompute`, so it still works. Also in `AshService.celebrate` move the `setBuff` call after the gift loop and wrap it in `pcall`, so a bad buff can never cancel the gift. Add a Lune test that calls the ready filter with a blank state.

## MAJOR

### M1. No movement or teleport check anywhere: every server rule that uses position trusts a client-owned HumanoidRootPart
- Files: `SweepService.luau:141-153` (sweep position and facing from HRP), `SellService.luau:86-122` (`nearSellSpot` from HRP), `GeyserService.luau:296-306` and `:322-333` (gem pickup), `PurchaseService.luau:50-62` (gate prompt), `BurpService.luau:153-178` and `:286-295` (hub safe zone, hit test). `grep -rn WalkSpeed|teleport|speed src/server` finds only `PlayerState` setting WalkSpeed; nothing ever compares two positions in time.
- Exact exploit (executor, works today):
```lua
local R = game.ReplicatedStorage.Remotes
local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
while true do
    hrp.CFrame = CFrame.new(goldenCellX, 3, goldenCellZ) * CFrame.Angles(0, math.rad(math.random(360)), 0)
    R.Sweep:FireServer()                 -- server accepts 1 swing per 0.8 x interval
    task.wait(0.8 * interval)
    if packFull then hrp.CFrame = hutPadCFrame; R.Sell:FireServer() end   -- zero-time trip
end
```
  Result: the 12 s "trip" the pacing is built on (CONTRACTS PACING) becomes 0 s, golden-cell races (the co-op rush) and geyser gems are won instantly by teleporting onto them, and the exploiter hops into the hub the moment a bomb lands (`BurpGlue.inHub`) so they never drop ash. Not infinite coins, but roughly 2 to 3 times income and it wrecks the co-op fairness the design sells.
- Fix: new `server/Core/MoveWatch.luau`. A 4 Hz Heartbeat step stores last HRP position and time per ready player. Allowed move per step = `(derived.walkSpeed * 1.5 + 6) * dt + 10` flat studs, plus a free pass for 3 s after `CharacterAdded` and after a lava bounce (`state.lastHitAt`). If exceeded: set `hrp.CFrame` back to the last good one and `state.suspectUntil = os.clock() + 3`; `onSweep`, `sell`, gem poll and gate prompt return early while `suspectUntil` is in the future; after 5 strikes in 60 s `player:Kick("Connection problem")`.

### M2. Island Party gifts are paid to every ready player, whatever they did or unlocked
- Files: `AshService.luau:151-175` (`for _, s in PlayerState.all() do PlayerState.addCoins(s.player, gift)`), `ProgressRules.luau:79-96` (`gift = 400 x zoneValue`, island 12,000), `Zones.luau` prices 400 / 4,000 / 70,000 / 1,800,000.
- Exact scenario: a veteran pushes Crater Rim to 25%: gift = 400 x 22 = 8,800 coins goes to a player who joined 10 seconds ago (zone 1 only; zone 2 costs 400, zone 3 costs 4,000). Zone 5 gift is 24,000. Alt accounts parked in the hub collect every gift, and each gift also counts as run earnings and lifetime coins (`PlayerState.addCoins` at `PlayerState.luau:197-210`), feeding Sparks. Friends can boost a new account past the first two gates in one milestone.
- Fix: in `celebrate` skip players whose `state.lastSweepAt` (set at `SweepService.luau:175`) is older than 120 s, and cap the gift at `ProgressRules.gift(highestUnlockedZone(state.profile.zones))` so a player never receives more than their own best zone is worth. (Keep the x2 buff for everyone; it is multiplicative, not a lump sum.)

### M3. A player whose profile is still locked plays a blank, never-saved profile for the whole session
- Files: `ProfileStore.luau:61-69` (`lockStaleSeconds = 180`, `loadLockTries = 6`, `lockRetrySeconds = 3`) and `:192-263` (the load gives up after about 15 s), `ProfileManager.luau:116-121` (then `offline()`), `ProfileStore.luau:390-394` ("the lock goes stale by itself").
- Exact scenario: server A crashes (or its release hit the DataStore throttle) and the player rejoins in under 3 minutes: they get `locked`, wait 15 s, then play the whole session on a fresh blank profile that is deliberately never written (correct for data safety). Nothing is lost, but they see "progress is not being saved", may play 30 minutes, and lose that 30 minutes. A child will not understand it.
- Fix: for `offlineReason` in {locked, busy, error}, keep a background retry (every 20 s, up to 200 s) that loads the real profile and swaps it in (`ProfileSchema.assign(live, loaded)` then `PlayerState.recompute` + `fullSync`), or, simpler and safer, `player:Kick("Your progress is closing on another server. Please rejoin in a minute.")` instead of letting them play on blank.

## MINOR

- m1. `SaveRetry.luau:28` `string.find(last, "403", 1, true)` matches any error text containing "403" (a request id, a key, a number). One such transient error stops the retries at once, so a load becomes `error` -> offline session (`ProfileStore.luau:241-243`) or a save is abandoned until the 15 s retry. Fix: match `"^403"`, `"HTTP 403"` or `"Studio access"` only.
- m2. `playSeconds` is added only at leave (`PlayerState.luau:371`). The goal "Island Regular" (`Goals.luau:126`, target 3,600 s) cannot become claimable during a session and the time is lost on a crash. Fix: add elapsed time every 60 s in the autosave tick (`PlayerState` Heartbeat) and reset `playSince`.
- m3. `SweepRules.RATE_SLACK = 0.8`, `BURST = 2` (`SweepRules.luau:13-14`, `:37`, `:42-57`) accepts one swing every 0.8 x interval, so a script gets a permanent +25% on the core loop over the honest client. Fix: `RATE_SLACK = 0.95` (burst 2 already absorbs jitter).
- m4. Memory: `GoalService.luau:46-52` recreates `announced[state.player]` for players that already fired `PlayerRemoving` (`PlayerState.all()` still lists them for the 2 s at `PlayerState.luau:376`; the 10 s timer lands in that window about 20% of leaves), so ~1 in 5 leavers leaves a permanent table plus a dead Player reference. Fix: make `PlayerState.all()` and `get()` skip `player.Parent == nil`, or check `state.player.Parent == Players` in `announceReady`. Every other per-player table I traced (Net limiters and warn map, Sweep/Sell/Purchase toast maps, `recs`, Helper owners, `gemPending`, `Profiles.known`) is cleaned on leave.
- m5. Perfect Dodge is free for anyone who waits in the hub: bombs skip hub players (`BurpService.luau:287`), so `director.hit` stays false while `landed > 0` (`BurpDirector.luau:417`), and the whole server gets the +10% for 3 minutes. Burp dodge goal stats are not farmable this way (hub players are excluded from `present`). Fix: count players outside the hub; if zero players are outside, skip the perfect buff.
- m6. `ClientReady` is sent exactly once (`client/Main.client.luau:109`). A dropped send leaves the player unready forever (no sweep, no sell, and B1 hits everyone). Fix: client resends every 3 s until the first `State` arrives (server side is idempotent and rate limited 1/s, burst 3).
- m7. No Lune tests for `Guard` or the `Net` limiter, nor for any service glue. I verified these by probe instead: `Buy("upgrade")` -> missing id; 3 args -> too many; `{}`/NaN/33-char id rejected; burst limiter allows exactly `burst` calls. Add `tests/guard.test.luau` with those cases so they stay true.
- m8. Zone purchases, tools and Spark perks rely on the 60 s autosave (`PurchaseService` has no `saveSoon`; only Daily, Goal, Set claim and Cool Down save early). A crash loses at most one minute, consistently (coins and item roll back together), so no duplication. Fix: `Profiles.saveSoon(player)` after zone / tool / sparkPerk purchases.
- m9. The starter sell radius (16 + 4 slack, `SellService.luau:25`) covers 34 beach cells with a Twig Broom (probe: nearest cell centre is 13.0 studs from a pad, reach 7). A beginner can sweep and sell without walking. Fine for the first minute, but widen the clear circle or drop the slack to 2 if the trip loop should matter early.

## Checked and found sound (so nobody re-audits it)

| Area | Verdict and evidence |
|---|---|
| Remote args | `RemoteDefs.luau:32-48`: every toServer remote takes only strings (max 16/32 chars) or one boolean; no numbers, vectors, tables, or positions. `Guard.validate` rejects extra, missing, wrong-type args (probe-confirmed). |
| Rate limits | `Net.luau:63-66` limits BEFORE validation, per remote per userId, buckets freed on leave (`:44-47`). |
| toClient remotes fired back | `Net.luau:41` attaches an empty listener, so a client cannot fill a server queue. No RemoteFunctions anywhere. |
| Handler crash | `Net.luau:72` wraps every handler in `pcall`; warns are throttled and contain no client text (no log injection). |
| Infinite coins | Every `addCoins` caller is server-computed: sell (`SellService.luau:122`), finds (`FindsService.luau:68`), gems (`:109`), party (`AshService.luau:160`), helper bots (`HelperService.luau:243`); `Wallet.earn` for daily and goals. None reads a client number. Bad numbers: `addCoins` ignores NaN and inf, `Economy.sellValue` and `findCoins` sanitize, `ProfileSchema.sanitize` clamps everything on load and `isValid` repairs before every save (`ProfileStore.luau:330-334`). |
| Free zones / items | `Pricing.priceOf` (`Pricing.luau:41-80`): known id, not owned, ring order, integer price, coins >= price, all re-checked in `PurchaseRules.buy` (`:139-160`). Probed ids `0x2`, `2.0`, ` 2`, `inf`, `nan`, `-1`, `1e999`, `__index`: only a legal zone number resolves to the normal price. |
| Double-spend races | Buy, Sell, Daily, Goal, ClaimSet and Cool Down contain no yield between check and spend (confirmed by reading each; `Profiles.update/grantOnce` run on a copy synchronously). Two taps cannot buy twice. |
| Daily once-only | `DailyService.luau:23-38`: server UTC day from `os.time()`, `DailyRules.plan` (lastDay) AND receipt `daily:<day>` written in the same save; `saveNow` after the claim; an old day can never replay because `day > lastDay` is required. |
| Goals / sets once-only | `GoalRules.claim` sets `goalsClaimed` in the same step as the payment (`GoalRules.luau:51`); sets likewise (`FindsService.luau:148`); both survive Cool Down. |
| Cool Down abuse | Atomic: `canCoolDown` is re-checked on the copy inside `Profiles.update` (`CoolDownService.luau:47-52`), a second tap fails because `runCoins` is 0, in-place assign keeps table identity, forced `saveNow`. Sparks are square-root of run coins and the bonus is capped at x10 (`StatsCalc.luau:53-59`). |
| Sell range | Server-side, 2D distance to a real pad, alive and ready, 0.25 s cooldown (`SellService.luau:61-122`). Only weakness is position trust (M1). |
| Gem pickup | Server polls at 5 Hz, only after landing, paid once (gem removed in the same step), highest-unlocked-zone value, capped 5e7. |
| Helper pay | Server-side from owner's unlocked zones only; golden cells excluded; paid to the owner; bodies capped at 60. |
| Zone lock | Sweep (`SweepRules.buildAllowed`), finds (via cleared cells), helpers (`HelperRules.allowedZones`), gems (`effectiveZone`) all honour `profile.zones`. |
| DataStore | One door (`Profiles.luau`), every call through `SaveRetry.run` (load, save, unlock). Session lock with stale takeover (`ProfileStore.luau:211-231`), save aborts as `lost` if the lock sid changed (`:358-364`), a failed load becomes a `locked` stand-in that can never be written (`:268-281`, `:303-309`), future/corrupt records are refused, `Serializable.check` before every write, UpdateAsync only, autosave staggered, `BindToClose` releases all profiles in parallel inside 25 s (`Profiles.luau:189-197`, `ProfileManager.shutdown`). Leave during load releases the lock (`ProfileManager.luau:101-111`). |

## Exploit attempts and results (what a malicious client sends)

1. `Buy` with oversize / non-string / missing / extra args -> rejected by Guard, one throttled warn.
2. `Buy("zone","5")` without zone 4 -> "Open Crater Rim first". `Buy("upgrade","power")` at max level -> "Maxed out!". Negative / NaN / huge ids -> unknown.
3. `ClaimDaily`, `ClaimGoal`, `ClaimSet`, `CoolDown` spam -> first one pays, rest see "already" or "not yet"; rate limit 1 to 4 per second anyway.
4. `Sweep` at 100 Hz -> limiter then token bucket; accepted rate about 1.25 x honest (m3).
5. `Sell` from across the island -> "Walk to the Trade Hut" (but see M1: a teleport passes).
6. Fire every toClient remote back -> swallowed.
7. Hostile character position (teleport, spin, fly) -> works (M1).
8. Join and never send `ClientReady` -> breaks party / perfect / buff expiry for others (B1).
9. Rapid server hop to duplicate rewards -> blocked by session lock and receipts (a hop only waits for the release, M3 describes the slow case).
Infinite coins, free zones, free tools, double daily/goal, and a server crash through remote input: none found.

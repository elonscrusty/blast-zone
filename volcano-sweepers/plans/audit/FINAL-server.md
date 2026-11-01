# FINAL audit: server + shared (last line of defence)

Area: `src/server/**`, `src/shared/**` except `Ui/` and `Client/`, and their tests. Read DESIGN, CONTRACTS, J1-J5 and
the J-fix handoff, then re-read the current code from scratch, without relying on the fixers' reports.
Proof: `stylua` clean, `lune run tests/run` = 523 passed / 0 failed, `rojo build` ok. Selene is not installed here, so it was not run.

## Scores after my fixes (honest, 1-10)

| # | Quality bar line | Score | The one thing still holding it below 9 |
|---|---|---|---|
| 1 | Core feel of sweeping | 8 | The server cone, rate limit (0.95 slack + burst 2) and own-cell rule are right and tested. The swing feel itself (puff, number, held tool) is only proven in code. Nobody has seen it on a phone. |
| 2 | Economy / progression pacing | 8 | The supply-aware sim hits every target within about 10% solo (sale 0:15, Push Broom 2:26, zone 2 5:50, zone 3 15:42, zone 4 33:58, zone 5 1h02, Cool Down 1h13 = 10 Sparks, Volcano Vac 3h15). But it is a sim of an ideal kid, not real thumbs. |
| 3 | Upgrade variety and clarity | 8 | Every upgrade reaches the server. Reach and arc now add cells. The Lava Mop comes about 4 minutes after zone 5 opens, so a kid in Lava Heart briefly has nothing new to buy. |
| 4 | Phone UI quality | 8 (server side) | Server toasts are short and kind. The layout is the client auditor's to judge. Landscape-only is a deliberate choice (left as is). |
| 5 | Co-op feel | 8 | Two friends used to earn about 1/3 of a solo kid's coins. Now it is about 2/3 (see fix 4), and Hot Springs comes 25% later instead of 34%. Sharing the island's starting ash is still a cost. |
| 6 | Volcano events fun / fairness | 8 | Now there is one ring, where the hit really counts. The hub is safe, Perfect Dodge needs someone outside, and gold is shared out per kid. Whether the server-made LinearVelocity bounce feels good on a phone is unproven. |
| 7 | Visual polish of the island | 7 | The build code is careful: piece-by-piece pcall and a fallback spawn. But the island has never been looked at. |
| 8 | Reliability (no errors, saves safe) | 8 | Save path verified again: offline stand-ins can never be written, the retry runs 8 x 20 s (outlives the 180 s stale lock) and stops, receipts, BindToClose. Every require path checked by script. String requires and the first boot still need one Studio run. |
| 9 | Security (server decides) | 9 | Every remote is strings or a boolean, rate limited, and re-checked. All positions go through MoveWatch. Small leftover: a speed hack can still move at 1.5x walk + 10 without being flagged. |
| 10 | First 5 minutes | 8 | Auto-Sweep is now ON for new players (walk into ash = sweep). First sale is at 0:15 and the first upgrade comes right after. It depends on the tutorial finger and the HUD being right on a real phone. |

## What I fixed (file:line, why)

1. `src/shared/Profile/ProfileSchema.luau:214`: default `settings.autoSweep = true`. DESIGN says Auto-Sweep is on by default, and the tutorial already adapts ("Walk into the ash!" when auto is on). A save that already holds a value keeps it. Tests: `tests/profile.test.luau:152,291,368` (default on, junk -> on, a saved `false` survives the round trip). The Settings toggle reads `view.settings.autoSweep`, which fullSync always sends, so it shows ON.
2. `src/server/Burp/BombVisuals.luau:58-72`: the server no longer builds its own `LavaRing` on landing. The ball still falls, and it is destroyed when it lands. The client draws the telegraph and the splash at `bomb.radius` (+ body radius, matching `hitTest`), so there is one ring and it marks exactly where a hit counts.
3. `src/server/Sweep/SweepService.luau:185-190`: `VSSweeping` is now set by comparing with the character's own attribute. Before, a kid who respawned while auto-sweeping kept extending the old timer, so the NEW body never got `VSSweeping = true`, and other players never saw that kid's tool swing again until they paused.
4. `src/shared/Sweep/ProgressRules.luau:345` (`PACE_SHARE_PER_EXTRA` 0.12 -> 0.45, so 2+ kids get the max 0.95 feed): with a friend, the regrow now answers the pair's full pace. pacing.test, 2 kids, first 40 min: per kid 54 -> 99 coins/s, ash 5.3 -> 6.4/s, median Hot Springs 21:00 -> 19:38 (solo 15:42). 4 kids: Hot Springs 18:42 -> 18:22. Solo and 16-kid numbers are unchanged. New test: `tests/progress_rules.test.luau` checks that `paceShare(2) == PACE_SHARE_MAX`.
5. `src/server/Burp/GeyserService.luau:poll`: the `order` id list was only compacted when the 60-gem cap was hit, so it grew forever on a long-running server. It is now cleared whenever no gems are lying around.
6. `src/server/World/World.luau:rescuePlayers`: after the server moves a body out of the volcano, it calls `MoveWatch.teleported`, so the movement check can never snap a rescued kid back inside.
7. Docs: `plans/handoffs/S3-burp-finds.md` item 9 was stale (it described the old velocity bounce and the server ring). `plans/NEXT-PIECES.md`: the server/shared rows are marked as done.

Checked and found correct (no change needed):
- Leftover 4 (Progress remote): the client now listens (`client/Hud/CleanBar.luau`: per-zone % of the zone you stand in). The server keeps sending it (<= 1/s, only when it changed).
- Leftover 5 (CullLogic.ashAhead): its fan is a superset of the server cone (it uses reach + 0.5 cell where the server uses + 0.25, and any cell within 1 cell where the server uses only your own cell). Auto-sweep can fire an empty swing but never misses ash the server would take.
- Leftover 8: `VSTool` / `VSSweeping` are spelled identically in PlayerState, SweepService and `client/Vfx/HeldTool.luau`.
- Leftover 9: a script resolved every `require("./...")` in src (0 bad) and every `require(Shared.X.Y)` in server and client (0 missing).
- Tags `VSSellPad`, `VSSellPrompt`, `VSGate` (attribute `ZoneId`, child `GatePrompt`), `VSSpawn` match between World and the services and client. Remote payload fields match `Types.luau` and the client readers.
- MoveWatch with honest play:
  - Spawn and respawn reset the track with 3 s of grace.
  - The bounce gives 2 s of grace (the jump lasts about 0.5 s).
  - The bank is about 6 s of walking, so a phone lag spike is paid for.
  - Bots don't collide, and pushes from other kids are slower than the allowed speed.
  - There are no seats and no slopes, and the server never moves a player except the rescue (now covered).
  - Snap-back needs 3 fresh strikes in 20 s or a jump of more than 120 studs.
- Profiles retry: it only retries for locked/busy/error, with each try spaced 20 s apart. It gives up after 8 tries. It copies the real save into the live table and never writes the stand-in. It releases a lock it took for a player who already left. No tight loops, and per-player tables are cleared.
- Exploit pass over all 11 toServer remotes, plus prompt firing, teleport, speed, deleting your own HRP or Humanoid, attribute spoofing and hub camping. Nothing pays without a server check.
  - Teleporting to the hut, a gate or a gem does nothing: the trusted spot follows at walking speed.

## For the other auditor (client area, not edited by me)
- `client/Core/Controls.luau:98,219` and `Tutorial.luau:523` fall back to `false` when `settings.autoSweep` is missing. Harmless (fullSync always sends settings), but `true` would match the new default.
- Helper bots follow the raw HumanoidRootPart, not MoveWatch (server, minor): a teleporter's bots sweep where the teleporter stands. The rate is still capped per bot per second, so it is no real gain. I left it as is.

## Please check on a real phone or in Studio Play (tap through)
1. Join: you stand on a teal pad by the hut, and ash is all around.
2. Walk into grey ash without touching anything. It should sweep by itself (AUTO is on).
3. Fill the bag, walk to the hut, tap SELL: coins fly up.
4. Buy one upgrade from MENU > Upgrades.
5. Walk to the Fern Forest gate, press the prompt: it opens once you have the coins.
6. Wait for a lava burp: one red ring, a ball falls, and if it hits you, you bounce (no death).
7. Walk around for 2 minutes with bad Wi-Fi: you are never pulled back.
8. Die or reset, then sweep again: friends see your tool swing.
9. Open Daily and claim it, then try again: "Come back tomorrow".
10. Leave, rejoin: coins and gates are still there.
11. With a friend: both sweep, and both get a party gift when a zone hits 25%.
12. Look at the island from the hut: no grey boxes floating, gates readable.

# Piece 02: Match flow (lobby, countdown, match, results)

**Goal:** One match from "FIGHT" to the results screen, plus the reward math.
**Read first:** build plan, `02-design.md` (match rules, rewards).

## You own
- `src/server/Systems/Match.luau`
- `src/shared/Config/Rewards.luau`, `src/shared/RewardCalc.luau` (pure)
- tests: `tests/reward_calc.test.luau`, `tests/match_rules.test.luau`
- pure helper `src/shared/MatchRules.luau` (placements, win check, bot count, countdown state)

## Build
1. **State machine** `Lobby -> Countdown -> Playing -> Results -> Lobby`. Everyone who joined the game is in the lobby; `QueueJoin` marks a player queued, `QueueLeave` unmarks. Start the 20 s wait once the first human queues; at the end of it (or when 16 humans are queued) go to a 5 s countdown. Send `QueueState` and `MatchState` as they change.
2. **Fill with bots.** `Bots.create(16 - humans)`. If `Bots` is missing, run with humans only (keep the match going; a single human alone just wins when the cap hits).
3. **Spawn.** Take spawn points from `Arena.getSpawnPoints()`, shuffle with a server random, load player characters there (`player:LoadCharacter()` or a custom spawn), register everyone with `Combat.register(fighter, loadout)` using the player's `Data` profile (hero, hero level, weapon levels; bots get a level 3 average loadout). Fire `FighterSpawned` for each. Freeze movement during the countdown.
4. **Play.** Fire `MatchPhase = "Playing"`. Track eliminations from `FighterEliminated`: place = alive count + 1 when someone falls. End when 1 fighter is left, or at the match cap (240 s): then rank survivors by HP.
5. **Results.** Compute the placements, then for each human: `RewardCalc` (cogs, trophies, hero xp, chest earned), apply with `Wallet.add` and `Data.update` (stats, hero xp, chests), send `Results`. Fire `MatchEnded`. After 15 s clean up (remove bots, unregister, reset), go back to `Lobby`.
6. A player who leaves mid-match counts as eliminated. Late joiners wait for the next match.
7. `Config/Rewards.luau` holds the placement tables from the design doc.

## Server checks
Queue remotes only work in `Lobby`/`Countdown`. Rewards are computed on the server from server-known placement and kills only. A player gets rewards once per match.

## Tests (Lune)
`RewardCalc` for every placement row (cogs, trophies; trophies floor at 0, no loss under 50), chest rule (top 3 or every 3rd match), hero xp formula. `MatchRules`: placement numbering, win detection, bot fill count, cap tiebreak by HP.

## Done when
Checks pass, contract (`Match.getPhase/getFighters/getAlive/isAlive`, Bus events) matches the plan, row 02 marked, handoff written.

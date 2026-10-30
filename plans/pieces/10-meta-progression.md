# Piece 10: Meta progression (upgrades, chests, dailies, leaderboard)

**Goal:** The server side of "what I do between matches". Pairs with piece 09 (the screens).
**Read first:** build plan, `02-design.md` (upgrade costs, chests, dailies, leaderboard).

## You own
- `src/server/Systems/Meta.luau`
- `src/shared/Config/Chests.luau` (the odds table, read by piece 09 too), `src/shared/Config/Dailies.luau`, `src/shared/Config/HeroShop.luau` (unlock costs: Spark 400, Bruno 1200 cogs)
- `src/shared/UpgradeMath.luau`, `src/shared/ChestRoll.luau`, `src/shared/DailyRules.luau` (all pure)
- tests: `tests/upgrade_math.test.luau`, `tests/chest_roll.test.luau`, `tests/daily_rules.test.luau`

## Build
1. **`Menu` RemoteFunction** via `Net.onInvoke("Menu", handler)`: `handler(player, cmd, args)`. Whitelist the commands from the build plan (`selectHero`, `upgradeWeapon`, `upgradeHero`, `unlockHero`, `openChest`, `claimDaily`, `claimLogin`, `getLeaderboard`, `finishTutorial`). Anything else: `{ok=false, reason="bad command"}`. Check `args` types and ranges for every command. Do nothing while the player is inside a running match.
2. **Upgrades.** `UpgradeMath.weaponCost(level)` = round(50 x 1.5^(level-1) to the nearest 5), `heroCost(level)` = round(100 x 1.55^(level-1) to the nearest 5); max level 10 (both). `Wallet.trySpend` first, then `Data.update` to raise the level; if the update fails, refund. Never go past level 10.
3. **Heroes.** `selectHero` only if unlocked. `unlockHero` costs cogs (Spark 400, Bruno 1200) or completes with hero cards (10 cards = unlock, from chests).
4. **Chests.** `openChest`: needs `chests > 0` (decrement atomically in `Data.update`), roll with `ChestRoll.roll(Config.Chests, rng)` (odds from the design: cogs 40-80 55%, cogs 150-250 20%, gems 3-8 15%, hero card 8%, emote 2% (emote = just a saved string for now)), apply the reward, reply with what was won. Odds live only in `Config/Chests.luau` and the UI shows them before opening.
5. **Dailies.** Three tasks (play 2 matches, 3 kills, open 1 chest), 10 points each; ladder at 10/20/30 points = 60 cogs / 3 gems / 1 chest. Reset at UTC midnight (`DailyRules.dayNumber(os.time())`). `claimDaily` only when the task is done and not claimed. Login streak of 7 days (cogs 50, 50, 75, 75, 100, 100, chest); missing a day resets to 1. Listen to `MatchEnded` to advance matches and kills, and count chest opens here.
6. **Leaderboard.** `OrderedDataStore` `Trophies`; write after each match (only when trophies changed), through `SaveRetry`, never more than once per 10 s per player. `getLeaderboard` returns the top 20 plus the caller's rank, cached for 60 s on the server. Names via `Players:GetNameFromUserIdAsync` with a pcall and a cache. In Studio without API access: return an empty list.
7. **First-time gift** is piece 01's job. `finishTutorial` sets `tutorialDone`.

## Server checks
Every command re-validates ownership, costs, max levels and cooldowns. Rolls on the server only. Rate limit comes from `Net` (5/s). Never trust any number from the client; commands carry ids and indexes only.

## Tests (Lune)
`UpgradeMath` equals the design table. `ChestRoll`: distribution within tolerance, rewards in range, hero card path. `DailyRules`: day rollover across UTC midnight, streak continue/reset, ladder thresholds, claim only once.

## Done when
Checks pass, command list and replies match what piece 09 expects (`{ok: boolean, reason: string?, ...}`), row 10 marked, handoff written.

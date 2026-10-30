# Piece 09: Lobby and menu screens

**Goal:** Everything outside the match: pick a bot, upgrade, open a chest, press FIGHT, see the results.
**Read first:** build plan, `02-design.md` (UI design, upgrade costs, chests, dailies).

## You own
- `src/client/Controllers/Menu.luau`
- `src/client/Screens/Lobby.luau`, `Heroes.luau`, `Upgrades.luau`, `Chests.luau`, `Dailies.luau`, `Leaderboard.luau`, `Results.luau`, `Tutorial.luau`
- `src/client/Ui/Widgets.luau` (buttons, panels, currency chip, progress bar; uses `Ui/Theme` from piece 08, and falls back to its own constants if that file is not there yet)
- `src/shared/MenuMath.luau` (pure): upgrade cost lookup, "can afford" text, progress fractions, daily ladder positions, odds text
- tests: `tests/menu_math.test.luau`

## Build
1. **Lobby.** Landscape. Top bar: cogs, gems, trophies (3 chips, tap = nothing for now, no "+"). Left: tabs Bots, Upgrades, Chests, Dailies, Top. Right: the selected bot standing on a platform (a ViewportFrame with the same Part-built rig; slowly turning) and a big **FIGHT** button (mid-right, at least 96 px tall). Pressing it sends `QueueJoin`; the button becomes **Waiting n/16** with a cancel (`QueueLeave`) from `QueueState`. Hide the lobby when `MatchState.phase` is `Playing`.
2. **Bots (heroes).** Strip of 3 bots with HP, locked ones show cost and a lock. Tap to select (`Menu("selectHero")`) or unlock (`Menu("unlockHero")`).
3. **Upgrades.** The 3 weapons and the bot as cards: level, now -> next numbers, cost, **Upgrade** button (disabled with a clear reason when too poor). Calls `Menu("upgradeWeapon")` / `("upgradeHero")`. Costs come from `MenuMath` (the same formula the server uses; the server has the final say).
4. **Chests.** Shows the unopened count and a big **Open** button. Tap the small ⓘ to see the odds table **before** opening (from `Config/Loot` style data in `Config/Chests.luau` that piece 10 owns; read it, do not copy numbers by hand). The reveal is a short pop animation.
5. **Dailies.** 3 tasks with progress bars, the 10 / 20 / 30 point ladder, **Claim** buttons, the login streak row, a "refreshes in" timer.
6. **Top.** The leaderboard list (`Menu("getLeaderboard")`), your row highlighted.
7. **Results** (`Results` remote): placement big, kills, cogs flying into the cog chip, trophies +/-, hero XP bar, chest earned; a **Again** button (sends `QueueJoin`) and **Lobby**.
8. **Tutorial.** First time only (`tutorialDone` false): arrows pointing at Upgrades, "Upgrade your blaster!", then FIGHT. Ends with `Menu("finishTutorial")`.
9. Everything reads the profile from `ProfileUpdate`. Every button is at least 56 px high with 12 px gaps; text min 18 px.

## Server checks
The client never changes numbers. Every tap is a `Menu` command; show the reason string the server returns when `ok` is false.

## Tests (Lune)
`MenuMath`: cost table equals the design table (50/75/110/170/255/380/570/855/1280 for weapons, 100/155/240/370/575/895/1385/2150/3330 for heroes), afford text, odds text adds to 100%, ladder positions.

## Done when
Checks pass, every control has a touch target, row 09 marked, handoff written.

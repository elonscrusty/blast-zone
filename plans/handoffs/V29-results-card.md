# V29 Richer results card (video 3 gap #29)
- Done: the results card now has a line for what you did: things broken, crates opened, powers picked. Place, kills, time and reward were already there.
- Pure rules in `src/shared/Results/MatchTally.luau` (counts, cap of 999, junk refused, the words, a client-side clean read). Words are ours and plain.
- Server `src/server/Results/TallySystem.luau` owns the book and clears it when a match starts. Only the server counts; the client never reports anything.
- Counted where it really happens: `BreakSystem` (a street prop breaks, breaker gets it), `ContainerSystem` (a crate breaks), `UpgradeSystem` (a power pick passed every check).
- `MatchSystem.sendResults` adds the asking player's own counts to `you.tally`. Nobody sees another player's counts. The payload field is optional, so old payloads still work.
- Client `ResultsClientSystem` shows one line under the pills ("12 things broken · 3 crates opened"). Hidden when nothing happened. Placeholder look: Claude Design places it.
- Tested: `tests/match_tally.test.luau` (13: counting, junk, cap, copy, reset, words, clean read, the three call sites, the results merge). Lune 1383 pass, StyLua clean, rojo build ok. Selene runs in CI. Not run in Roblox.
- Layout: row positions live in `src/client/Match/ResultsLayout.luau` (pure numbers the screen is built from); the extras line is at least 14 px tall on every phone shape from 360x640 to 1914x604, tested in pixels.
- Left: a count for bot kills vs player kills, "time alive" is already survivedSeconds. Hero posing in 3D is the existing winner pose.

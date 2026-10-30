# 41 Whole-match tests

1. `tests/match_sim.luau` is a pretend server: every pure piece is real (match flow, roster, damage door, health, ammo, shields, run XP, upgrades, zone, crates, orbs, bot brains + auto-fill, arena walls, coins, stats, daily) and wired like the `*System` files, in start order.
2. `tests/full_match.test.luau` plays whole matches with it (8 seeds, all 3 maps, 1/2/8 people, leavers, two matches in a row) and checks rows, kills, rewards, coins, and that reset leaves nothing behind.
3. Fixed: an idle friend in the lobby blocked bot fill forever (`BotRoster.lobbyHumans`, BotSystem counts queued people).
4. Fixed: a draw counted as a win on stats and daily (`RewardGranted` now has a 5th arg `won`; `StatsRules.matchDelta(place, won?)`).
5. Fixed: leaving on the results screen said "left the match" and could lose coins (MatchController pays first, no forfeit).
6. Fixed: a two-person match opened in Final pressure (count rule waits until someone is out).
7. Bodies are points and shots are flat lines; slides, shells, found guns and anti-cheat are not simulated.
8. If a piece changes its *System wiring, mirror it in `match_sim.luau` so the test keeps telling the truth.
9. Checks: stylua OK, `lune run tests/run` 629 passed, rojo build OK. selene runs in CI. luau-lsp not run here.
10. Idea: a solo player waits 10 s for bots again before every match; filling at once on Play again would be faster.

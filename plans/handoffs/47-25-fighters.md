# 47 25 fighters (video 3 gap 9)
- Done: a match fills to 25 (you + up to 24 labeled bots). `Config.Match` target and max are 25.
- One size knob: `ARENA_SCALE` at the top of `src/shared/Config.luau`. It stretches the map (`Layout.scaleSpec`), the safe circle and the match clock (`Config.zoneAt`). 1 = old 220 studs, 1.3 = 286 studs (default, about 4 minutes), 1.6 = 352 studs.
- Spawns and crates: `Layout.compile(spec, opts)` tops up to 25 spawn points and 36 crate points on free, reachable floor (farthest-point spread, no random). All 6 maps, all 3 sizes tested. Spawns stay at least 36 studs apart (bots' calm-start sight is 30).
- Bots: 24 different names; each thinks a little less often in a crowd (`BotTuning.thinkGap`, 0.1 s up to 0.16 s); one shared list of fighters per 0.05 s (`BotSystem` others cache). Walking and shooting are still every frame.
- Orbs: `Pickups.maxActive` 60 to 80. Crates: `Arena.containerSpots` 12 to 36.
- Max Players: `default.project.json` now asks for 25 (Players service). Steps for the Studio setting are in `plans/RELEASE-CHECKLIST.md` (it is a setting carter checks; Claude cannot change it).
- Tests: `tests/crowd.test.luau` (every map x 3 sizes: spawns, crates, circle, names, think gap, place file). Zone tests now use `Config.zoneAt(1)`; arena tests build the way the game does.
- Not tested in Studio. Left: bots build their rigs in parallel at the start (24 at once); watch that all are standing when the countdown ends (PERF-CHECKLIST step 1). Squads, ranked and modes may want their own fill numbers.

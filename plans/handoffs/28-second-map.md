# 28 Second map + map rotation
- Done: 3 new map tries (D "Neon Plaza", E "Market Hall", F "Canal Docks") in `src/server/Arena/LayoutD/E/F.luau`, same spec format as A-C. carter's pick plays as map 2; the others stay as extra maps.
- Rotation: `Config.Arena.rotation = { "C", "D" }` (first = carter's map 1). `MapRotation.luau` (pure) loops the list. `ArenaSystem` builds map 1 at start and, as each match goes Countdown -> Spawning (before spawns are read), moves to the next map. `ArenaSystem.setChooser(fn)` lets map voting name the winner (nil = keep rotating).
- Nothing else had to change: spawns, crate spots, shot blockers and roof fade are all read from tags fresh every match, and the client fade resets when the old arena parts go.
- `Workspace.Arena` now has `LayoutName` and `NextLayoutName` attributes (for a "next map" line on results or lobby later).
- Tests: `tests/arena.test.luau` runs every arena check on D, E, F too (spawns safe and apart, crates reachable, zone rings, doors, camping seats); `tests/map_rotation.test.luau` covers order, loop, one map, bad ids and the config.
- Look: built by the shared `ArenaBuilder`, so the city art / Neon Night pass styles every map at once.
- Preview: https://claude.ai/artifact/1F1hAyoqpyA4dzELczTv5z (3D, game view, night/sunset/day). `tools/arena-export` writes all six maps as JSON.
- Not tested: the swap in Studio (needs a full match). selene could not fetch the Roblox API here; CI runs it.
- Left: show "next map" in results/lobby (piece 05/10 files), maybe add A/B/E/F to the rotation after carter plays.

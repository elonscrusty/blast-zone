# S1 handoff: world builder

1. Files: `src/shared/WorldPlan.luau` (pure plan), `tests/world_plan.test.luau`, `src/server/World/{World,WorldUtil,Ground,Volcano,Hub,Gates,Decor}.luau`, `src/server/World/DecorKinds/{Beach,Forest,Springs,Rim,Heart}.luau`.
2. `require(...World.World).init()` builds `workspace.VSWorld` (about 1800 Parts, all Anchored) and the lighting; decor finishes in a background task (`World.decorReady()`).
3. API: `hubPosition`, `spawnPositions`, `sellPadPositions()`, `gatePosition(zoneId)` (zones 2..5), `ventPositions` (10, zones 3..5), `applyLighting()`, `partCount()`. Positions are plain maths, readable before `init()`.
4. Tags: `VSSpawn` (8 SpawnLocations, Neutral, Duration 0), `VSSellPad` (3 pads), `VSSellPrompt` is on the ProximityPrompt (key F, gamepad X) on the counter, `VSGate` is the glowing floor plate (attribute `ZoneId`, child prompt `GatePrompt`).
5. Walking happens on one invisible disc at y = 0 (radius 252.5); the coloured zone ground is non-colliding. Volcano core, hut walls, pillars, trunks, spires and an 80 stud outer wall ring collide. Everything else does not.
6. `VSWorld` has a number attribute `Glow` (0..1, about 7 s cycle) for the client to match the crater glow.
7. Layout is deterministic from `Config.World.seed`; the hub layout assumes `hub.clearRadius = 22`. The world assumes `groundY = 0` (warns otherwise).
8. Smoke/steam uses the built-in `rbxasset://textures/particles/smoke_main.dds`; if it ever fails the puffs just do not show. No other texture, sound or asset id is used.
9. Not done: no per-player gate lock visuals (gates always look open), no animated waves, no Studio check of the look (no Play tests by rule). carter, please look at the hut sign, awning tilt and the crater when you play.
10. Checks run: stylua clean for these files, `lune run tests/run` green, rojo build ok. Selene is not installed here, so it was not run.

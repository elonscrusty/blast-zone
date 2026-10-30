# 04 Graybox arena + roof/interior visibility
- Done: carter picked layout C "Arcade Row" (`Config.Arena.layout = "C"`). A "Crossroads Park" and B "Offset Avenues" are built too: change that one string to swap map.
- Code: `src/server/Arena/` (Layout = data to boxes + shot-block test, LayoutA/B/C, ArenaBuilder, ArenaSystem builds `Workspace.Arena` at start). `src/client/Arena/` (Visibility = pure fade maths, InteriorVisibilitySystem).
- Tags (Config.Tags): `BlocksShots` walls/cover/trees/blocks/map edge, `LowCover` fences + pond (walk blocked, shots pass), `Roof` (CanCollide/CanQuery off), `Interior` floors, `ArenaSpawn` pads (11 for C), `ContainerSpot` (14, bottom face on the floor), `FinalZoneRegion` (disc at the zone centre, radius = last stage).
- Zone: arena is built around `Config.Zone` centre (0,0). Every ring (156, 105, 68, 38, 14, 4) is checked to be walkable with no cut-off pocket.
- Fade: roofs fade when you are inside, walls and blocks on the camera line go see-through (client only, `LocalTransparencyModifier`). People inside a room you are not in are hidden from you. Numbers in `Config.Arena.fade`.
- Tests: `tests/arena.test.luau` (all 3 layouts: spawns free/apart/no instant shot at weapon range, crates reachable, zone rings, any one door shut still leaves a way, no covered spot sees > 80%, fade rules).
- Not tested: Roblox-side parts and fade (only when carter plays). selene and luau-analyze did not run here; CI runs selene.
- Left: art pass (Phase 4), second building on the map if play shows the arcade is too dominant, `Tier` on crate spots if 07 wants fixed rarity.

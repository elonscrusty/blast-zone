# SL Night traffic (video 3 gap #2, cars only)
- carter picked "A Cars" from the 3 street-life ideas (B robot people and C sky lights are not built). Glowing hover-cars loop the roads. Show only: no collision, no damage, nothing aims at them.
- Server: `src/server/Traffic/TrafficSystem.luau` works out the free road stretches at Spawning (after the map is built), sends `TrafficState` to all, clears at Waiting. Late joiners ask with `TrafficRequest` (1/s, no arguments). Switch: `Config.Features.traffic`.
- Pure rules: `src/shared/Traffic/TrafficPlan.luau`. Two lanes per road (drive on the right), cut wherever a solid sits on the lane, so cars never go through parked cars, crates or walls. Same seed gives the same cars. Numbers: `Config.Traffic`.
- Client: `src/client/Traffic/TrafficClientSystem.luau`. Up to 14 cars (8 on phones), 5 plain parts each, no lights or particles. Cars fade at the ends of a stretch and around you (7-13 studs) so one never hides a fight. A shot near a road makes its cars brake for 2s, then speed up.
- North-south lanes ride 2.4 studs higher, so cars never share a spot at a crossing.
- Tests: `tests/traffic.test.luau` (12 tests: all 6 maps at all 3 crowd sizes have stretches clear of every solid, lanes, cap, loop, fades, braking, remotes). 1243 pass, StyLua clean, rojo builds. selene could not run here (no API dump); CI runs it.
- Not tested in Studio (rules: no Play tests): how the car shapes look, the fade near you, glow colours. Placeholder look; the city art thread can restyle. Cars are not synced between players (each phone runs its own), which does not matter for a show.
- Left: car sound (needs a real audio id from carter), B robot people and C sky lights if carter wants them later.

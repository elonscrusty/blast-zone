# S3 handoff: volcano burps + finds (server)

1. Files: `server/Burp/{BurpService,BombVisuals,GeyserService}`, `server/Finds/FindsService`, `shared/Burp/BurpGlue` (all pure rules), tests `burp_glue` + `finds_service`.
2. Main must call `FindsService.init()` then `BurpService.init()` (BurpService starts BombVisuals + GeyserService itself).
3. BurpService steps the director every 0.25 s; hit = bounce (velocity + Freefall), drop 0.2 x (1 - armor) of the pack, 2.5 s shield, hub is safe, nobody dies.
4. Sky goes red by tweening Lighting.Ambient/OutdoorAmbient/Atmosphere.Color (restored after). Camera shake is the client's job (Burp remote).
5. `GeyserGems` remote has two shapes: a list `{ {x,z,id,rarity} }` (new gems) and `{ removed = id }` (picked/expired). C1 must handle both.
6. Golden cells: server flags them in the grid, but no remote tells clients WHICH cells are golden (RemoteDefs has none). C1/S2 need a way (e.g. send indices in AshDelta or a new remote).
7. Gems pay `coins x sellMult`; coins use the highest zone the player unlocked (<= the gem's zone), so locked zones cannot be cashed early.
8. Sets: finishing a set toasts; `ClaimSet` marks `setsClaimed`, recomputes stats, `Profiles.saveSoon`.
9. Not verifiable without Play tests: server-set `AssemblyLinearVelocity` on a client-owned character, `Humanoid:ChangeState` from the server, tween look. Carter should watch a bomb hit once.
10. Later (not v1): bomb scorch marks, ragdoll, per-bomb sounds.

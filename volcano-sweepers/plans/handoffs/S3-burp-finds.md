# S3 handoff: volcano burps + finds (server)

1. Files: `server/Burp/{BurpService,BombVisuals,GeyserService}`, `server/Finds/FindsService`, `shared/Burp/BurpGlue` (all pure rules), tests `burp_glue` + `finds_service`.
2. Main must call `FindsService.init()` then `BurpService.init()` (BurpService starts BombVisuals + GeyserService itself).
3. BurpService steps the director every 0.1 s with MoveWatch (trusted) positions; hit = bounce (a 0.15 s server LinearVelocity + 2 s MoveWatch grace), drop 0.2 x (1 - armor) of the pack, 2.5 s shield, hub is safe, nobody dies. Perfect Dodge only counts players who were outside when the bombs fell (+25% for 2 min).
4. Sky goes red by tweening Lighting.Ambient/OutdoorAmbient/Atmosphere.Color (restored after). Camera shake is the client's job (Burp remote).
5. `GeyserGems` remote has two shapes: a list `{ {x,z,id,rarity} }` (new gems) and `{ removed = id }` (picked/expired). C1 must handle both.
6. Golden cells: the `Golden` remote sends `{ cells, endsAt }` (after `AshService.flushNow`, so gold never sits on bare ground). The count is shared out per player (BurpGlue.goldenShare) into each player's best zone.
7. Gems pay `coins x sellMult`; coins use the highest zone the player unlocked (<= the gem's zone), so locked zones cannot be cashed early.
8. Sets: finishing a set toasts; `ClaimSet` marks `setsClaimed`, recomputes stats, `Profiles.saveSoon`.
9. Not verifiable without Play tests: the server-made LinearVelocity bounce on a client-owned character, the tween look. Since the final audit the server only drops the lava ball; the ground ring and splash are the client's (`Vfx.lavaTelegraph`/`lavaImpact` at `bomb.radius`). Carter should watch a bomb hit once.
10. Later (not v1): bomb scorch marks, ragdoll, per-bomb sounds.

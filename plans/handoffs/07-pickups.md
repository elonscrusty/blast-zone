# 07 Supply containers, XP orbs, run XP
- Done: containers in 3 loot tiers (blue common, violet rare, magenta epic; health 40/60/90, orbs 2/3/5, rolled 50/35/15 or forced by a `Tier` attribute on the `ContainerSpot` marker). Orbs, claims, elimination XP, `XpState`.
- Code: `src/server/Pickups/` (ContainerSystem, PickupSystem, RunXpSystem, pure ContainerRules + PickupRules), `src/client/Pickups/PickupFxSystem`. Numbers: `Config.Containers`, `Config.Pickups`.
- Piece 03: when a shot hits a part, call `require(...Pickups.ContainerSystem).damage(hitPart, amount, sourceId, matchId)`; true = it was a container, stop the shot (also for explosion splash).
- Piece 04: `ContainerSpot` marker = a Part whose bottom face is on the floor. Containers are built at Spawning, removed at Resetting/Waiting.
- Piece 08: listen to `RunXp.LevelUp` in Core. Piece 09: bots collect with `PickupSystem.tryClaim(botId, botPosition, pickupId)`.
- Rules: orb claim = first valid claim; the breaker gets 1.5 s first dibs (`Config.Pickups.reserveSeconds`). Orbs last 25 s. Client leans orbs toward you (look only) and asks by itself, no button.
- Tests: `lune run tests/run` (tiers, hits to break, break once, tier roll, claim rules, XP pacing). Nothing was run in Studio.
- Not tested: the Roblox-side code (parts, remotes, timing). It only gets exercised when carter plays.
- Left: heal pickup (`Config.Features.healPickup` stays off: health is piece 03's). With 4 crates + 1 kill a player gets ~2 offers, 5 crates ~3; tune `Config.Containers.tiers` or `Config.Arena.containerSpots` after playing.

# 47 Street that breaks (gap list #1 and #10; carter picked A "Chunk Burst")
- Done: cars, dumpsters, planters, benches and barriers have health. Bullets and mortar blasts hurt them; at zero the prop bursts. The solid stops being solid (walk and shoot through), its art parts leave the street, a scorch mark and 6 small blocks stay, and every client throws chunky blocks in the prop's own colours.
- Server decides: `src/server/Props/BreakSystem.luau` (health, combat-phase check, source alive, restore). Pure rules: `src/shared/Breakables/BreakRules.luau`. Hooks: `Firing.luau` (bullets, next to `ContainerLink`) and `Shells.luau` (blast loop, line check ignores the prop itself).
- Art link: `ArtKit.Spec.owner` / `Plan.owner` (set in StreetArt and ParkArt around each breakable); ArtBuilder writes it as attribute `ArtOwner`. Masses (buildings) never break, even `block-*`.
- Reset: props come back at the next Spawning (same arena) or with the new arena. Art parts are parked, not destroyed.
- Client: `src/client/Props/BreakFxSystem.luau` (flying chunks, cap `Config.Breakables.fly.maxLiveChunks`) and pure `ChunkFlight.luau`. Remote `PropBroken` (toClient). No UI, no sound ids yet.
- Numbers: `Config.Breakables` (health, chunks, rubble, fly). All placeholders until carter plays.
- Tests: `tests/breakables.test.luau` (9 cases, incl. every map: each breakable prop has art that names it). stylua, lune (901 pass), rojo build clean. Selene cannot fetch its Roblox API here, so CI runs it.
- Not tested until carter plays: how many shots a car takes, chunk look on phone, bots still think a broken prop blocks their view (they use the layout), blast damage numbers.
- Left: sound cue for a burst (audio ids empty anyway), bodies that stay (gap #7), rubble kicked up by slide, a big-blast look (follows Power Picks).

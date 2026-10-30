# 42 Loot and heal packs (from carter's "make it like video 3" ask; carter picked bundle A)
- Done: heal packs lie on the street, you walk over one to carry it (3 at most), and use it on a button (+30 health, never over max). Found guns also lie on the street all match (they never run out; the old crate-drop guns still expire). A fighter who falls drops one pack. Bots use a pack when under half health.
- Numbers: `Config.Loot` (heal amount, carry max, cooldown, how many packs and guns, where they go). All placeholders until carter plays.
- Where loot goes: open floor 7 studs from a crate marker (`ContainerSpot`), checked with a raycast; works on every map, no new art. 4 guns and 6 packs per match, at least 18 studs apart.
- Server decides: `src/server/Loot/HealPacks.luau` (carry count, every use check) and `LootSystem.luau` (spawns, death drop, bot use). Packs reuse `PickupSystem` (new `spawnHeal`, same first-claim rules as orbs; a full bag leaves the pack). Floor guns use `WeaponDrops.spawn(..., persistent=true)`.
- Client: `UseHealRequest` (key F, pad D-pad Down, touch HEAL button above the move stick), `LootState` back with the count. `src/client/Loot/` keeps the count; placeholder look only (green block with a plus, floating text). Claude Design owns the real look.
- Pure maths + tests: `src/shared/Loot/LootRules.luau`, `tests/loot.test.luau` (11 cases). stylua, lune (878 pass) and rojo build are clean; selene cannot fetch its Roblox std here, so CI runs it.
- Not tested until carter plays: raycast spots on each map, how many packs feel right, the touch button spot, bots walking over packs by chance (they do not hunt for them).
- Left: heal sound ids and a heal effect (audio/effects pieces), bots that walk to packs and guns on purpose, a HUD slot for the count on keyboard (touch button shows it today).
- Next bundles carter did not pick yet: B Power Picks (big level-up powers), C Fast Feet (sprint, hop low walls, 2 slides). Preview: previews/video3-systems/.

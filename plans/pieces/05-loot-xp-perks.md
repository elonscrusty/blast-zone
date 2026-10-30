# Piece 05: Loot, XP and perk cards

**Goal:** Why a run feels different every time: chests, pick-ups, levels, 3-card picks.
**Read first:** build plan, `02-design.md` (loot table, XP table, perk table).

## You own
- `src/server/Systems/Loot.luau`
- `src/shared/Config/Loot.luau`, `src/shared/Config/Perks.luau` (perk ids use the constants from `Config/Weapons.luau`, piece 04; if it is not there yet, define the id list in `Config/Perks.luau` and say so in your handoff)
- `src/shared/XpTable.luau`, `src/shared/PerkDraw.luau`, `src/shared/LootRoll.luau` (all pure)
- tests: `tests/xp_table.test.luau`, `tests/perk_draw.test.luau`, `tests/loot_roll.test.luau`

## Build
1. **Toy Chests.** At `MatchPhase = Playing`, place 14 chests at `Arena.getChestSpots()` (a pink Part with a lid, bobs a little). A fighter within 5 studs (10 with Magnet) opens it once. Roll with `LootRoll.roll(table, rng)` (weights from the design: Fix-it Kit 35, Bubble 20, XP burst 25, Quick reload 10, Cogs 10). Apply with `Combat.addKits / addShield / addReloadBoost`, `awardXp`, and for cogs `Wallet.add` only for humans (cap +15 per chest, max 3 chest cogs per match per player).
2. **Kill drops.** On `FighterEliminated`: killer gets 50 XP; 30% chance to drop a kit pick-up where the victim fell. Smashed blocks (Arena) give 5 XP: listen for a Bus event or an Attribute the Arena sets (agree with piece 03 through the coordinator if needed; default: skip block XP and note it in the handoff).
3. **XP and levels.** `XpTable`: 40, 60, 85, 115, 150, 190 to reach levels 2..7, max level 7. `awardXp` fires `XpGained`, sets Attributes `Level`, `Xp` on the model, and on a level-up fires `LevelUp`, sends `LevelUp` + `Banner{kind="LEVEL UP"}`.
4. **Perk cards.** On a level-up of a human: `PerkDraw.draw(owned, rng)` returns 3 distinct perk ids that are not already at 3 stacks. Send `PerkOffer{options, expiresAt = now + 8}`. `PickPerk(i)`: only valid with an open offer, `i` an integer 1..3, once. If the 8 s run out, pick randomly. Then `Combat.setPerks(id, perks)`. Several level-ups queue; one offer at a time.
5. **Bots** pick a random card instantly (same code path with no remote).
6. Clean up everything at `MatchPhase = Results`.

## Server checks
The client only sends an index. Offers, rolls, XP amounts and chest opens are all decided here. A chest can be opened only once, by someone alive and close enough (distance checked on the server).

## Tests (Lune)
`XpTable` thresholds and max level; `PerkDraw`: always 3 distinct (or fewer when the pool is small), never a maxed perk, deterministic with a seeded rng; `LootRoll`: distribution within tolerance over 10,000 rolls, weights of 0 never come up.

## Done when
Checks pass, contract (`Loot.getXp/awardXp`, Bus events, remotes) matches, row 05 marked, handoff written.

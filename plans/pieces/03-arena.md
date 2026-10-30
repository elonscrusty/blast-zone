# Piece 03: Arena (map, smashable blocks, Blast Waves, Ghost Pokes)

**Goal:** The play area and the twist: the floor that blows up.
**Read first:** build plan, `02-design.md` (art direction, blast schedule, ghost poke).

## You own
- `src/server/Systems/Arena.luau`
- `src/shared/Config/Themes.luau` (3 palettes: Toy Room, Junkyard Rumble, Sky Blocks), `src/shared/Config/Blast.luau`
- `src/shared/BlastPlan.luau` (pure), `src/shared/ArenaGrid.luau` (pure)
- tests: `tests/blast_plan.test.luau`, `tests/arena_grid.test.luau`

## Build
1. **Theme config.** Colors, materials, prop list per theme. `Arena.build("ToyRoom")` is the default until carter picks (carter's choice lands in `Config/Themes.luau` as `DEFAULT`). All three themes must build from the same layout, only paint and props change.
2. **Layout** (300 x 300, placeholder Parts only): floor, outer walls, 5x5 grid lines drawn lightly on the floor, 16 spawn points spread around the edge/ring, 14 chest spots, cover (block towers, crates, a few cars, a couple of walls with gaps), 6 red barrels. Plain Parts, anchored, named, in a `Workspace.Arena` folder. Leave room for later art.
3. **Smashable props.** Blocks and crates have an `Hp` attribute. `Arena.splash(pos, radius, dmg)` damages props in range; at 0 they break (a few flying Parts, then removed). A barrel that breaks makes an explosion (radius 10, 200 damage to fighters through `Combat.applyDamage`, chains into nearby barrels after 0.15 s).
4. **Grid API.** `ArenaGrid` pure math: `cellAt(x, z)`, `cellCenter`, neighbors. Wrapped by `Arena.cellAt/cellCenter/isBlasted`.
5. **Blast Waves.** `BlastPlan.make(seed, grid, schedule)` (pure) returns the waves from the design (0:40 / 1:15 / 1:45 / 2:15 / 2:40 / 3:05 Sudden Death). Rules: never blast a cell twice; start from the edges (pick a hidden safe cell at match start, blast the cells farthest from it first); the safe cell and its ring are last; Sudden Death leaves only the safe cell. Server: at each wave send `BlastWarn` (8 s), then `BlastBoom`, turn the cells into pits (dark, glowing red), fire the Bus `BlastBoom`, send `Explosion`. Every 0.25 s, anyone standing in a pit takes 8% max HP per second via `Combat.applyDamage(id, amount, nil, "blast")`. Banner `CIRCLE CLOSING`-style text = `Banner{kind="BLAST INCOMING"}` and `SUDDEN DEATH`.
6. **Ghost Pokes.** `GhostPoke(Vector3)`: only for fighters that are out of the match (`Match.isAlive` false and the player is in the match), once per 25 s, point must be inside the map and not in a pit. Send `GhostWarn`, 3 s later hit everything within radius 12 for 300 via `Combat.applyDamage(id, 300, ghostId, "ghost")` and `Arena.splash`.
7. `Arena.startMatch()` resets props, pits and plans; listens to `MatchPhase`.

## Server checks
Ghost poke: type Vector3 and finite, player is out, cooldown, inside map. Seeds and safe cell chosen on the server. Clients only draw.

## Tests (Lune)
`BlastPlan`: every cell appears at most once, wave sizes match the schedule, safe cell never blasted before Sudden Death, same seed = same plan, 100 random seeds all pass. `ArenaGrid`: cell mapping at edges and corners.

## Done when
Checks pass, contract (`Arena.*`) matches, row 03 marked, handoff written.

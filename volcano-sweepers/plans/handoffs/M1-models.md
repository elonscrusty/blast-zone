# M1 handoff: sweeper tool, helper bot and cart models

1. Files (all new): `src/server/World/Models/{ModelKit,ToolSpecs,BotSpecs,CartSpecs,ModelBuilder,SweeperTools,HelperBots,SweeperCart}.luau`, `tests/models.test.luau`. No existing file was changed except one line in `tests/run.luau` and `plans/NEXT-PIECES.md`.
2. Pure part lists (`*Specs`, `ModelKit`) have no Roblox types, so Lune tests them. `ModelBuilder` turns a list into a Model (non-colliding, welded to a see-through `Root` PrimaryPart).
3. `SweeperTools.build(id, look)` gives the hand part (grip = origin, hangs along -Y, -Z forward). `SweeperTools.buildBack(id, look)` gives the backpack/wings/tanks in torso space (+Z behind), or nil. `look` = "A" Toy, "B" Steel, "C" Candy.
4. `HelperBots.build(look, level)`: A Bumble (hover + propeller), B Roller (wheels + brush), C Ember (mini volcano). Level 0..15 only changes the trim colour (bronze/silver/gold/volcano); part count never changes. `spinParts(model)` and `bobParts(model)` list parts to animate.
5. `SweeperCart.build(look)`: ride-on cart, front brush (`Spin*` parts), back bin. `SweeperCart.setFill(model, 0..1)` grows the ash heap. `SweeperCart.seatOffset` is where a rider sits (marker part `SeatSpot`; the main thread decides about a real Seat).
6. Part counts (phone-light): tools 11-22 in hand + up to 8 on the back, bots 23-25, cart 43. Caps are enforced by tests (26 / 10 / 34 / 52).
7. Everything is Parts, Cylinders and Balls; no asset ids, no wedges, no textures, no particles, no lights, no sounds.
8. Not wired: nothing requires these modules yet. `Config.World`, `World/*` (other than `Models/`) and `Ash/*` are untouched. The existing `HeldToolLogic` blueprints still drive the held tools until the main thread switches over.
9. Not checked in Studio (rule: no Play tests). Please look at tool tilt in the hand, wing placement and the bot hover height when you play. The 3D preview page is the only look check so far.
10. Checks: `stylua --check`, `lune run tests/run` (548 pass), `rojo build` ok, `luau-analyze` clean on the pure files. Selene could not download its Roblox API dump here, so CI runs it first.

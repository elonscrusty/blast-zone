# L1 handoff: big volcano and landmarks

1. New files only, all in `src/server/World/Models/`: `Parts.luau` (pure part list + helpers), `BigVolcano`, `LavaPool`, `HotSpring`, `Lighthouse` (pure, one `spec(variant, scale)` each), `ModelBuild.luau` (list -> real Parts), `Landmarks.luau` (the one door). Tests: `tests/landmarks.test.luau`. Nothing existing was edited except one line in `tests/run.luau`.
2. Wire-up (main thread): `require(script.Parent.Models.Landmarks).build("volcano", folder, CFrame.new(x, groundY, z), { variant = "A", scale = 1.4 })`. Kinds: `volcano`, `lava`, `spring`, `lighthouse`. Returns `{ model, glow, beam }` or nil for an unknown kind.
3. Looks: A toy, B low-poly rock, C wild. `Landmarks.defaultVariant` picks the default (carter's pick); the other two stay as skins.
4. Base sizes (studs): volcano 90 radius and about 150 tall (C reaches about 200), lava pool and hot spring about 18 radius, lighthouse about 72 tall and 10 radius. `scale` multiplies everything, so use it for a bigger map.
5. Origin is the middle of the footprint ON the ground (y = 0 is the ground). Pass the ground level in the CFrame.
6. Volcano has an invisible solid core `ConeCollision` (radius about 90) so players cannot walk into it. Pools and springs have a few solid rocks; the rest does not collide. Lava and water are decor only: no scripts, no touch.
7. `refs.glow` = parts to pulse (lava, water, lamp). `refs.beam` = lighthouse beam Model; its pivot is the lamp, spin with `beam:PivotTo(beam:GetPivot() * CFrame.Angles(0, dt, 0))`.
8. Part counts per look: volcano 58-85, pool 26-59, spring 25-36, lighthouse 48-55; one full look about 200 parts. Tests keep each under budget.
9. Not done: nothing is placed in the world yet (main thread places them), no Studio look (no Play tests by rule), selene could not run here (no Roblox API download), CI will run it.
10. Preview and PNGs: project files `previews/landmarks/`. Regenerate the preview data with `lune run tools/dump_models <out.json>`.

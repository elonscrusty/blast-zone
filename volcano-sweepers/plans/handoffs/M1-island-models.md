# M1 handoff: island buildings and props

1. Files: `src/server/World/Models/{Kit,Styles,Registry,Build,TradeHut,Gate,Camp,Palm,Rocks,Mushroom,Spire,Sign}.luau`, `tests/island_models.test.luau`, `tools/dump_models.luau`. Nothing else was touched (no Config, World/*, Ash/*).
2. Every model is PURE DATA first: `Registry.spec("Palm", { style = "toy", v = 12 })` returns part specs (numbers + strings, no Roblox types). Lune tests run on those.
3. `Build.into(parent, spec, CFrame, scale?)` is the only Roblox code: makes a Model of anchored Parts via `WorldUtil.part`. `Build.anchorPoint(spec, name, origin)` gives a Vector3 for prompts and signs.
4. Looks (param `style`): `toy` Toy Pop (A), `tiki` Tiki Wood (B), `basalt` Basalt Glow (C). carter picked A (`toy`, the default); B and C stay as skins. Unknown style falls back to `toy`.
5. Params: `v` 1..1000 (same v = same model), `text` (signs), `accent` + `ground` (gates take the zone colours). Model space: ground at y=0, front faces -Z.
6. Wiring hints: hut part `Counter` + anchor `sell` (sell prompt), anchor `sign`; gate part `GatePlate` (tag VSGate + prompt), part `Beam` + anchor `sign` (price sign); signs have part `Board` + anchor `board`; palm anchor `top`; camp anchor `fire`.
7. Budgets (all looks, tests enforce): hut 48, gate 32, camp 34, palm 13, rocks 9, mushroom 10, spire 15, sign 9 parts. Only a few parts collide (hut counter + walls, gate pillars, trunk foot); nothing solid in the gate's walk-through.
8. Not done: not placed in the world (main thread wires it, e.g. swap Hub hut / Gates / DecorKinds to `Build.into`), no animation (flames and beacons are plain Neon parts), no sounds.
9. Preview + clips + PNGs: project files `previews/island-props/`. The 3D link was made from the same specs via `lune run tools/dump_models out.json`.
10. Checks: stylua clean, `lune run tests/run` green (550), rojo build ok. selene could not fetch its Roblox std here: pure files linted with the plain luau std, `Build.luau` not linted (CI will).

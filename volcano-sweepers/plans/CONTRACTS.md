# Contracts (read after DESIGN.md)

## Conventions (every file)
- `--!strict`, Luau, tabs, StyLua clean (`stylua src tests` from `volcano-sweepers/`), Selene clean (config in this folder).
- Run from `volcano-sweepers/`: `lune run tests/run`, `stylua --check src tests`, `rojo build default.project.json -o VolcanoSweepers.rbxl`.
- Pure logic goes in `src/shared/**` and must run in Lune: NO `game`, `Instance`, `Color3`, `Vector3`, `task`, `os.time` at module level. Colours are hex strings ("#RRGGBB"). Time/rng/waiting are passed in. Tests for every pure module in `tests/<name>.test.luau`, one `require` line added to `tests/run.luau`.
- Roblox glue (server/client) is thin: it calls the pure modules. Keep it small, typed, leak-free (disconnect connections, destroy instances on player leave).
- Relative requires in shared pure code: `require("./Other")` / `require("../Rng")`. Server/client glue: `local Shared = ReplicatedStorage:WaitForChild("Shared")` then `require(Shared.Catalog.Tools)`.
- The server decides everything. A remote carries intent only. The Sweep remote carries NO position or direction: the server uses the character's own position and facing.
- Never invent Robux ids, prices in Robux, or sound ids. No DataStore calls outside the Profile glue. Saves go through `Shared/SaveRetry.luau`.
- Every owned file listed in NEXT-PIECES.md; do not edit files you do not own (ask in your final report instead).
- Ids are fixed lowercase snake_case strings (below). Zone ids are numbers 1..5 in code, strings "1".."5" as table keys in saved data.

## Fixed ids
- Tools: `twig_broom`, `push_broom`, `leaf_blower`, `dust_vac`, `turbo_vac`, `lava_mop`, `dragon_vac`, `volcano_vac`
- Upgrades: `power`, `speed`, `reach`, `backpack`, `walk`, `sell`, `luck`, `armor`, `sweetspot`, `lucky_coins`
- Helper bot upgrade kind in Buy: `helper` (buy another bot), `helperUp` (level up all bots)
- Buy kinds: `upgrade` | `tool` | `zone` | `helper` | `helperUp` | `sparkPerk`
- Buffs: `party`, `perfect`, `golden`
- Rarities: `common`, `uncommon`, `rare`, `legendary`

## Ash model (shared/Ash)
- Grid of square cells (Config.World.cellSize) over the island rings, only cells whose centre lies inside zone 5 inner..zone 1 outer, and outside the hub clear circle, exist. Compact index 1..N (row-major over the bounding square, skipping non-island cells) — deterministic from Config, so server and client compute the identical layout; only LEVELS travel the network.
- Level per cell 0..9 (units). Snapshot = string of N chars ('0'..'9'). Delta = flat `{idx, level, idx, level, ...}`.
- Server is the only writer. Client mirrors levels and renders.

## Economy rules (shared/Rules)
- Backpack: `carried` units + `carriedValue` coins-before-multipliers (units x zone value when swept). Selling pays `carriedValue x derived.sellMult`, then clears the pack.
- Hit by a lava bomb: lose `carried x 0.2 x (1 - armor)` units (value scales down proportionally), ash goes back onto the ground nearby.
- Server clamps everything: coins never negative, numbers finite, caps on levels.

## Who owns what (see NEXT-PIECES.md) and what each exports
Wave 1 (pure, parallel, no dependencies on each other except Config/Types/Rng):
- **R1 rules**: `Catalog/{Tools,Upgrades,Zones,Finds,Helpers,SparkPerks,Goals,Daily}.luau`, `Rules/{StatsCalc,Economy,Pricing}.luau`, tests incl. `tests/pacing.test.luau` (a simulated idealised player must hit the pacing targets in DESIGN/PACING below).
- **R2 sims**: `Ash/{Layout,AshGrid}.luau`, `Burp/{BurpTuning,BurpDirector}.luau`, `Finds/FindRoller.luau` (takes the find list as a parameter).
- **R3 saving**: `Profile/*` adapted from the copied Blast Zone code to the Types.Profile shape (`ProfileSchema.default()`, `sanitize`, `migrate`), session lock + retry via fake datastore tests. Plus `Player/Purchases.luau`? NO — purchases are wave 2 (needs R1).

Wave 2 (Roblox glue, parallel, read the real wave 1 code):
S1 world, S2 ash/sweep/sell services, S3 burp/finds, S4 player/purchases/helpers/daily/goals/cooldown/bootstrap, C1 client core, C2 UI kit + HUD, C3/C4 panels.

## PACING targets (R1 must tune numbers so a simulated player meets these; tests enforce +-30%)
Simulated player: sweeps continuously, walks 12 s round trip per sell, buys the best affordable upgrade.
- First sale before 25 s of play. First upgrade bought before 45 s.
- Push Broom owned by ~2:30. Zone 2 gate by ~6:00. Leaf Blower by ~9:00. Zone 3 by ~16:00.
- Zone 4 by ~35:00. Zone 5 by ~70:00. Volcano Vacuum is a 3 h+ goal. First Cool Down offered at ~90 min.
- Every upgrade line has >= 12 levels; the cheapest upgrade level costs <= 20 coins; nothing is a trap
  (higher level always strictly helps). Costs are integers. Show clear numbers ("+8% reach").
- Sparks: first Cool Down gives about 5–15 Sparks; each Spark = +5% coins, additive, soft cap by curve (never > x10 total).

## State sync
Server holds `PlayerState` per player (Profile + live fields). On change it sends only changed top-level keys via `State`. The client store merges them. The client never computes authority: it displays `view.derived`, prices come from shared Catalog functions, but the server re-validates every `Buy`.

## Testing without Studio
No Play tests. The proof is: `lune run tests/run` green (pure logic incl. fake-datastore save tests, balance sim, determinism, security cases), stylua clean, rojo builds, selene clean (CI). The judges read the code.

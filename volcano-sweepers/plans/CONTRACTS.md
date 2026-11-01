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
- Grid of square cells (Config.World.cellSize) over the island rings, only cells whose centre lies inside zone 5 inner..zone 1 outer, and outside the hub clear circle and the Trade Post clear circles (`WorldPlan.postSpots`, radius `Config.World.tradePost.clearRadius`), exist. About 12,000 cells on the big island. Compact index 1..N (row-major over the bounding square, skipping non-island cells) — deterministic from Config, so server and client compute the identical layout; only LEVELS travel the network.
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
Simulated player: sweeps continuously, walks to the NEAREST sell pad (Trade Hut or the zone's Trade Post) and back
(tests/island_sim measures the walk on the real layout: about 50-75 studs one way), buys the best affordable upgrade.
Big island (Nov 2026) results, median of 3 islands: Push Broom 2:02, zone 2 5:42, Leaf Blower 9:05, zone 3 12:19,
zone 4 28:25, zone 5 52:34, Cool Down 1h22m (now offered at 7M run coins, was 3M), Volcano Vacuum 3h15m.
Crowds (first 40 min, ash swept per kid vs solo): 2 kids 1.1x, 4 kids 0.9x, 16 kids 0.76x, 24 kids 0.78x.
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

---
# WAVE 2 CROSS-PIECE APIS (fixed now; implement exactly these names)

Wave 1 is DONE and real: read the code, not just this file. `src/shared/{Catalog,Rules,Ash,Burp,Finds,Profile}`,
`src/server/Profile/Profiles.luau`, and **`src/server/Player/PlayerState.luau` (already written, S4 may extend but NOT rename)**.
Unit note: `FindRoller.roll(luck)` wants a *bonus fraction* (derived.luck - 1), derived.luck is a multiplier.
BurpDirector: call `:reportHit(userId, now)` right after handling each "land" event, step at least every 0.5 s, field is `untilAt` not `until`.

## Server (ServerScriptService.Server). `src/server/Main.server.luau` (owned by S4) boots in this order:
Net.init → Profiles.init → PlayerState.init → World.init → AshService.init → SweepService.init → SellService.init →
FindsService.init → BurpService.init → PurchaseService.init → HelperService.init → DailyService.init → GoalService.init → CoolDownService.init.
Each service module exports `init()` and is wrapped in pcall by Main so one broken service never stops the rest.

| Module (owner) | Exports others may call |
|---|---|
| `World/World.luau` (S1) | `World.init()` builds EVERYTHING in workspace under folder `VSWorld` (ground rings, volcano, hub, Trade Hut, gates, decor, lava, spawn, invisible bounds) and sets Lighting/Atmosphere/Sky/Bloom/ColorCorrection. `World.hubPosition: Vector3`, `World.spawnPositions`, `World.sellPadPositions(): {Vector3}` (hut pads + Trade Post pads), `World.gatePosition(zoneId)`, `World.ventPositions` |
| tags set by S1 | CollectionService tags: `VSSellPad` (parts, near the hut AND one on each Trade Post in zones 2..5), `VSSellPrompt` (ProximityPrompt on the hut counter and on each Trade Post counter: SELL), `VSGate` (part, attribute `ZoneId` number, child ProximityPrompt `GatePrompt`), `VSSpawn` (SpawnLocation) |
| `Ash/AshService.luau` (S2) | `AshService.grid` (the shared AshGrid), `AshService.init()`, `AshService.dropAround(x,z,units)` (lost backpack ash back on the ground), `AshService.zoneAt(x,z)`; replicates AshSnapshot on ClientReady and AshDelta batches (~10 Hz, chunks <= 400 pairs, only to ready players); slow regrow loop scaled by player count (half of it lands 32-90 studs around the players, `ProgressRules.regrowNear`; the bare ground around the players also feeds the adaptive budget, `ProgressRules.nearClean`); Progress remote (changed fractions, <= 1/s); milestone parties: at 25/50/75/100% of each zone and whole island fires `Party`, sets buff `party` via PlayerState.setBuff for 60 s x buffTime, gifts coins, tracks "already celebrated" so one zone does not repeat until it dips below the previous milestone by 10%; PlayerState.setClean(total). |
| `Sweep/SweepService.luau` (S2) | `Sweep` remote handler (server-only facts: HRP position + LookVector flattened, rate limit by derived.interval x 0.8, alive, ready, allowed zones from profile.zones, capacity), calls `grid:sweep`, `PlayerState.addCarried`, stats (ashSwept, cleared), calls `FindsService.onCleared(player, zoneId, clearedCount)`, fires `SweepFx` to other ready players within 160 studs, Toast throttled when backpack full. Golden cells x5 handled by the grid. |
| `Sweep/SellService.luau` (S2) | `Sell` remote + `VSSellPrompt`: must be within Config.World.sellRange of any `World.sellPadPositions()`; `Economy.sellValue`, `PlayerState.takeCarried/addCoins/addStat(unitsSold,sellCount)`, fires `Sold`; stat `sellCount`. |
| `Finds/FindsService.luau` (S3) | `FindsService.onCleared(player, zoneId, clearedCount)` (rolls FindRoller per cleared cell, pays coins via PlayerState.addCoins, updates profile.finds, stat findsTotal, `FindFound` remote, claim-able sets), `FindsService.grantGeyserGem(player, coins)`. Also the `ClaimSet` remote (set complete → set reward flagged in profile.setsClaimed, PlayerState.recompute). |
| `Burp/BurpService.luau` (S3) | runs BurpDirector with live player positions, fires `Burp`, `Bombs`, applies rain/golden via AshService.grid, lava hit: bounce (apply a velocity impulse to HRP, short ragdoll-free stagger), `PlayerState.dropCarried(frac = 0.2 x (1 - armor))` + `AshService.dropAround`, `BurpHit` remote, stats burpHits / burpDodged, perfect buff via PlayerState.setBuff, geysers: spawn gem parts, server proximity pickup (<= 6 studs, polled at 5 Hz), pays `FindsService.grantGeyserGem`, `GeyserGems` remote. Visual lava bombs are server Parts (fall from sky, explode puff). The hub is a safe zone. |
| `Player/PurchaseService.luau` (S4) | `Buy` / `EquipTool` handlers using `Pricing.priceOf`/`reason`, validates kind/id, spends via PlayerState.spendCoins (or Sparks for sparkPerk), applies the change to the profile, `PlayerState.recompute`, `PlayerState.touch`, Toast. Also connects `VSGate` prompt Triggered → buy that zone (or Toast why not). `SetSetting`, `TutorialDone`. |
| `Helpers/HelperService.luau` (S4) | spawns/despawns bot Models (Parts only, cute round bodies with eyes, Neon accents) following the owner, sweeping with `AshService.grid` on a 1 s tick, depositing coins DIRECTLY to the owner (never to backpack) at reduced rate per Catalog/Helpers; max bots visible per server capped (<= 60); cleans up on leave. |
| `Player/DailyService.luau`, `GoalService.luau`, `CoolDownService.luau` (S4) | `ClaimDaily` (UTC day from os.time()//86400, streak logic, Profiles.grantOnce with Profiles.dailyKey(day)), `ClaimGoal` (stat >= target, once), `CoolDown` (Economy.canCoolDown → Economy.coolDownReset → replace profile fields IN PLACE, clear backpack, recompute, fullSync, `CoolDownDone` remote, force a save). |

## Client (StarterPlayerScripts.Client). `src/client/Main.client.luau` (owned by C1) requires modules in order and wraps each in pcall.
| Module (owner) | Exports others may call |
|---|---|
| `Core/Store.luau` (C1) | `Store.get(key)`, `Store.view()` (live table), `Store.subscribe(key, fn(value, old)) -> disconnect` (also calls once now if value exists), `Store.ready: boolean`, `Store.onReady(fn)`; merges `State` remote payloads. |
| `Core/Net.luau` (C1) | `Net.send(name, ...)` (RemoteEvent FireServer with name check), `Net.on(name, fn)` |
| `Core/Controls.luau` (C1) | `Controls.setSweepHeld(bool)`, `Controls.sweepHeld()`, `Controls.requestSell()`, `Controls.autoSweepActive()`; keyboard: hold MouseButton1 or E to sweep, F to sell; gamepad R2/ButtonR2 sweep, ButtonX sell; the HUD sweep button calls setSweepHeld. Sends `Sweep` at the derived interval while held (server also enforces). Auto-sweep setting: sweeps while the character moves and ash is within reach. |
| `Ash/AshRenderer.luau` (C1) | builds the client-side ash cells from `Ash/Layout` (NOT replicated parts: client-created, parented to a folder in workspace, anchored, CanCollide/CanQuery/CanTouch off, shaded by zone ash tint, height by level, hidden at 0 to reveal the ground), applies AshSnapshot/AshDelta, only updates cells near the camera for speed (distance culling, batching ≤ 600 updates/frame), small scale tween on change. Exposes `AshRenderer.levelAt(i)`. |
| `Vfx/Vfx.luau` (C1) | `Vfx.floatText(worldPos, text, kind)`, `Vfx.puff(worldPos, hexColor, amount)`, `Vfx.coinBurst(count)` (coins fly from screen centre to the coin counter: C2 provides `Hud.coinTargetPosition(): UDim2?`), `Vfx.shake(strength, duration)`, `Vfx.fireworks(worldPos)`, `Vfx.lavaTelegraph(bomb)`, `Vfx.lavaImpact(x,z,radius)`, `Vfx.screenTint(colorHex, alpha, seconds)`; hooks the remotes `SweepFx, Sold, Burp, Bombs, BurpHit, Party, FindFound, CoolDownDone, GeyserGems` for world-space effects only. UI reactions (toasts, banners) are done by C2 from the same remotes via `Core/Net.on`. |
| `Core/Sfx.luau` (C1) | `Sfx.play(name)` (silent when `Config.Audio.ids[name]` is nil) and `Sfx.music()`. |
| `Core/Haptics.luau` (C1) | `Haptics.tap(strength)` guarded by settings.vibrate |
| `Ui/Theme.luau`, `Ui/Components.luau`, `Ui/PanelHost.luau`, `Hud/*.luau` (C2) | Theme tokens; Components: `Button`, `IconButton`, `Panel`, `Card`, `Pill`, `Bar`, `Label`, `Toggle`, `Tabs`, `ScrollList`, `Pips`, `CostButton` (shows price, greys + shakes when too expensive), `Badge`; `PanelHost.register(def)` where `def = { id: string, title: string, icon: string, order: number, build: (parent: Frame, ctx) -> (() -> ())? }` (build returns an optional cleanup/refresh), `PanelHost.open(id)`, `PanelHost.close()`, `PanelHost.toggle(id)`, `PanelHost.isOpen()`; `Hud.init()`. Panels live in `Panels/<Name>.luau` (C3, C4) each `return def` and are required by `Panels/init`-style loader in Main (C1 requires every ModuleScript under client/Panels in a pcall). |

## UI rules for every client UI file
- Only Theme tokens for colour/size/font; no stray hex or magic numbers. UIScale from Theme.scale(). Touch targets >= 44 px at scale 1. Text readable at 360x640 portrait and 800x360 landscape. TextScaled with UITextSizeConstraint min/max. Respect `GuiService:GetGuiInset()` and safe area (ScreenGui.ScreenInsets = DeviceSafeInsets, IgnoreGuiInset = true for full-screen). One DisplayOrder table in Theme (HUD 10, Toasts 30, Panels 20, Banner 25, Overlay 40).
- Every interactive thing has a visible pressed state (tween), and nothing is a dead end: every panel has a big close button; Escape/B closes.
- Kid-friendly copy: short words, no jargon. Numbers formatted with `Theme.fmt(n)` (1.2K, 3.4M, ...).

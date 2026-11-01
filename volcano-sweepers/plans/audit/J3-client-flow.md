# J3 audit: client integration and Roblox API correctness

Judge: J3. Lens: `src/client/**` against the Rojo tree, `src/shared/**`, `RemoteDefs` and what the server really sends.
Method: read every client module on the main path (Main, Core/*, Ash, Vfx, Hud/*, Ui/*, Panels/Shared, Settings, Tools, Book/Goals badge code), compared every server `Net.fire*` call with its client handler, ran `lune run tests/run` (465 passed, 0 failed), and counted ash cells with a Lune script against the real `Layout`. No Studio, so anything that only a Play test can show is listed at the end as "not verifiable".
Read-only: nothing under `src/` or `tests/` was changed.

## Verdict

BLOCKERS: none found. Nothing on the join -> ClientReady -> snapshot -> sweep -> sell path throws, and every server payload matches its client handler.
MAJOR: 4 (no number pops on your own sweep, no held tool or swing, E key shared by sweep and gate prompts, tutorial advances on a button press not on ash collected).
MINOR: 9.

## Verified OK (how I confirmed it)

| Area | Result | Evidence |
|---|---|---|
| Rojo paths | `script.Parent` of Main is the folder `StarterPlayerScripts.Client`; `Core`, `Ash`, `Vfx`, `Ui`, `Hud`, `Panels` are its Folder children; `Shared` is `ReplicatedStorage.Shared` | `default.project.json:30-38` (`$path: src/client`, no `init.*` files anywhere: `find src -name 'init*'` empty). Same mapping as the parent Blast Zone game that carter has played. |
| Load order | Store, Net, Sfx, Haptics, Controls (pulls AshRenderer, Vfx, CameraFx lazily by pcall), PanelHost, every Panels module (each registers on require), `Hud.init`, Tutorial, then `ClientReady` last, so every handler exists before the server answers | `Main.client.luau:53-112`; no require cycles (Bridge is lazy, Hud <-> Vfx is lazy) |
| String requires | `require("./X")` and `require("../X")` are used in the parent repo already (`src/shared/Chest/ChestRules.luau:10`) | grep |
| Remote shapes | State, AshSnapshot, AshDelta, Golden, SweepFx, Sold, Toast, Burp, Bombs, BurpHit, Party, FindFound, CoolDownDone, GeyserGems: every field the client reads is a field the server sends (Types.luau:60-90 vs `Vfx.luau:980-1240`, `AshRenderer.luau:277-350`, `Hud.luau:204`, `BurpBanner.luau:223`) | read both sides |
| Client -> server | Sweep, Sell, Buy, EquipTool, CoolDown, ClaimDaily, ClaimGoal, ClaimSet, SetSetting, TutorialDone, ClientReady: arg counts and types match `RemoteDefs` schemas (`Buy` with `""` id for helper kinds passes `string` kind) | `grep Net.send / Bridge.send` vs `RemoteDefs.luau:144-160` |
| Store merge | Whole-key replace, deep-equal skip, `Store.ready` flips before other `onReady` waiters, `subscribe` replays once | `StoreLogic.luau:108-243`, `Store.luau:366-374` |
| AshRenderer | Properties set before `Parent` (`:213-220`), parts pooled (`POOL_MAX 700`), 600 cells and 4 ms per frame, 100 shrink anims max, `anims[i]=nil` during traversal is legal, golden expiry uses `GetServerTimeNow` and the server sends server time (`BurpService.luau:309`) | read; `CullLogic` has 318 lines of tests |
| Controls | Hold sources (ui, mouse, E, R2), focus loss clears, drift-free interval, never faster than `minInterval`, backpack full gate, auto-sweep needs floor + ash in the same fan geometry as the server (`CullLogic.ashAhead`), no position sent | `Controls.luau:109-285` |
| CameraFx | `BindToRenderStep` at Camera+1, offset only (never accumulates because the default camera rebuilds CFrame from its own state each frame), respects `settings.shake` | `CameraFx.luau:124` |
| Haptics | Only `HapticService` on Gamepad1 (there is no phone vibration API); the file says so and the Settings row is honest about it | `Haptics.luau:1-5` |
| ScreenGuis | All guis `ResetOnSpawn=false`; main ones use `Components.screen` (`IgnoreGuiInset` + `ScreenInsets`, pcall-wrapped); HUD offsets by `GetGuiInset()` | `Components.luau:206-235`, `Theme.luau:197` |
| APIs | Every `Enum.*`, `:Method(` and property name used in `src/client` is real (grepped the full unique set); no `Instance.new(class, parent)`; no unguarded `view.x.y` indexing in panels | grep |
| Trust | Client sends intent only; Sweep has no position; prices/dots are display only; `TutorialDone` and `SetSetting` are validated server side | `PurchaseRules.luau`, `Guard.luau` |
| Leaks | Every panel returns a cleanup that calls `live.destroy()`/`binding.destroy()` and disconnects its own connections; module-level connections are singletons | `grep` on all 9 panels |

## MAJOR

### M1. Your own sweep never pops a number (core loop moment 1 is incomplete)
- Where: `src/client/Core/Controls.luau:176-207` (`feedback` does sound, haptic, camera nudge, puff only) and `:284`. `Vfx.floatText` is only called from the Sold, BurpHit and FindFound handlers (`Vfx.luau:1047-1059, 1149, 1185-1196`). The server never echoes your own sweep (`SweepService.luau:122-128` sends SweepFx to others only). `Backpack.luau:78-100` only changes the bar.
- DESIGN says: "Every swing must feel good (puff, camera nudge, tick sound, '+5' float text, ground revealed)".
- Failing scenario: a 7-year-old holds SWEEP. The cells shrink about 150 ms later (server round trip plus the 10 Hz AshDelta), the bar creeps up, but no "+3" ever flies out of the broom. The first 3 seconds, which carter said must be satisfying, are quiet.
- Fix: in `Vfx.luau` (it already owns `floatText`), `Store.subscribe("carried", function(v, old) ... end)`. When `v > old`, add `v - old` to a pending total and remember `Controls.lastSweepPoint` (set in `feedback`: `x, z`). Flush every 0.15 s: `Vfx.floatText(Vector3.new(x, GROUND_Y + 3, z), "+" .. StoreLogic.formatNumber(total), "ash")`. Every 5th flush use the coin value instead (`delta(carriedValue) * derived.sellMult`, kind "coin"). Cap at 6 floaters per second (the pool has 24).

### M2. There is no held tool and no swing animation anywhere
- Where: `grep -rniE "Handle|Motor6D|Weld|Animator|LoadAnimation|AnimationTrack" src` finds only `Helpers/BotModel.luau` (bots). `NEXT-PIECES.md` C1 never listed it, and no handoff mentions it.
- DESIGN says tools "must look and feel different: held model built from Parts, different puff colour, different sound hook". Only the puff colour is done (`Controls.luau:201-204`, `Vfx.luau:1018-1022`).
- Failing scenario: the player buys a Dragon Vac for a huge sum, equips it, and the avatar still stands with empty hands and does not move when sweeping. Friends see nothing either. Tool tiers have no visual payoff, which also hurts "upgrade clarity" and "co-op feel".
- Fix: new module `src/server/Player/HeldTool.luau` (server, so friends see it): on `CharacterAdded` and on `PlayerState` key `tool` change, build a small Model from Parts (colour from `Tools.byId[id].color`, length from `reach`, extra Neon bit for the trait), weld to `RightHand` (R15) or `Right Arm` (R6) with a `Weld` whose `C0` is the rest pose, name it `VSHeld`, destroy the old one. Client side (own and others via SweepFx): in `Controls.swept` and the SweepFx handler, tween that Weld's `C0` by a 40 degree arc and back in 0.12 s. Add it to `Main.server.luau` BOOT_ORDER after `PurchaseService`. Because it is just Parts it needs no asset ids.

### M3. Desktop: E is both "sweep" and the gate ProximityPrompt key, and the prompt needs a 0.4 s hold
- Where: `src/server/World/Gates.luau:134-141` creates `GatePrompt` with `HoldDuration = 0.4`, `MaxActivationDistance = 16` and no `KeyboardKeyCode`, so Roblox uses E. `Controls.luau:121-124, 140` also binds E (hold) to sweep. The hub prompt avoids it with F (`Hub.luau:194`) but gates were missed. Gamepad: same collision on ButtonX (default `GamepadKeyCode`) vs Controls sell (`Controls.luau:131`).
- Failing scenario: a desktop player holds E to sweep within 16 studs of any gate. Gates sit at the ring edges, right next to the ash. After 0.4 s the prompt fires `PurchaseService.onGateTriggered`: with enough coins the zone is bought without the player choosing to, otherwise "Collect N more coins..." toasts appear again and again (1.5 s throttle, `PurchaseService.luau:62-66`). While the prompt is on screen it also marks E as processed, so a later E press does not start sweeping.
- Fix: `Gates.luau` after line 140: `prompt.KeyboardKeyCode = Enum.KeyCode.G` and `prompt.GamepadKeyCode = Enum.KeyCode.ButtonY`. (Phones are unaffected; they tap the prompt.)

### M4. First 5 minutes: the tutorial advances on a button press, not on ash collected, and AUTO is off for new players
- Where: `Tutorial.luau:251-256` moves to stage "wait" on the first `Controls.swept`, which fires for every swing sent, even with no ash in reach (`Controls.luau:275-284`: manual sweep sends without checking `ashNear`). Stage "wait" hides all text (`:211-215`) until the pack is half full. `ProfileSchema.luau:214` defaults `autoSweep = false`, while `Economy.luau:43` (the fresh table used by Cool Down) says `true`. Nothing in Tutorial mentions AUTO.
- Failing scenario: a child spawns 18 studs from the hub centre (`WorldPlan.luau:178`), taps SWEEP once while facing the wrong way, the "Hold SWEEP!" bubble disappears, and for the next minute there is no hint at all. Holding a button with one thumb while steering with the other is the hardest thing for the youngest players, and the one-tap fix (AUTO) is never pointed at.
- Fix: (a) advance sweep -> wait only when `Store.get("carried") > 0` (subscribe to `carried`); (b) while stage is "sweep" and `AshRenderer.ashAhead(...)` is false for 3 s, show "Walk to the grey ash!" with the existing Beam to the nearest cell (`Layout.cellsInRadius` on `hrp` with growing radius); (c) on touch devices set the default `autoSweep = true` in `ProfileSchema.luau:214`, and add a one-time pulse on the AUTO chip in `Actions.luau` when stage becomes "wait".

## MINOR

1. Tutorial arrow breaks after a respawn. `Tutorial.luau:138-140` re-parents `att0` into the new character, but `att0` lived in the old character, which Roblox destroys (Destroy locks `Parent`). Scenario: the player resets during the "sell" stage; `poll()` (Heartbeat, no pcall) then throws "Parent property of Attachment is locked" every 0.25 s and the arrow never returns. Fix: `if att0 == nil or att0.Parent == nil then cleanupBeam(); end` before the reparent, and recreate the beam.
2. Coin burst can land off the coin icon on notched phones. `Coins.luau:81-91` returns `icon.AbsolutePosition` (screen space); `Vfx.luau:440-455, 457` places frames with `Position` inside `VSFxCoins`, whose inset settings differ from the HUD gui (`Vfx.luau:420-432` sets only `IgnoreGuiInset`, `Components.screen` also sets `ScreenInsets = DeviceSafeInsets`). Fix: `local target = coinTarget(size) - gui.AbsolutePosition` (the parent game does the same: `src/client/Controls/TouchControls.luau:159`), and build `VSFxCoins` and `VSFxTint` with `Components.screen(..., {fullBleed = true})`.
3. Daily red dot uses the device clock: `MenuBar.luau:87` `os.time()`. `Daily.luau:80-87` already uses `workspace:GetServerTimeNow()`. A phone with a wrong clock shows the dot at the wrong time. Fix: one line.
4. Duplicate visuals for gems and lava rings. Server builds a `GeyserGem` Part per gem (`GeyserService.luau:198-212`, replicated) and the client draws its own ball + halo for the same id (`Vfx.luau:892-930`) at a different height (2.5 vs 3). The client removes its copy within 4 studs (`:932-950`) and on every non-event phase (`:1119`), while the server part lives up to 25 s (`GEM_LIFETIME`). Same for the landing ring: server `LavaRing` (`BombVisuals.luau:70-100`) plus client `LavaSplash` (`Vfx.luau:751-764`). Fix: keep one source. Simplest: delete the client gem Parts (keep the pickup sound/haptic) and keep the server Part; keep the client telegraph disc, drop the server ring.
5. Per-zone progress is sent but never shown. `Progress` (`AshService.luau:183, 261`) has no client listener (`grep '"Progress"' src/client` finds only unrelated panel names). `CleanBar.luau` shows only `cleanTotal`. DESIGN: milestones per zone, "shared island clean meter". Fix: `ctx.listen("Progress", ...)` in `CleanBar` and show the fraction of the zone the player stands in (`zoneId` already computed at `:140-150`), with the 25/50/75 ticks on that fraction.
6. Ash Storm has no snow. DESIGN: "Soft grey snow VFX"; `Vfx.luau:1106-1107` only tints the screen. Fix: a pooled ParticleEmitter on a Part that follows the camera (`Vfx.luau` has the pool helpers) enabled while `kind == "ashStorm"` and phase "event".
7. Draw radius is larger than the camera can see. `AshRenderer.luau:33` `RADIUS = 200` gives up to 1932 Parts (measured: 1110 at the beach spawn, 1932 at the island centre); default max zoom is 128 studs. `RADIUS = 140` gives 644 at the spawn. Also `centre()` (`:259-273`) falls back to `Camera.Focus` before the character exists, so for the first frames it builds the cells around world (0,0) and then releases them when the character appears at z=222. Fix: `RADIUS = 140`, and return `nil` from `centre()` until the character exists.
8. Orientation is locked to landscape (`default.project.json:43` `LandscapeSensor`), same as the parent game, but DESIGN line 87 says "Landscape and portrait both usable" and `UiMath.layout` has a whole portrait branch that phones can never reach. Fix: either update DESIGN to say landscape only, or drop the property. Not a bug.
9. Doc drift: `RemoteDefs.luau:186-189` says GeyserGems is `{x,z,id}`; the real payload also has `rarity` and the form `{ removed = id }` (`GeyserService.luau:160, 286, 355`). The client handles all three (`Vfx.luau:1209-1228`), so only the comment is wrong. Also `Toasts.luau:36` cuts at 80 chars mid-word with no ellipsis; no current toast is that long.

## Scores (1-10, client-integration lens; target is 8 on every line)

| # | Quality-bar line | Score | Why | Biggest single raise |
|---|---|---|---|---|
| 1 | Core feel of sweeping | 5 | Input, cadence, puff, nudge, cell shrink and hooks are wired and correct, but no number pops (M1), no held tool or swing (M2), default square-sparkle puffs, no sound ids | M2, a visible tool that swings (then M1 pops) |
| 2 | Economy / progression pacing (as seen on the client) | 7 | Client only displays server numbers; coin count-up, sale burst, red dots are good; pacing itself is server and tests | M1 coin-value pops so progress is felt per swing |
| 3 | Upgrade variety and clarity | 7 | All 9 panels build from one kit, all remotes valid, cleanups correct; no tool visuals to show the tier (M2) | M2 |
| 4 | Phone UI quality and consistency | 7 | One Theme/Components kit, layout maths tested, jump button area reserved, insets handled; unverified on a device and coin burst space may be off on notches (minor 2) | One Studio phone-emulator pass (see "not verifiable") |
| 5 | Co-op feel | 5 | Friends' puffs, party fireworks and shared bar exist; per-zone progress unused (minor 5), no sign of who is where or what they carry, others' tools invisible (M2) | M2 held tool visible to others, then minor 5 |
| 6 | Volcano events fun/fairness | 7 | Banner, red rumble pulses, shake, ground telegraph, gold glow and gems all hook to the right payloads; duplicates (minor 4) and no snow (minor 6) | Remove the duplicate gem/ring visuals |
| 7 | Visual polish of the island | 6 | Ash tiles are well pooled and shaded, shrink-to-reveal works; effects use the default sparkle texture, no snow, no tool art | M2 plus snow |
| 8 | Reliability (no errors, saves safe) | 8 | Every module/widget/panel is pcall-isolated, no wrong API names found, no cycles, leaks closed; the one real runtime error is the respawn beam (minor 1) | Fix minor 1 and 7 |
| 9 | Security (client side) | 9 | Intent-only remotes, no position, client gating is cosmetic, server re-validates | Nothing client-side; keep server checks |
| 10 | First 5 minutes (7-year-old, no reading) | 6 | Splash, floating hints, Trade Hut arrow and big buttons are good, but M4 (hint ends on a press, AUTO off, no ash pointer) | M4 |

Component scores: load order and paths 9, remote contract 9, Store 9, AshRenderer 8.5, Controls 8, CameraFx 8, HUD/insets 7.5, Vfx 7, Tutorial 6.

## Not verifiable without Studio (check on the first Play)
1. HUD vs Roblox top bar on a notched phone in landscape: coins pill must clear the menu icon; confirm `IgnoreGuiInset=true` together with `ScreenInsets=DeviceSafeInsets` gives the origin `Theme.topInset()` assumes (the parent game uses both on several guis).
2. SWEEP button (x = width - 192 .. width - 108 virtual px) vs the default jump button (about 70 px wide, 25..95 px from the right edge on small screens): the maths says a 13 px gap.
3. 60 FPS on an old phone with about 1100 ash Parts (see minor 7) plus fireworks.
4. The `UIGradient` on the Splash `CanvasGroup` (`Splash.luau:35-38`): confirm it only tints the background and not the white title text.
5. Camera offset feel at `CameraFx.nudge(0.3)` (about 0.1 stud) may be too small to notice on a phone.

# FINAL audit: client + UI (last line of defence)

Area: `src/client/**`, `src/shared/Ui/**`, `src/shared/Client/**` and their tests. I read DESIGN, CONTRACTS, J1-J5 and the
J-fix handoff, then audited the current code from scratch.
Proof:
- `stylua --check src tests` is clean.
- `lune run tests/run`: 523 passed, 0 failed.
- `rojo build` is ok.
- Selene 0.27 ran with a stub Roblox std (the Roblox API dump is blocked here): 0 errors, 0 undefined variables in src.
- Scratch scripts, kept outside the repo, checked:
  - every `Module.field` and `Theme.*.*` / `UiMath.K.*` / Components method used by the client exists;
  - every shared string require resolves;
  - the HUD and panel rectangles at 800x360, 844x390, 640x360, 360x740, 320x568, 568x320 and 1920x1080.

## Scores after my fixes (honest, 1-10)

| # | Quality bar line | Score | The one thing still holding it below 9 |
|---|---|---|---|
| 1 | Core feel of sweeping | 8 | Each swing has a puff, a "+N" pop, a held tool that swings, a cell that shrinks and a camera nudge, but every sound is silent: `Config.Audio` has no ids yet. |
| 2 | Economy / progression pacing | 8 | The client only shows the server's numbers (count-up coins, sale burst, pops, new-only red dots). The pacing itself is a sim and has not been tried by real kids. |
| 3 | Upgrade variety and clarity | 8 | One kit everywhere, clear numbers, 8 tool looks in the hand. Nobody has seen the tool models yet: the shapes are built from Parts that were never rendered. |
| 4 | Phone UI quality and consistency | 8 | The layout maths is clear of Roblox's jump button on phones AND tablets (new test), and the left thumb area is free. The notch / safe area and emoji glyphs are unverified on a real device. |
| 5 | Co-op feel | 8 | Friends see your tool swing, your puffs and fireworks, and your zone's clean %. There is no marker of where friends are or what they carry. |
| 6 | Volcano events fun / fairness | 8 | One telegraph ring at `bomb.radius` (+ body), a red screen-edge warning while you stand in it, a banner countdown and snow. The bounce feel is unproven. |
| 7 | Visual polish of the island | 7 | Ash slabs are pooled, shaded and capped at 1100 Parts, but the island has never been looked at. Particles use the default square sparkle. |
| 8 | Reliability (no errors, saves safe) | 8 | Every module, widget and panel is pcall-isolated, handlers match the real payloads, and leaks are closed. There has still been no Studio boot of the client. |
| 9 | Security (server decides) | 9 | The client sends intent only. The AUTO chip is now only an optimistic picture that snaps back to the server's word. Nothing to add client-side. |
| 10 | First 5 minutes (7-year-old, no reading) | 8 | Auto-Sweep is on, so walking into ash sweeps. A glowing line leads to the ash and then the hut, a finger points at SELL, then MENU, then the Upgrades tile. No child has played it yet. |

## What I fixed (file:line, why)

1. `src/shared/Client/TutorialLogic.luau:181-187`, `src/client/Core/Tutorial.luau:57-58,591`: the shop step was broken by the new MENU launcher.
   - The finger pointed at MENU and then vanished once the menu opened (any open panel hid it). A cached MENU target could also keep it on the wrong button.
   - Now there are two steps: "Tap MENU to get stronger!" (finger on `Menu_menu`), then "Tap Upgrades!" (finger on the `Menu_upgrades` tile inside the open menu). Each target has its own cache. It re-points the moment a panel opens, and the button search retries after 0.5 s (was 1 s).
   - Test: `tests/tutorial_logic.test.luau`.
2. `src/client/Core/Tutorial.luau:28,59-64`: raw `Color3.fromRGB` / `Enum.Font` replaced by Theme tokens (goldLight, ink, gold, lava, font.title, DisplayOrder.overlay - 1).
3. `src/client/Hud/OfflineBadge.luau:35`, `src/shared/Ui/Format.luau:129`, `src/shared/Ui/SettingsModel.luau:99`, `src/client/Panels/Settings.luau:196` (leftover 3): `offlineRetrying` was sent but never shown.
   - The badge now says "⏳ Loading your save..." while the server retries, and "👤 Guest mode — not saving" only once it gives up.
   - The Settings card text follows the same rule and is now refreshed live (it was set once at build).
   - Tests: `ui_format`, `settings_model`.
4. `src/client/Hud/Actions.luau:34,355-370`: the AUTO chip flipped on tap but never snapped back if the server dropped the request (SetSetting is rate-limited 4/s). It now re-reads the store 1.5 s after a tap, and every 0.5 s after that. Missing value = ON, the same as Controls, Tutorial and Settings (leftover 1).
5. `src/client/Core/Controls.luau:98,222`, `src/client/Core/Tutorial.luau:511`: the `autoSweep` fallback is `true` (the new default).
6. `src/shared/Ui/UiMath.luau:18,74-78,332`, `src/client/Hud/Hud.luau:88`: on tablets, Roblox's jump button is 120 px at 50-170 px from the right. SWEEP/AUTO overlapped it by about 8 px at UI scale 1.5. A `bigJump` reserve now applies when the real short side is > 500 px. Phones are unchanged. Test: `tests/ui_math.test.luau` (SWEEP/AUTO/SELL vs Roblox's real jump rect on 6 screens).
7. `src/client/Panels/Menu.luau:95`: on a 568x320 phone the menu body is 520 x 174, which fell into the 3-column "tall" grid (tiles clamped to 76 px, so it scrolled). Any wide, short body now gets 5 columns, and the 8 tiles fit in 2 rows.
8. `src/client/Ui/Components.luau:779-790`: red dots pulsed forever, although the comment (and J5 m4) said "pulse, then stay still". The pulse now repeats `BADGE_PULSES` times, and a quick off/on can no longer leave two pulse tweens running.
9. `src/client/Vfx/Vfx.luau:65-70` + coin burst, danger edges and float text: screen-space colours, font and display orders now come from Theme (no raw colours on screen). In-world art (particles, discs) keeps its hex data.
10. `src/client/Ash/AshRenderer.luau:73,159-185,233`: the over-cap "starved" list could hold the same cell many times and hand a freed Part to a cell that already had one. It now has a set, and it skips cells that left, emptied or already have a Part.
11. `src/client/Core/Controls.luau:176-195`: Auto-Sweep swings get a softer camera kick (0.2 vs 0.45), a quieter swish and no controller buzz, so walking through ash does not bob the camera non-stop.
12. Selene warnings in my area: `AshRenderer.acquire` unused arg, `StoreLogic` stub args. Doc: `plans/handoffs/C2-ui-kit-hud.md` items 2, 3 and 10 described the old 9-button menu.

Checked and correct (no change):
- Leftover 2: the client telegraph and splash use `bomb.radius` (clamped 1..40).
- Leftover 4: `CleanBar` listens to `Progress` and shows the zone you stand in.
- Leftover 5: `CullLogic.ashAhead` is a superset of `AshGrid.queryCone`. It counts any cell within 1 cell (the server counts only your own cell) and reach + 0.5 cell (the server uses + 0.25). The existing sparse-island test checks 400 positions x 4 tools.
- Leftover 6: the names `SweepButton`, `AutoButton`, `SellButton`, `Menu_menu` and `Menu_upgrades` match the real instances.
- Leftover 8: `VSTool` and `VSSweeping` are spelled the same on both sides.
- Leftover 9: every shared require resolves.
- Every `Net.on` matches the server's `Net.fire` payloads: State, AshSnapshot, AshDelta, SweepFx, Sold, Toast, Burp, Bombs, BurpHit, Progress, Party, FindFound, CoolDownDone, Golden and both GeyserGems shapes.
- Main load order: Store → Net → feedback → Controls → Ash → Vfx → HeldTool → WorldFeel → PanelHost → Panels → Hud → Tutorial → ClientReady (retried every 3 s until the first State arrives).
- HeldTool:
  - R15 hand plus shoulder swing; R6 Right Arm with the grip swing only.
  - It rebuilds after a respawn or a body-part swap.
  - At most 16 models, built within 140 studs, animated within 110.
  - Cleanup on CharacterRemoving and PlayerRemoving.

## For the server auditor (not edited by me)
- `tests/_tmp_pacing_only.luau` is a stray temp file (it is not in `run.luau`). Delete it before the PR.
- Selene flags `server/Sweep/SweepService.luau:240` (`\u{2014}` escape) as a warning. Valid Luau, so a selene false positive. A plain "-" would silence it.

## Tap-through checklist (real phone or Studio phone emulator)
1. Join on a phone held sideways: the coins, bag bar and MENU sit top-left, and nothing covers the thumbstick.
2. SWEEP sits left of Roblox's jump button with a gap. Try a tablet too.
3. Walk into grey ash without touching anything: it sweeps by itself and "+N" numbers pop.
4. Tap AUTO twice fast: it ends showing what really happened.
5. Fill half the bag: a glowing line leads to the hut, the SELL button appears with a finger, then coins fly to the counter.
6. After selling: the finger points at MENU, then at the Upgrades tile. Buy one and see "You got stronger!".
7. Open MENU on a small phone: all 8 tiles show without scrolling.
8. Watch a friend sweep: their broom or vac is in their hand and swings.
9. In a lava burp, stand in a red ring: the screen edges glow red. One ring only.
10. Red dots pulse a few times, then stay still.
11. Reset while the tutorial line is showing: the line comes back with no errors in the F9 console.
12. Check the F9 console after 5 minutes: no red errors from Client.

# FINAL handoff: client + UI audit (src/client, src/shared/Ui, src/shared/Client)
1. Report with scores, fixes and a phone tap-through list: `plans/audit/FINAL-client.md`.
2. Tutorial shop step now goes MENU (`Menu_menu`) -> Upgrades tile (`Menu_upgrades`); TutorialLogic has `menuOpen` and point "menu".
3. Save note: `offlineRetrying` shows "⏳ Loading your save..." (HUD badge + Settings card); "Guest mode" only after the server gives up.
4. AUTO chip snaps back to the server's value 1.5 s after a tap; every client fallback for `autoSweep` is ON.
5. `UiMath.layout` takes `bigJump` (real short side > 500 px): SWEEP/AUTO clear Roblox's bigger tablet jump button; tested.
6. Tile menu uses 5 columns on any wide, short body (568x320 fits without scrolling).
7. Red dots pulse a few times then stay still; Vfx/Tutorial screen colours come from Theme.
8. AshRenderer over-cap queue is de-duplicated; Auto-Sweep swings kick the camera more softly.
9. Not done: no sound ids (silent by design), no friend markers; Escape still also opens Roblox's own menu on PC.
10. Needs a device: notch/safe area, emoji glyphs on old Android, held-tool look, 60 FPS with ~900 ash Parts.

## Ash look pass (after carter: "the ash is just blocks")
Ash cells are now soft dome mounds (stretched spheres, ~13 studs wide, smoothed heights with neighbours, jitter, embers in zones 4-5).
Files: src/shared/Client/AshShape.luau, src/client/Ash/AshRenderer.luau, tests/ash_shape.test.luau.
Check on a phone: frame rate at the island centre; if it looks cobbly change `RADIUS_FULL` in AshShape.

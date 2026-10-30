# Piece 08: Match HUD and effects (the juice)

**Goal:** The screen during a match: what is happening, and every hit feeling good.
**Read first:** build plan, `02-design.md` (UI design, banners, numbers).

## You own
- `src/client/Controllers/Hud.luau`, `src/client/Controllers/Effects.luau`, `src/client/Controllers/Minimap.luau`
- `src/client/Ui/Theme.luau` (colors, fonts, sizes shared by HUD and Menu; piece 09 reads it), `src/client/Ui/Banner.luau`
- `src/shared/Config/Hud.luau`, `src/shared/HudMath.luau` (pure): damage number size and color by amount, banner queue rules, minimap world-to-pixel, timer text
- tests: `tests/hud_math.test.luau`

## Build
1. **Top-left:** place badge (rank number) and `Players: n/16` from `MatchState`. Kill feed under it from `KillFeed` (max 4 lines, fade).
2. **Over each fighter:** name plate and a small HP + shield bar (BillboardGui, from `Hp`/`MaxHp`/`Shield` Attributes). Your own bar is bigger. Bots look the same as players.
3. **Bottom:** XP bar and level number (`Level`, `Xp` Attributes). Ammo ring / RELOADING word in the middle from `Ammo` and `ReloadingUntil`.
4. **Minimap** (top-right, round): the 5x5 grid, your dot (green), other fighters only when close, warned cells pulsing, blasted cells dark red (from `BlastWarn` / `BlastBoom`), a countdown over warned cells. The map is also tappable for the ghost poke: it exposes `Minimap.onTap(fn)` and piece 07's Poke button uses the same tap.
5. **Banners** (`Banner` remote): big italic text slides in, holds 1 s, slides out: ENTERING COMBAT (when an enemy is within 30 studs, client side), MULTI KILL, MEGA KILL, MASSACRE, INVINCIBLE, LEVEL UP, BLAST INCOMING, SUDDEN DEATH. One at a time, queued.
6. **Perk cards** (`PerkOffer`): three big cards (at least 110 x 140 px) in the middle with name, icon (simple shape + color), one-line text, an 8 s bar. Tap sends `PickPerk(i)`. Number keys 1-3 on PC.
7. **Effects:** damage numbers from `Hit` (white; crit = big and yellow, floats up and fades; pool the labels so nothing is created every hit), muzzle flash and trail from `Shot` (Parts or Beams, pooled), explosion from `Explosion` (flash + smoke + star burst), pit warning ring on the floor from `BlastWarn`, pit boom from `BlastBoom` (shake + dust), ghost poke warning circle from `GhostWarn`. A short red vignette when hit. Hit sound ids come from `Config/Hud.luau` as `nil` placeholders (no made-up asset ids).
8. Hide the HUD in the lobby and during `Results`. Respect the safe area.

## Server checks
None of its own: it only draws what the server says. It must not send anything except `PickPerk`.

## Performance
Pool labels, beams and sounds. No per-frame allocations in `RenderStepped`. Cap effects when more than 40 are alive.

## Tests (Lune)
`HudMath`: number size scaling, banner queue order and de-duplication, world-to-minimap mapping at corners, timer text (`0:08`).

## Done when
Checks pass, row 08 marked, handoff written.

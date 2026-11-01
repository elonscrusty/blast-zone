# J5 audit: phone UI quality and consistency

Judge: J5. Lens: Quality bar line 4 ("Phone UI quality and consistency"), plus the UI side of line 10.
Read: `src/client/Ui/*`, `Hud/*`, `Panels/*`, `Panels/Shared/*`, `src/shared/Ui/*`, `tests/ui_math.test.luau`, plus `Core/Tutorial.luau` and the ScreenGui parts of `Vfx/Vfx.luau`.
Ran (read-only): `lune run tests/run` = 465 passed, 0 failed. I also ran `UiMath.layout` / `panelRect` / `chipWidth` / `Format.compact` for 7 viewports from a scratch script outside the repo, to get exact rectangles. No file under `src/` or `tests/` was touched.
No Studio, no pixels. Everything below is derived from sizes, anchors and the layout maths. Section 6 lists what I could not verify.

## 0. Verdict

BLOCKERS: none. I found no runtime error, data loss or exploit on a main UI path. Every `Components`, `Hud` and `Panels` call I traced uses valid Roblox API, and every risky call is pcall-wrapped (`Components.luau:221-232`, `PanelHost.luau:271`, `Hud.luau:404`).
Theme discipline is the best part of the UI: zero raw `Color3`, `fromRGB` or hex and zero raw `Enum.Font` in `Hud/`, `Panels/` and `Ui/` outside `Theme.luau`. One `Color3.new` is used in the gradient helper (`Components.luau:91`).
MAJOR: 5. The biggest single risk is that the left menu column sits in the thumbstick zone in landscape.
MINOR: 14.

## 1. Scores (target 8)

| Sub-line | Score | Why (one sentence) | Single biggest raiser |
|---|---|---|---|
| A. Layout and overlap safety (HUD, panels, Roblox UI) | 7 | The shared layout maths is pure, tested and overlap-free for 9 viewports, but it only reserves the jump button, so toasts land on the character and the menu lands on the thumbstick. | Replace the 9-button left column with one MENU launcher (M1). |
| B. Touch ergonomics, phone first | 6 | Every `Button` face is 4 px shorter than its box, so the most-tapped controls have 38-42 px hit areas against the repo's own 44 px rule. | Make the face fill the whole root and use 48 px boxes (M2). |
| C. Consistency and Theme tokens | 8 | One kit, one palette, one DisplayOrder table, no stray colours in the UI; only per-panel button heights and a few raw text sizes drift. | A `Theme.size.button` token set and moving the Tutorial colours into Theme (m5). |
| D. Panel flow and states | 8 | One panel at a time, three ways to close, maxed/locked/too-expensive/empty states all handled, only the Cool Down CTA is awkward. | Pin the Cool Down action in a footer (M3). |
| E. Legibility and kid readability | 6 | 8-13 px text floors, white-on-light-green prices, icon-only menu, and chips that shrink to 22 px of text. | Responsive buff chips plus a text floor of 11 (M5, m6, m7). |
| F. Feedback, animation, UI performance | 8 | Press, lip squash, punch, haptic and sound hooks everywhere, cleanup is sound, per-frame work is one count-up; only the always-pulsing dots are noisy. | Pulse a dot only when it is new (m4). |
| Line 4 overall | 7 | A genuinely cohesive premium-looking kit whose phone-landscape ergonomics (menu, toasts, hit areas, chrome height) were never tried on a thumb. | M1 plus M2. |

## 2. MAJOR findings

### M1. The permanent 9-button menu sits where the left thumb lives (landscape phones)
- Where: `src/shared/Ui/UiMath.luau:258-290` (menu rect), `UiMath.luau:37,258-260` (only `jump` is reserved), `Hud/MenuBar.luau:212`.
- Verified by reading: `UiMath.layout` reserves a 100x100 area for the Roblox jump button and nothing for the movement thumbstick. The left menu is built from `PanelHost.menuButtons`, which is 9 panels.
- Computed: at 800x360 the menu rect is (6,108) 96x240, two columns by five rows. At 844x390 it is (6,105) 96x240. At 568x320 it is (6,108) 144x144, three columns.
- Roblox's thumbstick, fixed or dynamic, is in the bottom-left. At 800x360 the classic thumbstick's frame is about x 50-170, y 150-270, which overlaps the menu (x 6-102, y 108-348).
- The 9 buttons are a ScrollingFrame, which also sinks touches in its rectangle.
- Scenario: a 7-year-old on an iPhone in landscape puts the left thumb down to walk. The touch lands on a menu button or its scroll area. Dynamic thumbstick will not start, so the player taps 🛠 or ❄️ by accident, or cannot walk.
- Fix: collapse the column into ONE 48 px "MENU" button under the pack bar (`Hud/MenuBar.luau`) that opens a launcher panel. The launcher is a 3x3 grid of big icon+word tiles registered through `PanelHost` as `id = "menu"`. The red dots aggregate on that one button and also show on the tiles. That frees the whole left-middle of the screen and lets the tiles carry words (m3).

### M2. Hit areas are 38-42 px, not the 44 px the repo promises
- Where: `Ui/Components.luau:418` (`faceSize = ... UDim2.new(1, 0, 1, -lipPx)`), `Components.luau:434-444` (only `Face` is the `TextButton`), `Ui/Theme.luau:145-151` (`touch = 44`, `lip = 4`, `closeButton = 46`).
- Verified: a Button's root is 44 px high, the `Face` TextButton is root minus the 4 px lip, and only the face receives `Activated`. So:
  - Menu IconButtons (44 root): 44x40 hit.
  - AUTO (84x44): 84x40.
  - Tabs, Cancel, Claim, OK (`Theme.size.touch` = 44): 40 high.
  - Panel close X (46 round): 42x42 (`Components.luau:1627-1636`, round buttons subtract the lip on both axes).
  - Upgrades BUY: `Upgrades.luau:35` `buttonH = 42`, so 38 px high. This is the most-tapped control in the game.
  - Gates BUY in portrait: `Gates.luau:34` `buttonHTall = 42`, so 38 px.
- Test gap: `tests/ui_math.test.luau:210-222` asserts `min(r.w, r.h) * s >= 44` on layout rectangles. The AUTO rect is 44 and passes, but the real face is 40. The check is true on paper and false on the glass.
- Scenario: a 6-year-old with a wide fingertip taps BUY on Upgrades at the edge of the card and misses. The button squashes, nothing happens, and the child does not know why.
- Fix: in `Components.Button`, make the `Face` TextButton `Size = UDim2.fromScale(1,1)` and draw the visible face and lip as non-Active children, or add a transparent full-root hit `TextButton`. Also set `Upgrades.buttonH` and `Gates.buttonHTall` to 48 (`Theme.size.button` = 48). Add a test that Button hit height >= 44 for every size in the kit.

### M3. The Cool Down button is below the fold and jumps away when armed
- Where: `Panels/CoolDown.luau:303-352` (`Action` frame, `LayoutOrder = 5`, `Warn` card above `CoolDownButton`, then `NotNow`), `CoolDown.luau:531-534` (`extra = WARN_H + gap + touch + gap`, `action.Size` grows).
- Verified from constants: landscape body is 226 px (computed 656x226 at 800x360). Tabs 44 plus gap 6 leave a 176 px scroll viewport. Content above the button is hero 84 + status 92 + lists 150 + 3 gaps = about 344 px, so the button starts about 170 px below the fold.
- Portrait 360x740 is 606 px body, 556 px viewport; content is about 106+92+306+60 plus gaps, so it is borderline.
- When armed, the warn card appears ABOVE the button in the same list, pushing the confirm button down by 58 px inside a scrolling frame that does not follow it.
- Scenario: at about 90 minutes the dot appears, the child opens the panel, and sees a text wall and no button. If they scroll to it and tap once, the warning card slides in above and the confirm button moves out of view. The prestige moment feels broken.
- Fix: pin `action` (warn, button, not-now) in a fixed footer under the scroll list, the way `Daily.luau:96-122` pins its Claim button in `Bottom`. Keep the warn text inside the footer, above the button, with the footer height fixed at WARN+BIG.

### M4. Opaque toasts and the banner sit on the character, and they draw over open panels
- Where: `UiMath.luau:299-301` (banner under buffs), `UiMath.luau:324-333` (toast stack), `Ui/Theme.luau:173-178` (`panels = 20`, `banner = 25`, `toasts = 30`), `Hud/Toasts.luau` (opaque `CanvasGroup`).
- Computed at 800x360: clean (250,40), buffs (250,82), banner (250,112) 300x44, toasts (250,160) 300x104.
- The screen centre is (400,180). The toast stack covers y 160-264 around the middle, so it covers the lower half of the character and the ground at their feet. The Roblox default camera puts the character near the middle.
- During a Lava Pops event the telegraph circles are on the ground around the player. Up to three opaque 32 px toasts (such as "Backpack full! Sell at the Trade Hut") hide the circles the child is meant to dodge.
- The banner and toast ScreenGuis have a higher DisplayOrder than the panel layer. With a panel open, a toast lands on top of the cards and on the BUY button the child just tapped ("Need 120 more coins!" appears over the card it refers to).
- Scenario: Rumble banner, then sweeping, then toasts. The player cannot see where the lava target is, and takes the hit.
- Fix:
  - Toasts: at most 2 rows, 28 px high, `BackgroundTransparency = 0.15`, anchored to the left of centre under the clean bar and not over the character. Better: stack them just under the banner and cap the stack height at 60 px in landscape.
  - While `PanelHost.isOpen()`, route `Hud.toast` into a one-line strip inside the panel (below the title bar) instead of the HUD overlay.

### M5. Buff chips become unreadable with 3 buffs on a 360 px phone (2 on a 320 px phone)
- Where: `UiMath.luau:313` (portrait `buffs` width = `clean.w`), `UiMath.chipWidth` (`UiMath.luau:113-119`), `Hud/BuffChips.luau:110-116`, `Ui/Components.luau:884-898` (Pill label starts at `textX = 30` with an icon, width `chipW - 38`).
- Computed: 360x740 gives `buffs.w` = 188, so 3 chips are 60 px wide and the text label is 22 px. 320x568 gives `buffs.w` = 148, so 2 chips are 72 px wide and the label is 34 px.
- The text is "x2 4:59" in a `TextScaled` label with `MinTextSize = 8` (`Theme.text.min`, `Components.luau:321`). Seven characters at 8 px are about 31 px, so on a 22 px label the text spills past the chip edge.
- `tests/ui_math.test.luau:64-68` actually asserts the 46 px chip, so it enshrines the illegibility.
- Scenario: the island party (60 s), a perfect dodge (3 min) and a golden burp (45 s) overlap. This is a plausible state in a 16-player server. The kid sees three squeezed pills of broken digits.
- Fix: in tall mode put the buffs row under the pack bar spanning the full width (`vw - 2m` = 344 px), or make chips icon plus countdown only (no word label). Enforce `chipW >= 64` and wrap to a second row. Add a test asserting `labelWidth >= 40` at every viewport.

## 3. MINOR findings

m1. `Components.shakeX` captures `base = inst.Position` at call time (`Components.luau:158-189`, line 163). A disabled-button tap calls `self.shake()` (`Components.luau:597`) during the release of the pressed-position tween (`setPressed`). If the order is `InputEnded` then `Activated`, `base` is the pressed offset (about 2-3 px low) and the face rests low until the next press. Event order is not verifiable without Studio. Fix: capture the rest position `facePos` explicitly.

m2. CostButton price group is left-biased for short prices. `Components.luau:1419-1465` centres a block of coin (22) + gap (5) + a FIXED 70 px label (`:1462`, `:1492`). For "35" the visible content is about 43 px but the centred block is 97 px, so on a 104 px button the coin and number hug the left and the right half is empty. The early game is all small prices. Also the block (97) is wider than the group (92). Fix: size the label to `AutomaticSize.X`, or centre the text in a 1-scale label with the coin pinned left.

m3. The menu is icon-only (`MenuBar.luau` builds `IconButton` with `def.icon` only), 9 buttons from second zero:
- 🛠 ⬦ 🧹 ⬦ 🤖 ⬦ 🚪 ⬦ 📖 ⬦ 🎯 ⬦ 🎁 ⬦ ❄️ ⬦ ⚙️, with no words and no tooltip on PC.
- Tools uses 🧹 (`Panels/Tools.luau:542`), which is also the SWEEP button icon (`Hud/Actions.luau:85`) and the splash.
- Cool Down (locked for about 90 minutes) is as prominent as Upgrades.
- Fix: words under the icons in the M1 launcher, a distinct icon for Tools, and reveal Helpers, Gates, Cool Down and the Book only once they are relevant.

m4. Red-dot noise. `MenuBar.luau:62-66` lights `upgrades` whenever ANY upgrade is affordable. The cheapest levels cost 12-35 coins, so that dot is on almost constantly, and each dot runs an infinite pulse tween (`Components.luau:~743-775`). Up to 6 pulsing dots at once is not restraint. Also the Upgrades "⭐ Best buy" tag (`Panels/Upgrades.luau:147`, `UpgradesModel.luau:147-165`) is simply the CHEAPEST line, not the best value. Fix: pulse once on first light, then go static; rename the tag to "Cheapest" or "Next".

m5. Consistency drift:
- Raw colours and fonts in `Core/Tutorial.luau:84,91,100,133` (`Color3.fromRGB` x4, `Enum.Font.GothamBlack`).
- Vfx ScreenGui orders 45 and 50 (`Vfx/Vfx.luau:430,573`) are outside `Theme.DisplayOrder` (max 40).
- Raw text sizes: `Actions.luau:87,251` (15, 13), `Backpack.luau:128`, `BurpBanner.luau:75,86`, `Splash.luau:476,483`, `Toasts.luau:375`, `Components.luau:~360 (11)`.
- Hex in view-models: `BookModel.luau:176`, `GatesModel.luau:152`, `ToolsModel.luau:229`.
- Main action heights differ by panel: Upgrades 42, Gates 44/42, Helpers 44, Tools 50/52, Daily 48, CoolDown 60. `CLAIM_W = 104` is duplicated in 5 files (Book, Goals, Gates, Upgrades, CoolDown).
- Fix: add `Theme.size.button`, `claimW`, `Theme.fontSizes`; move the Tutorial constants into Theme.

m6. Contrast (my arithmetic from the Theme hexes, WCAG relative luminance):
- White on green `#4CC764` (variant `good` face and the BUY price) is about 2.2:1.
- White on teal `#1FB5A8` (secondary button, selected tab, GEYSERS banner) is about 2.5:1.
- White on lava `#FF7A2F` (primary button, SWEEP, panel title bar) is about 2.6:1.
- All carry a 1.5 px outline, which helps but does not fix sunlit-phone readability for kids. Charcoal on gold and white on lavaDark (4.5:1) are fine.
- Fix: use `greenDark` (3.6:1), `tealDark` and `lavaDark` as the FACE, with the light colour as the lip highlight.

m7. Text floors. `Theme.text` has `tiny = 11`, `small = 13`, `min = 8` (`Theme.luau:126-134`), and `TextScaled` can silently shrink to 8 (`Components.luau:321,477,492`).
- Used for core information: pack-bar text, zone name, tile state labels, upgrade descriptions.
- Toasts are single-line in 32 px (`Toasts.luau:141-145`) with 80 bytes allowed (`:100-101`, `string.sub` can cut a multi-byte emoji). At 320x568 the toast text region is 160 px, so "Backpack full! Sell at the Trade Hut" (36 chars) shrinks to about 8.5 px and "That gate is locked — open it at the gate!" hits the 8 px floor and overflows.
- Fix: min 11, small 14, tiny 12; toasts 2 lines at 40 px; truncate on a UTF-8 boundary.

m8. Splash colour. `Splash.luau:31-37` puts a gold-to-lava `UIGradient` on a `lavaDark` background. UIGradient multiplies, so the screen renders deep crimson-brown, not the warm sunny gradient the comment promises. Fix: base `white`.

m9. Double click sound. `PanelHost.close()` plays "click" (`PanelHost.luau:176`) and the close X is a Button with `sound = "click"` (`Components.luau:1635`, played at `:602`). Open does the same (`PanelHost.luau:286` plus the menu button). Silent today (no ids), double once audio ids land.

m10. Small landscape 568x320: body 186 px, so Upgrades shows 1.3 cards and the Book detail sheet is `DETAIL_H = 196` (`Panels/Book.luau:37`), taller than the body, so about 5 px is clipped top and bottom. The chrome is 114 px of the 260 px panel (title 54, padding 20, header 40). Fix: title bar 44 on short screens, merge the coin pill into the title bar, set `DETAIL_H = min(196, bodyH - 8)`.

m11. 320x568 menu goes two-column by 8 px. `UiMath.luau:264` reserves `offlineH + m` = 28 px for the guest badge even when it is hidden; 9 buttons need 432 px against 424 available, so the menu uses two columns and squeezes the banner to 202 px and the toasts to a 160 px text region. Fix: reserve the badge height only when `offline` is true, or lay it out beside the sell button.

m12. The daily dot uses the client clock: `MenuBar.luau:87` `UiMath.dailyReady(daily.lastDay, os.time())`, while the panel uses server time. A wrong device clock lights a dot for a gift that is not there. Already listed in the C4 handoff.

m13. Escape also opens Roblox's own menu (`PanelHost.luau:294-306` sinks via ContextActionService, but CoreGui handles Escape on its own). Already flagged by the author. On PC the first Escape closes the panel and opens the Roblox menu.

m14. Test gaps in `tests/ui_math.test.luau`: no hit-area test (see M2), no minimum label/chip width (M5), no rect for the screen-centre/character (M4), no panel vs HUD z-order check, no text-fit guard for the longest strings (m7). Nothing tests `PanelKit` or `Components`.

## 4. Verified OK (how I confirmed)

- One panel at a time: `PanelHost.open` destroys the current one first (`PanelHost.luau:197-203`), and `close()` is re-entrancy safe (`:160-189`).
- Close is always reachable: X in the title bar (`Components.luau:1627-1651`), backdrop tap (`PanelHost.luau:249`), Escape or gamepad B (`:294-306`). At 800x360 the panel is (60,48) 680x300 with 60 px dim strips on both sides, so tap-outside is usable.
- Safe area: HUD and panels use `ScreenInsets = DeviceSafeInsets` plus `IgnoreGuiInset` (`Components.luau:215,223-225`), with the top bar reserved by `Theme.topInset()` (`Theme.luau:203-211`) in both HUD layout and `placePanel` (`PanelHost.luau:126`). Splash is full bleed.
- Virtual px plus one UIScale per screen, so layout code is device-free (`Components.luau:250-265`); scale is clamped 1-1.5 (`UiMath.scaleFor`).
- Panel layout from the real panel size with the pop-in and screen scale divided out (`PanelKit.scaleOf`, `PanelKit.watchSize`), with a fallback when size is 0 (`PanelKit.luau:48-90`).
- Every list scrolls (`Components.ScrollList`), so nothing is cut off, with the scrollbar inset accounted (`Components.luau:1292,1305`).
- States: `CostButton.set` handles price/affordable/maxed (`Components.luau:1480-1504`); disabled taps play error, shake and toast (`Components.luau:594-600`). Gates: "🔒 LOCKED" (`Gates.luau:~245`). Tools: LOCKED/NEXT/EQUIPPED. Book: "?" tiles. Helpers: "+" slots. Tool buy and zone buy send ids as strings.
- No client-side spending: panels only send intent and celebrate when the SERVER state changes (`Upgrades.luau:260-274`, `Helpers.luau` repaint).
- Leaks: panel `Context`s are destroyed on close (`Settings.luau:221`, `CoolDown.luau:~620`); infinite tweens are cancelled in cleanup (`Tools.luau` stops/glowStop, `Helpers.luau` stopWobble); `Components.tween` keys by instance in a weak table (`:110`). Hud.destroy tears everything down.
- Per-frame work: only `Coins` (`ctx.every(0, ...)`, and only while counting). Everything else is 0.1-0.5 s timers on one Heartbeat connection (`Context.luau`).
- Press feedback: lip squash, hover lighten, `punch`, haptic and sound hook on every Button (`Components.luau:539-606`).
- Layout test: `lune run tests/run` = 465 passed, 0 failed; no overlap, inside the screen and under the top bar for 9 viewports and 3 insets.

## 5. Top 10 changes for seamlessness (ranked by impact)

1. Replace the left 9-button column with one MENU button plus a launcher panel of 3x3 icon+word tiles (M1, m3). This also fixes progressive disclosure.
2. Make the whole Button box the hit target and raise action buttons to 48 px (M2). Add the hit-area test.
3. Move toasts out of the screen centre: 2 rows, semi-transparent, and into an in-panel strip while a panel is open (M4). Keep the banner at the very top.
4. Pin the Cool Down action in a fixed footer (M3).
5. Responsive buff chips: full-width row in portrait, minimum chip width 64, icon plus timer (M5).
6. Shrink panel chrome on short screens: title bar 44, coins in the title bar, `DETAIL_H` clamp (m10). That is about +40 px of body on 800x360.
7. Darker CTA faces and a text floor of 11 (m6, m7). Two-line toasts.
8. Pulse a red dot only when it is new, rename "Best buy" (m4).
9. Token clean-up: `Theme.size.button`, `claimW`, Tutorial colours and fonts into Theme, Vfx display orders into `Theme.DisplayOrder`, hex out of the view-models (m5).
10. Add tests for hit area, chip label width, toast rect vs screen centre and longest-string fit; re-run on the 9 viewports (m14).

## 6. Not verifiable without a device

- Whether Android Roblox reports `ViewportSize` in physical pixels. `UiMath.scaleFor` is `clamp(min(w,h) / 360, 1, 1.5)` (`UiMath.luau:67-80`); on a 2400x1080 report the UI would be drawn at 1.5 on a 1080 px short side, about half the intended size. Check on the first Play on a real Android.
- Exact Roblox thumbstick and jump-button rectangles (M1 uses the classic stick's documented placement).
- Whether the emoji font renders ❄️, ⚙️, ✔️, ⚠️, 🛠 (Unicode 7 plus variation selectors) on older Android.
- Event order of `InputEnded` versus `Activated` (m1).
- Core chat window overlay on the top-left HUD cluster.

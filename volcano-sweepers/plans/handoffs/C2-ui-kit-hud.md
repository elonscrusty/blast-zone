# C2 handoff: UI kit + HUD

1. Files: `src/client/Ui/{Theme,Components,PanelHost,Fmt,Bridge}.luau`, `src/client/Hud/*.luau` (`Hud.luau` entry, one module per widget), `src/shared/Ui/{UiMath,Format}.luau` (pure), `tests/ui_math.test.luau`, `tests/ui_format.test.luau`.
2. Main calls `require(Hud.Hud).init()` once (after Core/Store + Net). Panels call `PanelHost.register({id,title,icon,order,build=function(parent, ctx) ... return cleanup? end})`; the menu bar draws one button per registered panel, sorted by `order`.
3. Panel ids that get automatic red dots: `upgrades`, `tools`, `helpers`, `gates`, `daily`, `cooldown` (spelling like `cool_down` also works). Anything else: `Hud.setBadge(id, true)`.
4. Build panels only from `Components` (Panel body is already padded + clipped): `Card`, `Button`, `IconButton`, `CostButton:set(price, affordable, label)`, `Pill`, `Bar`, `Toggle`, `Tabs`, `ScrollList`, `Pips`, `Badge`, `Label`, `CoinIcon`. Colours/sizes/fonts only from `Theme`; numbers with `Theme.fmt(n)` or `Fmt.n`.
5. The UI works in "virtual px": each screen has a root frame + UIScale (`Theme.scale`, 1.0 on phones, up to 1.5 on PC) so plain pixel offsets are fine everywhere.
6. Phone layout lives in `UiMath.layout` and is unit tested (9 screen sizes, 3 top-bar heights: no overlap, inside the screen, touch targets >= 44 real px, menu never needs scrolling with 9 buttons).
7. HUD talks to the core only through `Ui/Bridge` (lazy pcall-require of Core/Store, Net, Controls, Sfx, Haptics): a missing core module disables that feature, never the HUD.
8. Remotes used: `Burp`, `Toast` (listen only), `SetSetting autoSweep` (send). State keys read: coins, carried, carriedValue, derived, buffs, cleanTotal, settings, offline, daily and the upgrade/tool/zone/helper keys (for dots).
9. `Hud.coinTargetPosition()` returns the coin icon centre in screen pixels for `Vfx.coinBurst`. Sell pads are found with the `VSSellPad` tag (polled 4 Hz).
10. Not done / risks: never run in Studio (checked with a Lune fake-Roblox harness only); no sound ids; Escape is also seen by Roblox's own menu; buff chips sit under the clean bar (not beside the coins) and AUTO sits above SWEEP so the jump button stays free.

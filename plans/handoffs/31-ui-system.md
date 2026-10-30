# 31 UI system for Claude Design
1. Goal: Claude Design (carter's design tool) makes the whole UI; this piece makes that drop in. Built on #24 (`src/client/Ui/`).
2. `plans/UI-SCREENS.md`: all 29 screens/pieces (main + open PRs) with states, data, remotes, layer, file, and phone/PC/controller sizes.
3. `plans/UI-DESIGN-BRIEF.md`: paste-ready brief with carter's picks (HUD B Street Sticker, Neon Night, Big Banner, Scrap) and the JSON shape to hand back.
4. Look layer: `Ui/Tokens.luau` (roles, `check`, contrast) + `Ui/Skins/StreetSticker.luau` (today's look, default). `Hud/Theme` and `Hud/UiKit` now read it, so old screens follow a new skin.
5. Parts: `Ui/Components.luau` (screen, text, panel, button, bar, modal) take roles only. Modal uses `ModalGate`; buttons keep 48 pt.
6. Import: `lune run tools/import-design design/<id>.json` checks and writes a skin file. Template: `design/skin-template.json`.
7. Rule in CONTRACTS "Look and logic". `tests/ui_tokens.test.luau` fails on new files that write colours/fonts; `LEGACY` list (12 files, incl. ones in #16 #17 #20 #22) only shrinks.
8. Steps to bring work back: `plans/UI-BRING-BACK.md` (carter's 5 tiny steps + builder steps).
9. Checks: stylua OK, `lune run tests/run` 342 pass, rojo build OK, luau-lsp clean on Ui/ and Hud/. selene needs CI (no API dump here). Nothing run in Studio.
10. Next: when carter brings the JSON + pictures, import the skin, then move LEGACY screens onto Components one group per PR.
11. Update: carter's Claude Design skin "Street Sticker+" (design/street_sticker_plus.json) is imported as `Ui/Skins/StreetStickerPlus.luau` and is now `Tokens.defaultSkin` (display font LuckiestGuy, body FredokaOne, warmer win/lose/draw banners). Screens still on LEGACY keep their old hard-coded look until moved to Components.

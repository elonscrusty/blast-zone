# 22 UI layers and screen-size fixes
1. Bug fixed: Settings (DisplayOrder 40) drew under the lobby (MatchFlow, 50). Now Settings is `UiLayers.Modal` (100).
2. New `src/client/Ui/`: `UiLayers` (one list of DisplayOrders), `ModalGate` (one panel at a time), `LobbyLayout` + `LobbyMenu` (lobby button slots).
3. Every ScreenGui now uses `UiLayers`; a test fails on a bare `DisplayOrder = <number>`. Rule is in CONTRACTS.md "Screen layers".
4. Lobby: PLAY/SETTINGS could touch on short phones (min size 48 pushed them together). Now in fixed slots with a gap; status text above.
5. HUD: `Layout.place` takes the real screen shape; on 16:9 phones the reload button used to sit on the fire stick. Tablets get the 16:9 layout shrunk.
6. Spectate arrows had no DisplayOrder (0) and sat under the HUD and thumbs; now `UiLayers.Spectate`.
7. Bots banner moved to the top band so it no longer covers the lobby status text. Kill feed ends above the player.
8. No new looks: same colours, fonts and buttons. Claude Design thread owns the look; these files are only structure.
9. Checks: stylua, `lune run tests/run` 333 pass, rojo build OK. selene needs CI (no API dump here). Nothing run in Studio.
10. Open PRs #16, #17, #20 use bare numbers; switch list is at the end of CONTRACTS "Screen layers" (test fails until done).

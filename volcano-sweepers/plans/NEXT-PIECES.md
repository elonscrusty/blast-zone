# Volcano Sweepers pieces

Built in waves. Read `DESIGN.md` then `CONTRACTS.md`. A piece edits only the files it owns.
Status values: todo / building / done (tests green) / audited.

| # | Piece | Owner files | Status |
|---|-------|-------------|--------|
| R1 | Rules + catalogs + economy + balance sim | shared/Config.luau, shared/Catalog/*, shared/Rules/* | todo |
| R2 | Ash grid + burp director + finds roller (pure sims) | shared/Ash/*, shared/Burp/*, shared/Finds/* | todo |
| R3 | Saving + PlayerState + purchases (pure) | shared/Profile/*, shared/Player/* | todo |
| S1 | World builder + lighting + hub + decor | server/World/* | done (tests green, S1) |
| S2 | Sweep/sell/regrow/progress services + ash replication | server/Ash/*, server/Sweep/* | todo |
| S3 | Burp events + finds + geysers (server) | server/Burp/*, server/Finds/* | todo |
| S4 | Player service, saving glue, purchases, helpers, daily, goals, cool down | server/Player/*, server/Helpers/*, server/Main.server.luau | done (tests green, S4) |
| C1 | Client core: store, input, controls, ash renderer, VFX, camera, sound hooks | client/Core/*, client/Ash/*, client/Vfx/* | todo |
| C2 | UI kit + HUD + toasts | client/Ui/Theme, Components, Hud/* | todo |
| C3 | UI panels: upgrades, tools, helpers, gates | client/Panels/* | todo |
| C4 | UI panels: finds book, goals, daily, cool down, settings, tutorial | client/Panels/* | todo |
| J | Judges + Opus audit + fixes | anything | todo |

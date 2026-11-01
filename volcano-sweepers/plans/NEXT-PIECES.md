# Volcano Sweepers pieces

Built in waves. Read `DESIGN.md` then `CONTRACTS.md`. A piece edits only the files it owns.
Status values: todo / building / done (tests green) / audited.

| # | Piece | Owner files | Status |
|---|-------|-------------|--------|
| R1 | Rules + catalogs + economy + balance sim | shared/Config.luau, shared/Catalog/*, shared/Rules/* | done (audited) |
| R2 | Ash grid + burp director + finds roller (pure sims) | shared/Ash/*, shared/Burp/*, shared/Finds/* | done (audited) |
| R3 | Saving + PlayerState + purchases (pure) | shared/Profile/*, shared/Player/* | done (audited) |
| S1 | World builder + lighting + hub + decor | server/World/* | done (tests green, S1) |
| S2 | Sweep/sell/regrow/progress services + ash replication | server/Ash/*, server/Sweep/* | done (audited) |
| S3 | Burp events + finds + geysers (server) | server/Burp/*, server/Finds/* | done (audited) |
| S4 | Player service, saving glue, purchases, helpers, daily, goals, cool down | server/Player/*, server/Helpers/*, server/Main.server.luau | done (tests green, S4) |
| C1 | Client core: store, input, controls, ash renderer, VFX, camera, sound hooks | client/Core/*, client/Ash/*, client/Vfx/* | done (audited) |
| C2 | UI kit + HUD + toasts | client/Ui/Theme, Components, Hud/* | done (audited) |
| C3 | UI panels: upgrades, tools, helpers, gates | client/Panels/{Upgrades,Tools,Helpers,Gates}, client/Panels/Shared/*, shared/Ui/*Model | done (audited) |
| C4 | UI panels: finds book, goals, daily, cool down, settings | client/Panels/{Book,Goals,Daily,CoolDown,Settings}, shared/Ui/{Book,Goals,Daily,CoolDown,Settings}Model | done (audited) |
| J | Judges + Opus audit + fixes | anything | done (5 judges, 3 Opus fixers, 2 Opus final auditors) |
| M1 | Island models: Trade Hut, gate, camp, palm, rocks, mushroom, spire, sign (3 looks each) | server/World/Models/*, tools/dump_models.luau, tests/models.test.luau | done (tests green); carter picked A Toy Pop (B Tiki Wood and C Basalt Glow stay as skins). Not wired into the world yet (main thread does that) |

J-fix server + shared (src/server, src/shared except Ui/Client): done (tests green). Handoff: plans/handoffs/J-fix-server-shared.md
FINAL audit, server + shared (src/server, src/shared except Ui/Client): done (tests green). Report: plans/audit/FINAL-server.md, handoff: plans/handoffs/FINAL-server.md
FINAL audit, client + UI (src/client, src/shared/Ui, src/shared/Client): done (tests green). Report: plans/audit/FINAL-client.md, handoff: plans/handoffs/FINAL-client.md

# Next pieces

One piece per thread. Mark it here when its PR is up, then write a handoff in `plans/handoffs/`.
All pieces go in together in one batch, then carter plays.
Read `plans/CONTRACTS.md` first. Your files are the only files you edit (see "Who owns what").

Source of truth: carter's design brief (game name in `Config.Game.Name`). Section numbers (§) are from that brief.

| # | Piece | Brief § | Status | PR |
| --- | --- | --- | --- | --- |
| 00 | Repo setup | - | done | first commit |
| 01 | Core + shared rules (Config, remotes, ids, damage door, boot) | 17 | PR up | this PR |
| 02 | Movement, elevated camera, Slide | 8, 10 | PR up | see PR |
| 03 | Aiming, firearm, health, elimination (explosive weapon later) | 9, 11 | PR up | this PR |
| 04 | Graybox arena + interior/roof visibility | 12, 8 | PR up | this PR |
| 05 | Match state machine, spawns, results, spectate, reset | 7, 11, 16 | PR up | this PR |
| 06 | Safe zone + sudden death | 15 | PR up | this PR |
| 07 | Supply containers (3 loot tiers), XP orbs, run XP wiring | 13, 14 | PR up | see PR list |
| 08 | Upgrade catalogue + offers (server) + upgrade cards (client, Bottom Row) | 14, 20 | PR up | this PR |
| 09 | Test bots | 18 | PR up | this PR |
| 10 | HUD, minimap + zone display, touch/desktop/controller controls, settings (cards moved to 08, results to 05) | 20 | PR up | this PR |

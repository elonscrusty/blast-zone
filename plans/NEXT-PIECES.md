# Next pieces

One piece per thread. Mark it here when its PR is up, then write a handoff in `plans/handoffs/`.
All pieces go in together in one batch, then carter plays.
Read `plans/CONTRACTS.md` first. Your files are the only files you edit (see "Who owns what").

Source of truth: carter's design brief (game name in `Config.Game.Name`). Section numbers (§) are from that brief.

| # | Piece | Brief § | Status | PR |
| --- | --- | --- | --- | --- |
| 00 | Repo setup | - | done | first commit |
| 01 | Core + shared rules (Config, remotes, ids, damage door, boot) | 17 | PR up | #2 |
| 02 | Movement, elevated camera, Slide | 8, 10 | PR up | #9 |
| 03 | Aiming, firearm, health, elimination (explosive weapon later) | 9, 11 | PR up | #7 |
| 04 | Graybox arena + interior/roof visibility | 12, 8 | PR up | #10 |
| 05 | Match state machine, spawns, results, spectate, reset | 7, 11, 16 | PR up | #11 |
| 06 | Safe zone + sudden death | 15 | PR up | #3 |
| 07 | Supply containers (3 loot tiers), XP orbs, run XP wiring | 13, 14 | PR up | #4 |
| 08 | Upgrade catalogue + offers (server) + upgrade cards (client, Bottom Row) | 14, 20 | PR up | #5 |
| 09 | Test bots | 18 | PR up | #6 |
| 10 | HUD, minimap + zone display, touch/desktop/controller controls, settings (cards moved to 08, results to 05) | 20 | PR up | #8 |
| 11 | Integration: all pieces merged on one branch, checks green, BlastZone.rbxl | - | PR up | integration PR |
| 12 | Audio: sounds + music (silent until ids are added, see plans/AUDIO-IDS.md) | 22 | PR up | this PR |

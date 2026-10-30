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
| 16 | Performance and stability: leaks, per-frame work, edge-case tests, speed checklist | 16, 23, 26 | PR up | this PR |
| 17 | Saving player progress (DataStore profiles, session lock, once-only grants) | 19 | PR up | this PR |
| 20 | First-time intro, save error messages, release checklist | 7, 25 | PR up | piece 20 PR |
| 18 | Coins + unlock track (looks only) + combined claim strip on the results screen | 19 | PR up | this PR |
| 15 | Phone refinement (floating sticks, pick chips) + full controller support | 20 | PR up | #18 |
| N11 | Original character (3 looks) + animations: move, aim/fire, reload, slide, hit, defeat, victory | 21 | PR up | this PR |
| 21 | Fair spawns: spawn shield + bots calm start | 18 | PR up | #21 |
| 26 | Invite friends: INVITE button (SocialService prompt), friends queued into the host's next match, people take bot seats | - | PR up | #22 |
| 27 | Anti-cheat audit: remote checks, move watch (teleport/speed/fly), reset-to-hide fix | - | PR up | #23 |
| 22 | UI layers: Settings over lobby, one panel at a time, lobby slots, phone-shape spacing | 20 | PR up | piece 22 PR |
| 13 | Combat effects polish: "Sticker Punch" look (muzzle, tracers, hits, numbers, slide, crates, blast warning, camera shake) | 22, 23 | PR up | this PR |
| 24 | Lifetime stats (wins, eliminations, matches), lobby stats card, global top-wins board (Trophy Wall, OrderedDataStore) | - | PR up | #26 |
| 30 | Store page: 3 icon + thumbnail ideas (3D), name ideas, description, upload steps | - | PR up | store PR |
| 25 | Daily challenges: 3 a day (easy/medium/hard), server counts, pay Scrap once, reset at midnight UTC, plain DAILY panel (look comes from the UI system) | - | PR up | daily PR |
| 29 | Emotes in the lobby (12, all free: carter said "all of them") + pick-your-own winner pose on the results screen | - | PR up | own PR |
| 23 | More guns: Breaker shotgun, Hornet SMG, Longline rifle, found in containers (carter picked all 3) | 9, 13 | PR up | see handoff 23 |
| 34 | Account level from run XP + free gifts at milestone levels (Scrap or looks; saved with the profile). Server only: the look of the level screen waits for carter | - | PR up | level PR |

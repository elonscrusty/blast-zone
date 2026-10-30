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
| 22 | UI layers: Settings over lobby, one panel at a time, lobby slots, phone-shape spacing | 20 | PR up | piece 22 PR |
| 17 | Saving player progress (DataStore profiles, session lock, once-only grants) | 19 | PR up | this PR |
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
| 30 | Store page: 6 icon + thumbnail ideas (3D, C1 Showdown picked), name ideas, description, upload steps | - | PR up | #27 |
| 25 | Daily challenges: 3 a day (easy/medium/hard), server counts, pay Scrap once, reset at midnight UTC, plain DAILY panel (look comes from the UI system) | - | PR up | daily PR |
| 29 | Emotes in the lobby (12, all free: carter said "all of them") + pick-your-own winner pose on the results screen | - | PR up | own PR |
| 23 | More guns: Breaker shotgun, Hornet SMG, Longline rifle, found in containers (carter picked all 3) | 9, 13 | PR up | see handoff 23 |
| 31 | UI system for Claude Design: screen list, brief, look/logic split (Ui/Tokens, Skins, Components), import tool | 20 | PR up | UI system PR |
| 38 | Weather: rain only (light/steady/heavy per match), server picks, one cheap emitter, haze on the sky | - | PR up | weather PR |
| 19 | Lobby plaza (3D) + loadout logic; look comes from Claude Design | 7, 20 | PR up | this PR |
| 28 | Second map: D Neon Plaza (carter's pick) + map rotation between matches; E and F kept as extra maps | 12 | PR up | #34 |
| 37 | Gun sounds: Breaker, Hornet, Longline shots, gun drop and gun swap cues (box hit/break already existed); ids left empty | 9, 13 | PR up | gun sounds PR |
| 36 | Kill streak rewards (heal, speed boost) | - | PR up | see PR |
| 32 | Spectate after you die: killer first, camera style (A same / B wide / C close), server-checked targets | PR up | see handoff 32 |
| 33 | Map voting between matches: server counts votes in the lobby, winner picked right before the arena builds (placeholder buttons; look comes from the UI system) | - | PR up | map vote PR |
| 34 | Account level from run XP + free gifts at milestone levels (Scrap or looks; saved with the profile). Server only: the look of the level screen waits for carter | - | PR up | level PR |
| 39 | Idle (AFK) removal, bots top up part-full lobbies, safe server shutdown (pays out, no new matches, saves via #15) | - | PR up | piece 39 PR |
| 35 | Smarter bots: easy/normal/hard tiers, take cover, leave the zone wall early, use found guns (calm start kept) | 18 | PR up | see handoff 35 |
| 14 | City art pass: Neon Night, day to night in one match | 12 | PR up | #42 |
| 40 | Player analytics (match start/end, deaths by cause, onboarding funnel, gun picks; server only) | - | PR up | handoff 40 |
| 41 | Whole-match tests: a pretend server with bots plays full matches (lobby, crates, guns, zone, winner, coins, reset); 4 seam bugs fixed | - | PR up | piece 41 PR |
| 42 | Loot & Heal (video 3 bundle A): carried heal packs (use button), floor loot (packs + found guns that never expire), death drop, bots heal | - | PR up | loot PR |
| 43 | Power Picks (video 3 bundle B): Piercing Rounds, Rapid Fire, Aftershock, Heavy Shell, Long Slide level-up cards | 14 | PR up | power picks PR |
| 46 | Big moments (video 3 gaps 4-6): name plates (name, level badge, health bar, own ring), call-out banners (double kill, spree, circle closing, sudden death), level-up burst; 3 looks A/B/C | 14, 22 | PR up | big moments PR |
| 44 | Turn the camera (bug: the view was locked): mouse right-button drag, touch drag on the free right side, gamepad L2 + right stick; walking, minimap follow the turn | 2, 10 | PR up | handoff 44 |
| 45 | Fast Feet (video 3 bundle C): run toggle with a breath bar, hop low cover with the Slide button, 2 slide charges | 43 | PR up | fast feet PR |
| 46 | Heroes (video 3 gaps #12 + stat cards of #13): 5 original heroes, own health + own two guns, free HERO loadout slot, server-decided, gun stat cards (logic only; looks from Claude Design) | 9, 20 | PR up | heroes PR |
| G19 | Chests with a reveal (video 3 gap 19): free chests from play (1st = Neon, top 3 = Street, every 4th match = Street), odds shown before opening, Scrap or looks only, server rolls and pays in one change, reveal with 3 motion tries | 13, 19 | PR up | chests PR |

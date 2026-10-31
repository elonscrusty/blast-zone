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
| G23 | Ranked ladder (video 3 gap 23): rank points, tiers, warm-up, ranked switch, saved with Profiles; leaving keeps the loss; logic only (screens from Claude Design) | 17, 24 | PR up | ranked PR |
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
| 47 | Street that breaks (video 3 gap list #1, carter picked A "Chunk Burst"): cars, dumpsters, planters, benches, barriers burst from shots and blasts; scorch + rubble stay; chunks fly | - | PR up | street breaks PR |
| 46 | Big moments (video 3 gaps 4-6): name plates (name, level badge, health bar, own ring), call-out banners (double kill, spree, circle closing, sudden death), level-up burst; 3 looks A/B/C | 14, 22 | PR up | big moments PR |
| 44 | Turn the camera (bug: the view was locked): mouse right-button drag, touch drag on the free right side, gamepad L2 + right stick; walking, minimap follow the turn | 2, 10 | PR up | handoff 44 |
| 45 | Fast Feet (video 3 bundle C): run toggle with a breath bar, hop low cover with the Slide button, 2 slide charges | 43 | PR up | fast feet PR |
| 46 | Heroes (video 3 gaps #12 + stat cards of #13): 5 original heroes, own health + own two guns, free HERO loadout slot, server-decided, gun stat cards (logic only; looks from Claude Design) | 9, 20 | PR up | heroes PR |
| 48 | Big map (video 3 gap 8): tap the minimap (or M, pad Y) to see the whole arena, the safe circle, the next circle and you; one tap closes it; the game keeps running (logic only; look from Claude Design) | 10, 44 | PR up | big map PR |
| 47 | 25 fighters (video 3 gap 9): matches fill to 25 with bots; map, circle and match clock stretch with one number (`Config.Arena.scale`); one spawn per fighter and more crate points on every map; 24 bot names; bots think slower when crowded; Max Players 25 | 9, 21 | PR up | handoff 47 |
| G20 | Season pass (video 3 gap 20): 14-day seasons, 20 tiers, free row + paid row, season XP from every match, TAKE / TAKE ALL (looks and Scrap only; the paid row is not for sale yet; logic only, look from Claude Design) | 18, 34 | PR up | season pass PR |
| 48 | Gear slots (video 3 gap #15): head, body, feet; 3 pieces each (one free), small trades not power, server-decided, saved in the loadout; logic only, looks from Claude Design | 19, 46 | PR up | gear slots PR |
| G24 | Game modes (video 3 gap 24): lobby vote for a mode (Classic, Quick Blast, Loot Rush; Last Stand ready but off), padlock by account level, server applies the winner's tuning at Spawning and puts it back after (logic only; looks from Claude Design) | - | PR up | game modes PR |
| V3-18 | Scrap Shop (video 3 gap 18): SHOP lobby button with a new dot, 2 always-on + 4 daily looks (slide trails and shot tracers) bought with Scrap, server checks stock/price/ownership, no Robux, no random buys (logic only; looks from Claude Design) | 18, 25 | PR up | shop PR |
| V16 | Power rating (video 3 gap #16): one show-off number from level, looks owned, wins, eliminations, matches; each part capped; server-made, sent to its owner only; logic only, no screen | 20 | PR up | power rating PR |
| V14 | Bench (video 3 gap #14): parts drop after a match, 3 of a part merge into 1 of the next tier (4 tiers), plans (blueprints) build gear looks from parts; server decides, saved with the profile; BENCH panel logic only | 20 | PR up | bench PR |
| AD | Airdrop with a light beam (video 3 gap #3): a crate falls into the circle 2 times a match, a tall beam shows where, it opens after a short wait and drops a found gun, heal packs and XP orbs; server picks time, spot and loot; hint strip with arrow and distance (logic only) | 7, 42 | PR up | airdrop PR |
| V11 | Squads (video 3 gap #11): Solo/Duo/Trio vote, friends then people then bots seated together, no friendly fire, last squad standing wins and shares the place (logic only; looks from Claude Design) | 9, 20 | PR up | squads PR |
| 48 | Missions + login days (video 3 gaps #21 + #22): 3 weekly missions + week bonus, 19 achievements, 7-day login row; claim buttons, server counts and pays once (logic + placeholder MISSIONS panel; looks from Claude Design) | - | PR up | missions PR |
| SL | Night traffic (video 3 gap #2, carter picked A Cars): glowing hover-cars loop the roads of every map, cut around solids, brake when shots go off, fade near you; show only, server sends the road stretches (looks need no Studio test; logic tested) | 4, 14 | PR up | night traffic PR |
| G19 | Chests with a reveal (video 3 gap 19): free chests from play (1st = Neon, top 3 = Street, every 4th match = Street), odds shown before opening, Scrap or looks only, server rolls and pays in one change, reveal (carter picked A Lid Pop; B, C kept as skins) | 13, 19 | PR up | chests PR |
| W1 | Whole-game wiring check: a test reads the source and fails if a System has no start, a client ask has no (or two) server handlers, a server message is never sent or never heard, a remote goes the wrong way, or anything but the match flow loads characters. Fixed the two unheard messages (hop streak now shows on other players; PickupSpawned heard) | - | PR up | wiring PR |
| G17 | Counter bar (video 3 gap 17): Scrap + Stars (earned by winning/podium, saved in `data.wallet`), server `grant`/`spend` for a shop or chest piece, placeholder bar top right (logic only; looks from Claude Design) | 18, 17 | PR up | counter bar PR |
| A1 | Whole-game audit to 7/10: fuzz of 240 matches clean; bot bodies built once and cloned (no 24 slow calls per match); bots with no body are taken out so a match cannot hang; new mixed-seed full-match test | - | PR up | audit PR |
| V29 | Richer results card (video 3 gap #29): things broken, crates opened, powers picked, counted by the server and shown on your own results (logic + one placeholder line; looks from Claude Design) | 5, 47 | PR up | results card PR |
| FEEL1 | Video feel pass 1 (carter: "like the video"): camera 2x closer, run 20 -> 11 studs/s (plaza walk keeps 20), slide 9, guns and bot sight scaled to match; no new features | 2, 3, 9 | PR up | feel pass 1 PR |
| PA | Phone audit + lobby walking: UI is laid out again whenever the phone turns or the screen size changes (a phone starts upright, so the lobby came out 5x too small and piled at the bottom); new `tests/phone_audit.test.luau` lays lobby / fight / pick chips / spectate out on 13 real phone shapes with notch, home bar, Roblox's own top-bar buttons and both hands, and fails on any overlap, off-safe-area piece or tiny button; every ScreenGui must be listed in it; you can walk in the lobby (stick works anywhere between buttons) | - | PR up | phone audit PR |

# Video 3 gaps: what the video has that our game does not

Research only. Nothing here is built. Checked 2026-10-30 against main (`e26c67a`, after PR #50).

How it was checked: the whole video (4 min) was sampled every 3 seconds and the match, menu and results moments were studied at full size. Then compared with `plans/NEXT-PIECES.md`, `plans/handoffs/`, `plans/UI-SCREENS.md` and `src/`.

Rules for this list: our game is original. Gaps are written as general features. We never copy that game's names, heroes, maps, numbers, art or UI. Look only (UI is Claude Design's job).

Not judged: **sound**. Frames cannot tell what the video sounds like. Someone should listen and add notes.

Status key: **in progress** = a thread is on it, **missing** = nothing exists yet, **partly** = we have a small version.

## Already handled (do not list as missing)

| What the video shows | Status |
| --- | --- |
| Neon night look, trees, props, chunky city | in progress (look + props passes) |
| Name plates, big call-out banners, level-up burst (gaps 4, 5, 6) | in progress (Big moments, piece 46) |
| Healing packs on the street, carried and used on a button | done (#50) |
| Guns lying on the street | done (#50) |
| Big level-up powers (rocket blast, piercing, double barrel...) | in progress (Power Picks) |
| Sprint / hop low walls / more slides | in progress (Fast Feet) |
| Camera turning | in progress (being fixed) |
| Lobby layout | in progress (fix) |
| Level-up with 3 cards, shrinking circle (red on map), sudden death, kill-streak call-outs, minimap, kill feed, countdown, slide, crates, 2 gun slots, victory pose, daily jobs, top-wins board, map vote, spectate, weather, day-night | we have these (small versions) |

## Gaps: in the match

| # | Gap (general idea) | What the video shows | Ours today | Size |
| --- | --- | --- | --- | --- |
| 1 | **Street that breaks** (**done, piece 47**) | Parked cars, fences, bins burst into pieces and leave rubble. Dashing and blasts kick up debris. Results count "things broken". | Static props. Slide and blasts break nothing. | M |
| 2 | **Street that lives** | Ambient traffic, wandering bystanders who run from fights, roaming guards or hazards near the edge. Makes the city feel busy. (Keep bystanders harmless: Roblox rules, kids.) | Empty streets. | M-L |
| 3 | **Airdrop with a light beam** | A tall beam of light marks a falling loot box, everyone sees where to run. | Crates sit in fixed spots, no event. | S-M |
| 4 | **Always-on name plates** | Every fighter has a name, a health bar and a small level badge over the head. Your own has a green ring under the feet. | Enemy bars show for a few seconds after a hit. No badge, no ring. | S |
| 5 | **Big moment banners** | Large banner with an emblem for double kill, killing spree, "invincible" at sudden death, circle closing. | Plain text notices ("DOUBLE! +15 HP"). | S |
| 6 | **Level-up celebration in the world** | Burst, big arrow over the hero, star emblem, then the 3 cards. | Cards only. | S |
| 7 | **Bodies stay** | Fallen fighters lie on the street for a while. | Already true: a fallen fighter is held where they fell with the defeat pose until the match ends (`CharacterSetupSystem`, bots' rigs are only removed at match end). Found while building piece 47; not yet seen in play. | - |
| 8 | **Expandable big map** | Tap the minimap to open a full-screen map. | Small round map only. | S |
| 9 | **Bigger fights** | 25 fighters, about 4 minutes. | Built for about 8 (bots fill). Needs map size, spawn, perf and bot checks. | L |
| 10 | **Heavier weapon effects** (props now burst; the big blast look still follows Power Picks) | Purple tracer for the big weapon, huge blast flash, rocks and sparks when something is hit. | Shots, hit sparks, shake exist. No big-blast look yet. | S-M (follows Power Picks) |
| 11 | **Squads (duo/trio)** | Title says team mode; party chat invites "anyone up for a duo?". | Solo only. carter's brief is solo, so this is optional. | L |

## Gaps: heroes and gear

| # | Gap | What the video shows | Ours today | Size |
| --- | --- | --- | --- | --- |
| 12 | **Heroes with real differences** | A roster strip of 5+ heroes. Each has health and its own two guns. | 3 looks, all the same stats (looks only). **Piece 46 builds the logic** (5 heroes, health, 2 guns each, stat cards); looks wait for Claude Design. | L |
| 13 | **Gun upgrade cards** | Each gun shows damage, range, fire rate and a small progress bar to upgrade it. | Guns are fixed. | M |
| 14 | **Blueprints / merge screen** | Collect parts, merge into better gear. | Missing. | L |
| 15 | **Gear slots** (head, body, feet...) | Equipment grid. | Piece 48 builds the logic (3 slots, small trades, free to earn). Looks wait for Claude Design. | M |
| 16 | **Power rating** | One number for how strong your gear is. | Missing. | S |

(Careful with 13-16: keep them looks and soft perks, never Robux power. Same rule as levels, #34.)

## Gaps: menus, flow, progression

| # | Gap | What the video shows | Ours today | Size |
| --- | --- | --- | --- | --- |
| 17 | **Currency bar** | Top bar: several counters (coins, cash, energy, gems, tickets) and a bag. | One currency (Scrap). | S |
| 18 | **Shop** | Store button with a red "new" dot. | No in-game shop yet (no Robux ids, by rule). | M |
| 19 | **Chests with a reveal** | Open a chest, items pop out, "tap to continue". | Missing. | M |
| 20 | **Seasonal pass** | Pass with free and paid rows, progress bar. | Missing (we have a Scrap unlock track). | L |
| 21 | **Missions, weeklies, achievements** | Tabs: dailies, weeklies, achievements, each with Claim buttons and a bonus meter. | 3 daily jobs only. | M |
| 22 | **Daily login rewards** | Row of days, today's glows. | Missing. | S |
| 23 | **Ranked ladder** | Stars to reach, tiers, qualification bar, ranked mode toggle. | Top-wins board only. | M-L |
| 24 | **Game modes and map picker** | Mode list, some locked with a padlock, map preview. | Map vote exists. One mode. | M |
| 25 | **Matchmaking waiting room** | Grid of "finding player" slots that flip to READY with names. | Lobby plaza and bot top-up, no visible slot grid. | S-M |
| 26 | **Friends and party** | Chat bubble, duo calls, invite. | Invite button exists. No party, no chat (chat stays Roblox's own). | M |
| 27 | **"New feature" tutorial pointer** | Dimmed screen, pointer on the new button, "tap to continue". | First-time intro of 4 tiles. | S |
| 28 | **Energy limit** | Energy counter that gates play. | None. Not recommended for kids; skip unless carter wants it. | - |

## Gaps: results and polish

| # | Gap | What the video shows | Ours today | Size |
| --- | --- | --- | --- | --- |
| 29 | **Richer results card** | "YOU RANKED #1", hero posing in 3D, list: kills, crates opened, powers picked, things broken, time. | Place, kills, time, reward, winner pose. | S |
| 30 | **Hero outline + ground ring** | Thin dark outline, glowing trim. | Planned in the look plan, waits for carter's pick. | S |
| 31 | **Lobby cyan grid + stars** | Glowing grid floor, starry sky behind the hero. | Planned in the look plan. | S |

## Top 3 to start (best value for effort)

1. ⭐ **#1 + #7 + #10 "Street that breaks"**: props burst, rubble, bodies stay. The world reacts to you. Makes every shot feel good.
2. ⭐ **#4 + #5 + #6 "Big moments"**: name plates with ring, big banners, level-up burst. Small, all feel.
3. ⭐ **#12 + #13 "Different heroes"**: each hero its own health and guns, gun cards. Big reason to come back.

Next after those: #21 + #22 (missions and login days), #3 (airdrop), #9 (25 fighters).

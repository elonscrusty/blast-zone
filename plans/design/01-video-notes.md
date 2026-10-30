# Phase 1 + 2: What the video shows, and why it is fun

Source: `video.mp4`, a 4:03 screen recording of a browser game ("Gridpunk - 3v3 Battle Royale" on CrazyGames). We only learn mechanics and feel from it. Nothing from it is copied into Blast Zone.

How the frames were read: one frame every 6 seconds, plus a few sharp close-ups. Anything that happens faster than 6 seconds (shots, dodges, kills) was seen only when it landed on a frame. `[INFERRED]` marks a guess.

## Phase 1: Timestamped log

| Time | What the player does | What is on screen |
| --- | --- | --- |
| 0:00 | Sits in the lobby, hero tab open | Hero row (5 heroes, one selected, "20 trophies" on it). Hero card: LEVEL 1, HP 2400. Three weapon cards: gun 41 dmg / 5.8 shots per sec / range 16, rocket launcher 488 dmg / 1.4 per sec / range 18, ability 244 dmg / range 15 / 45. Each card shows weapon level 1 and `0/20` (upgrade progress). Top bar: coins 5200, cash 30, energy 150/150, X 10, gems 10, map tickets 180/200 with a refill timer (2:21:01). Shop button with a red dot. Player level 22. |
| 0:06 | Taps VS, then picks a map | "1. Sentinel Park" map picture. Mode row: 8 mode icons, 7 locked. "Ranked Match" tick box. Big FIGHT button with an energy cost (8). Side list: ranking "Reach 60 stars" with chest steps at 20/40/60 and a top 10 list (57, 47, 42 ... 0 stars). |
| 0:12 - 0:18 | Waits | Matchmaking board: tiles flip from "FINDING PLAYER" to "READY" with a small face and name. About 25 tiles fill in ~6 s. `[INFERRED]` many of the names are bots. |
| 0:24 | Match starts | Top-left: rank badge `#0`, `Players: 0/25`. Top-down 3/4 camera, park map, a pink loot box on the grass. Bottom-left: weapon-level number `1`, thin XP bar under the screen. |
| 0:30 | Lands in the fight | `#25 Players: 25/25`. Banner ENTERING COMBAT when near an enemy. Floating damage number `82`. Round minimap top-right with a green circle. |
| 0:36 - 0:42 | Shoots | Big yellow burst + number `488` (rocket hit). Numbers show every hit. |
| 0:48 - 0:54 | Fights, kills | Kill feed (names + gun icon) top-left. `#23 -> #19` players left. |
| 1:00 | Zone | `#18 Players: 16/25`, banner CIRCLE CLOSING! Red area appears on the minimap edge. |
| 1:06 | Reloads | Word RELOADING in the middle of the screen. Weapon icon bottom-right shows a counter (5 = ammo or cooldown). |
| 1:42 | Perk | `#11` pop-up card "Movement speed" at level 3 -> 4. |
| 1:48 | Streak | Banner MULTI KILL with a skull badge. |
| 1:54 | Level up | LEVEL UP banner. Three cards: Double Rockets / Damage / Cooldown. Player picks one. Level shown bottom-left: 5. |
| 2:06 | Level up again | New three cards: Nuclear Rocket / Plasma Bullets / Cooldown. Level 6. |
| 2:12 | Crit | Huge number `789`. |
| 2:24 | Streak | Banner MASSACRE. Red danger band on the ground = zone edge. `#6`. |
| 2:54 | Streak | Banner INVINCIBLE with skull badge. `#3`. |
| 3:12 | End | Banner SUDDEN DEATH at 2 players left, fight moves indoors (pool table room). |
| 3:24 | Match over | Screen blurs, loading logo. |
| 3:30 | Back in lobby | Hero XP bar `50/40` (full) with level 2. |
| 3:36 | Reward tally | Coins fly into the top bar (+30 coins, "Qualifications" progress, "Punk Pass" +45). |
| 3:42 | New feature pop-up | "Missions" icon unlocks. |
| 3:48 | Dailies panel | Timer "Refresh in 12m 25s". Ladder of chests at 20/40/60/80/100 points (first two ticked). Quests: Upgrade equipment 1 time, Play with friends, Buy 1 item from hero's Daily Shop, Claim Hacking earnings 3 times, Quick Hacking 2 times. Each gives x10 points. Tabs: Daily Rewards, Dailies, Weeklies, Achievements. |
| 3:54 | Achievements | Cash rains down. Rewards x10 cash for tasks like "Reach hero's Power Level 2", "Open 5 chests", "Spend total of 1000 cash". |
| 4:00 | Lobby | Coins now 20.6K (was 5.2K), cash 140 (was 30), energy 138/150. Locked tiles (First Purchase, Hacking, Challenges, Growth, Monthly), Total Power 23, Quests, Punk Pass bar, Start-time 7:00 PM event. |

Number changes seen: energy 150 -> 138 for one match `[INFERRED: the FIGHT cost]`; coins rose a lot in one tally, but the 6-second sampling can't show the exact payout; players left fell from 25 to 2 in about 3 min 10 s (about one elimination every 8 s).

## Phase 2: Breakdown

### 1. Core loop (about 3 minutes per run)
**Fight -> loot/kill -> level-up card -> stronger gun/rocket -> fight.** Spend it as: pick up boxes and kills give XP -> each level gives 3 cards -> pick one -> the next fight is easier.

### 2. Meta loop (hours)
Win coins/trophies -> upgrade heroes and weapons (cards like `0/20`) -> unlock heroes, maps and modes (7 of 8 modes are locked) -> chase ranking stars, daily chest ladder, Punk Pass, events.

### 3. Progression curve (honest limits)
We only saw level-1 numbers, so the curve is `[INFERRED]`.
- Weapon damage: gun 41, rocket 488, ability 244. Rocket = 11.9x the gun hit, with 1/4 the fire rate. So the rocket is a "pop" and the gun is the "stream".
- Upgrade need `0/20` at level 1. A level 2 card needing a different number would tell us the shape; we never saw one. We assume a stepped curve (more cards needed each level).
- Daily ladder: 20/40/60/80/100 points. Evenly spaced (linear), 10 points per quest, so 2 quests per step.
- In-match level: 5 levels by about 1:54 (about 25 s per level, falling off). `[INFERRED]` linear XP needs.

### 4. Pacing
| Moment | When |
| --- | --- |
| First reward (a loot box in sight) | Under 10 s into the match |
| First fight | About 30 s |
| First level-up card | About 1:40 |
| First "wow" (big crit, banner, streak) | About 1:48 |
| First upgrade chance (after the match) | About 3:36 |
| New feature unlock | 3:42, one match in |

### 5. Game feel
- Camera: high 3/4 top-down, character always centered, wide view, a minimap for the rest.
- Movement: fairly quick, no jump. A green ring under the player marks "you".
- Hit feedback: every hit makes a big white-yellow number. Crits are huge. Explosion flash and little star bursts.
- Banners: ENTERING COMBAT, MULTI KILL, MEGA KILL, MASSACRE, INVINCIBLE, LEVEL UP, CIRCLE CLOSING, SUDDEN DEATH. Big italic, slides in, dark shadow.
- Reload word in the middle of the screen. Cooldown ring on ability buttons.
- Sounds `[INFERRED]`: shots, explosions, "ding" on kill, banner stingers. Not testable from silent frames.

### 6. Visual style (general only)
Bright cartoony low-poly city (parks, streets, cars, houses with interiors). Warm daylight, saturated greens and oranges. Characters have big heads and chunky clothes. The menu is a dark neon blue "arcade grid" with glowing yellow buttons. Busy but readable: bright ground, dark HUD frames.

### 7. UI jobs
| Screen | Job |
| --- | --- |
| Top currency bar | Show money, energy, gems, tickets. Every one has a "+" to buy. |
| Hero tab | Pick a hero, see HP and weapons, upgrade weapons. |
| VS / mode screen | Pick map and mode, show ranking, start match. |
| Matchmaking board | Show that others are joining (reduces waiting boredom). |
| Match HUD | Players left, own rank, minimap with zone, ammo/cooldown buttons, heal, XP bar, kill feed. |
| Level-up cards | Choose 1 of 3 boosts. |
| Reward tally | Show coins flying in. |
| Dailies / Weeklies / Achievements | Give a reason to come back, with a chest ladder. |
| Shop | Sell things (red dot invites a tap). |

### 8. Monetization and retention hooks seen
Energy that refills with a timer, "Don't lose progress, log in" nag, battle pass ("Punk Pass"), chest shop with a red dot, first-purchase offer, timed event ("Start time 7:00 PM"), daily/weekly/achievement lists, friend invite button and "play with friends" quests, ranking with star chests, locked modes that tease what comes later.

### 9. Good and weak
Strongest 3
1. A match is short and every 8 seconds someone is out, so something always happens.
2. Level-up cards make each run feel different, and the numbers are huge and satisfying.
3. The loop outside the match (dailies ladder, hero upgrades, ranking chests) always shows "the next thing".

Weakest 3
1. Energy cost stops play when you want to keep playing (bad for kids).
2. Many menu parts are locked or red-dotted, so the lobby is cluttered.
3. On a phone, the HUD would be tiny. It was designed for a mouse and keys (Q, Space, Tab, mouse buttons).

# Phase 3: Blast Zone, the original design

Working name: **Blast Zone** (carter picked it, may change).

## Premise
You are a wind-up toy bot in a giant playroom. 16 bots drop onto the floor. The floor itself blows up piece by piece (the **Blast Waves**). Last bot standing wins. Your bot is upgraded between matches.

## What we keep from the genre (structure only)
Short top-down battle royale, a closing danger area, pick-ups, level-up cards in the match, big hit numbers, banners, hero + weapon upgrades, daily chest ladder.

## Our twists (what makes it ours)
1. **Blast Grid.** The danger area is not a circle. The floor is a 5x5 grid. Chosen squares flash for 8 s, then blow up and become pits. Everyone can see which squares are next, so the fight is about where to stand, not just running to the middle.
2. **Ghost Pokes.** Out of the match? You are not stuck watching. You become a ghost and can tap the map once every 25 s to drop a small bomb marker (3 s warning). Players can dodge it. Keeps dead phones busy and makes the end loud.
3. **Smashable toy blocks.** Cover is built of toy blocks and crates. Rockets break it. Red barrels chain-explode.
4. **Bots fill every match.** A match can start with one human; empty slots get bots with funny names so the lobby is never empty.

## Would a player of the source game call this a copy?
They would see the same *kind* of game (top-down battle royale with level-up cards), which is the brief. But the world (toy room, wind-up bots), the danger area (a grid of blasting floor tiles, not a circle), the ghost mechanic, the smashable blocks, the no-energy rule, the names, the art and the UI all differ. No character, weapon name, map, UI layout or text is reused. If we notice any of those leaking in, we change it. Answer: no, it is a different game in the same genre.

## Art direction (3 tries, carter picks one, the others become skins)
All three share the same rules and the same low-poly style. Only palette, props and mood change.
| Try | Setting | Mood | Palette |
| --- | --- | --- | --- |
| A ⭐ **Toy Room** | Playroom floor, block towers, toy cars, rug, crayon walls | Happy, bright, readable on a small phone | Sunny yellow floor, candy red/blue/green blocks, soft cream |
| B **Junkyard Rumble** | Scrapyard of old machines, tyres, cranes | Gritty-fun, loud | Rust orange, teal lights, dark grey |
| C **Sky Blocks** | Floating pastel islands made of blocks | Calm, dreamy, high contrast edges | Pastel pink/mint/sky, white clouds |
Why A is the star: the floor is bright, so bots and bullets pop; kids know toys; it is the cheapest to build with plain parts.
Shapes: chunky, rounded, big heads. No thin details (they vanish on a phone). Bots have a big wind-up key on the back.

## UI design (mobile first)
- Portrait is not used. **Landscape**. Safe-area padding.
- Left thumb: move stick (bottom-left, 140 px). Right thumb: aim stick (bottom-right). Pushing the aim stick fires the blaster.
- Buttons (each at least 72 px, with 16 px gaps): **Boom** (heavy), **Roll** (dodge), **Fix** (heal, shows count). The blaster is the aim stick, so there is no swap button.
- Top-left: place and players left. Top-right: round minimap with the grid and the next blast squares. Top-middle: banners.
- Bottom edge: XP bar with level.
- PC: WASD, mouse aim, click = blaster, E = Boom, Space = Roll, Q = Fix, Tab = map. Touch is the main design; keys are extras.
- Lobby: big FIGHT button in the middle-right, hero strip on the left, currency bar on top (3 numbers only). Nothing locked is shown as a clutter; locked things are hidden until they matter.

## Match rules (numbers are first guesses, all in `Config/`)
| Item | Value |
| --- | --- |
| Players per match | 16 (humans first, bots fill) |
| Lobby wait | 20 s, then 5 s countdown |
| Match length | about 3:30, hard cap 4:00 |
| Map | 300 x 300 studs, 5x5 squares of 60 |
| Blast schedule | 0:40 (4 squares), 1:15 (5), 1:45 (5), 2:15 (4), 2:40 (3), 3:05 Sudden Death (all but 1) |
| Warning time | 8 s flash, then BOOM |
| Pit damage | 8% of max HP per second |
| Ghost Poke | cooldown 25 s, 3 s warning, radius 12, 300 damage |

### Heroes (v1: 3, the rest of the roster comes from skins)
| Hero | HP (level 1) | Speed | Feel |
| --- | --- | --- | --- |
| Wobbles | 1000 | 16 | Balanced, free |
| Spark | 800 | 18 | Fast, fragile, 400 cogs |
| Bruno | 1400 | 14.5 | Tough, slow, 1200 cogs |
Hero level 1-10: +6% HP each level.

### Weapons (everyone has all three; levels are per weapon)
| Slot | Name | Damage | Rate | Range | Extra |
| --- | --- | --- | --- | --- | --- |
| 1 | Pop Blaster | 24 | 4.5 shots/s | 40 | 24 ammo, reload 1.6 s, projectile 120 studs/s |
| 2 | Boom Cannon | 220 (splash radius 9, half damage at the edge) | cooldown 6 s | 55 | projectile 70 studs/s, breaks blocks |
| 3 | Zip Roll | 0 | cooldown 5 s | 12-stud dash | 0.35 s untouchable |
| Heal | Fix-it Kit | heals 35% max HP over 2 s | carry max 3, start with 1 | | |
| Shield | Bubble | absorbs 150 | pick-up only | | |
Weapon level 1-10: +8% damage per level. Crit: 10% chance, x2 damage, bigger number.

### In-match XP and perk cards
XP to next level: 40, 60, 85, 115, 150, 190 (max level 7). Kill = 50 XP. Chest = 40. Smashed block = 5.
Each level-up shows 3 random cards (8 s to choose, else a random one):
| Card | Effect (stacks to 3) |
| --- | --- |
| Twin Boom | Cannon fires 2 shells |
| Hot Shots | +15% all damage |
| Quick Fuse | -20% cooldowns |
| Zoomies | +10% move speed |
| Big Bang | +25% splash size, +20% cannon damage |
| Zap Pops | Blaster hits chain 30% damage to the nearest bot within 8 studs |
| Thick Skin | +12% max HP and heal that amount |
| Quick Hands | -30% reload |
| Magnet | pick-up range x2 |

### Loot
14 Toy Chests at fixed spots at the start. Contents (shown on the ⓘ in the lobby too):
| Item | Chance |
| --- | --- |
| Fix-it Kit | 35% |
| Bubble | 20% |
| XP burst (+40) | 25% |
| Quick reload (10 s) | 10% |
| Match cogs (+15) | 10% |
A kill has a 30% chance to drop a Fix-it Kit.

### Rewards after a match
| Place | Cogs bonus | Trophies |
| --- | --- | --- |
| 1 | 150 | +30 |
| 2 | 100 | +20 |
| 3 | 70 | +12 |
| 4-5 | 40 | +5 |
| 6-8 | 20 | 0 |
| 9-12 | 0 | -5 |
| 13-16 | 0 | -10 |
Plus 30 cogs for playing and 12 cogs per kill. Trophies never drop below 0, and nobody loses trophies until they have 50. Hero XP = 40 + 8 per kill + seconds survived / 5.

### Upgrade costs (cogs only in v1)
| Level | Weapon cost (50 x 1.5^(L-1)) | Hero cost (100 x 1.55^(L-1)) |
| --- | --- | --- |
| 1 -> 2 | 50 | 100 |
| 2 -> 3 | 75 | 155 |
| 3 -> 4 | 110 | 240 |
| 4 -> 5 | 170 | 370 |
| 5 -> 6 | 255 | 575 |
| 6 -> 7 | 380 | 895 |
| 7 -> 8 | 570 | 1385 |
| 8 -> 9 | 855 | 2150 |
| 9 -> 10 | 1280 | 3330 |

### Chests (after matches)
You earn a Toy Chest for every top-3 and for every 3rd match. Opening is instant. Odds are shown **before** it opens (tap ⓘ).
| Content | Chance |
| --- | --- |
| Cogs 40-80 | 55% |
| Cogs 150-250 | 20% |
| Gems 3-8 | 15% |
| Hero card (progress to unlock a locked hero) | 8% |
| Emote | 2% |
Gems are only earned in v1. Nothing is sold for Robux until carter gives real product ids.

### Dailies
3 daily tasks (play 2 matches, 3 kills, open 1 chest), 10 points each. Ladder at 10/20/30 points: 60 cogs, 3 gems, a chest. Refreshes every 24 h (UTC midnight). A 7-day login streak (cogs 50, 50, 75, 75, 100, 100, chest).

### First 30 minutes (what the player sees)
Assume a new player who improves a little each match. Welcome gift: 100 cogs.
| Minute | Event | Cogs gained | Cogs left after spending | What they buy |
| --- | --- | --- | --- | --- |
| 0 | Welcome gift, tutorial upgrade | +100 | 50 | Pop Blaster 1 -> 2 (-50): first upgrade in minute 1 |
| 5 | Match 1: 10th place, 0 kills | +30 | 30 | Boom Cannon 1 -> 2 (-50) |
| 10 | Match 2: 8th, 1 kill | +62 | 17 | Pop Blaster 2 -> 3 (-75) |
| 15 | Match 3: 6th, 2 kills, first chest (about 65) | +74 +65 | 81 | Boom Cannon 2 -> 3 (-75) |
| 20 | Match 4: 5th, 2 kills | +94 | 65 | Pop Blaster 3 -> 4 (-110) |
| 25 | Match 5: 4th, 3 kills, daily ladder (60) | +106 +60 | 231 | saving |
| 30 | Match 6: 3rd, 3 kills, chest (about 65) | +136 +65 | 432 | Spark costs 400, so the first hero unlock lands at minute 30 |
Trophies after 30 min: about 22. First "wow": a big crit and banner by about 1:30 of match 1.

### Roblox-native extras (v1 and next)
- v1: leaderboard of top trophies (OrderedDataStore, refreshed every 60 s).
- v1: friends see each other in the lobby list; join friend (Roblox native).
- Later: squads of 3 (party teleport), private servers, trading emotes.
- Monetization ideas only (no ids, no prices, nothing is sold yet): 2x cogs pass, bigger chest slot, extra hero. All hidden behind `Config/Products.luau`, where ids are `nil` until carter supplies them.

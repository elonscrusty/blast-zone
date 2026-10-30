# Assumptions

Labels from the brief: OBSERVED (seen in the recordings), INFERRED (plausible, unconfirmed), PROPOSED (our own decision).
Only carter's brief is the reference; nobody here watched the recordings. All numbers live in `src/shared/Config.luau`.

## OBSERVED (from the brief's evidence notes)
- Solo last-survivor match, 25-player counter. Elevated angled camera. Destructible purple containers. Three-card upgrade offers.
- A named Slide ability. A red boundary that shrinks. "Sudden death" with two left. Results screen with rank and stats.
- Not shown: a 3v3 match, whether others were humans or bots, any combat in the hub recording.

## PROPOSED (our decisions, all changeable in Config)
| Question (brief §4) | Decision |
| --- | --- |
| 1-2 Firing and aim | Desktop: mouse aim + click. Mobile: right-stick aim/fire. Controller: right stick + trigger. No auto-lock. |
| 3 Speed, camera | 20 studs/s. 55 degree pitch, distance 62, FOV 55, fixed heading. No jumping. |
| 4 Weapon | Volt Pistol: 10 damage, 5 shots/s, 12 rounds, 1.2 s reload, range 70, 100 health. Arc Mortar later (off by default). |
| 5 Slide | 14 studs in 0.25 s, 5 s cooldown, no invulnerability, stops at walls. Stationary: slides the way you face. |
| 6 XP | Container break 5, orb 5, elimination 30. Level costs 20, 35, 55, then +25 each. Max 6 offers per match. |
| 7 Upgrade stacking | Piece 08 decides; stats are always computed from base + stacks, never by multiplying a running value. |
| 8 Offer safety | Match keeps running while cards are shown. No invulnerability. Extra offers queue (max 3). |
| 9 Zone | First warning at 35 s. 4 stages (radius 156 > 105 > 68 > 38 > 14), then sudden death at 170 s (radius 4, 25 damage/s). About 3 minutes. |
| 10 Roster | Humans plus clearly labeled "[BOT] " fill. Bots follow player rules, no hidden advantage. |
| 11 Teams | Not in v1. |
| 12 Fairness | Everyone starts with equal stats. Permanent power is not built. |
| 13 Saving | Not in v1 (Phase 5). `Config.Rewards.persist = false`. |
| 14 Defeat | Eliminated players see a defeat summary and spectate. Join mid-match: spectate until next match. Disconnect: eliminated, no killer credit. Simultaneous final elimination: draw, both rank 1 (window 0.1 s). |
| 15 Audio and shake | Original, set by piece 10. Camera shake can be turned off. |

## Rules chosen for tricky cases
- Walls and solid cover block shots. Low cover and fences block movement only. Roofs are visual only.
- Explosions hurt the owner at 50% and do not pass through walls.
- XP orbs are exclusive: first valid claim within 5 studs wins. They last 25 s. The 9-stud pull is cosmetic only.
- Disconnected attacker: kills already credited stay; bullets still in flight are removed.
- Zone damage has no killer credit. A player exactly on the edge counts as inside.
- Late hits after the match leaves combat are dropped by the damage door.
- Game name "Circuit District" is a placeholder; rename in `Config.Game.Name` (and the place name in Roblox).

## Not decided yet (owners to record here)
- Exact upgrade list and weights (08). Final arena layout (04). Bot behavior details (09). Controller button mapping (10).

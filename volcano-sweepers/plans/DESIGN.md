# Volcano Sweepers — game design (one-shot build)

carter's ask: an original Roblox game in the *feel* of Moon Sweepers (Steam, Oct 2026: up to 16 friends
clean a huge dirty place with a tiny tool, sell what they gather, buy better tools). We build our own
take. Never copy that game's name, art, text or layout. Fun for all ages, satisfying, many upgrades,
seamless phone-first UI, target 8/10 across the whole game.

Working title: **Volcano Sweepers**. Placeholder name only; keep it in `Config.Game.Name`.

## One line
A friendly cartoon volcano island is buried in glowing ash. You and up to 15 friends sweep it clean,
sell the ash, upgrade your gear, dodge the volcano's silly burps, and find hidden treasure.

## Why it will be fun (the three loops)
1. **Moment (3 s):** swing → ash puffs away → numbers pop → backpack bar climbs. Every swing must feel
   good (puff, little camera nudge, tick sound hook, "+5" float text, ground colour revealed).
2. **Trip (30–60 s):** fill the backpack → run to the Trade Hut → SELL (coins fly to the counter, big
   satisfying cha-ching moment) → spend → go again stronger.
3. **Session (10+ min):** unlock gates to new zones with richer ash, climb tool tiers, find treasure for
   the Finds Book, help the whole island reach clean milestones (everyone gets a party), then Cool Down
   (prestige) for permanent Sparks. The volcano never lets the island stay clean, so there is always more.

## World
Round island, volcano in the middle. Flat walkable ground (no terrain editing; all built from Parts at
runtime by the server). Five zones in rings from the outside in. Each zone has its own ground colour,
decor, and ash value. A gate (sign + ProximityPrompt) sits at each ring edge.

| # | Zone | Ash value per unit | Look |
|---|------|-------------------|------|
| 1 | Sunny Beach | 1 | sand, palms, shells, waves; the hub + Trade Hut + spawn live here |
| 2 | Fern Forest | 3 | green, big ferns, mushrooms, fireflies |
| 3 | Hot Springs | 8 | steamy blue pools, pink rocks, bubbling |
| 4 | Crater Rim | 22 | red rock, bone-white spires, glowing cracks |
| 5 | Lava Heart | 60 | black glass floor, lava pools (decor, never kill), floating embers |

Ash lives in a grid of cells (see CONTRACTS). Each cell holds 0–9 "ash units". Every zone starts mostly
full. Sweeping removes units. The volcano and a slow regrow put units back.

## Gear and numbers (all live in Config/Catalog modules; tests check pacing)
**Tools** (buy once with coins, equip any owned): Twig Broom (start), Push Broom, Leaf Blower, Dust Vac,
Turbo Vac, Lava Mop, Dragon Vac, Volcano Vacuum. Each has: reach (studs), arc (degrees), power (units per
cell per swing), swing interval, capacity bonus, and one special trait (wide / long / fast / pull / etc).
They must *look and feel* different: held model built from Parts, different puff colour, different sound
hook. Price curve roughly x4 per tier.

**Upgrades** (coin sinks with many levels, each stat line 12–20 levels, cost grows ~1.25–1.4x per level):
Sweep Power, Sweep Speed, Reach, Backpack Size, Walk Speed, Sell Boost, Treasure Luck, Burp Armor,
Sweet Spot (chance of a double-clear), Lucky Coins (small chance a sale pays double).

**Helper Bots** (buy up to 6, each upgradable): cute round robots follow you and sweep nearby ash on
their own; their coins arrive at a reduced rate and show as little numbers over the bot. Idle joy.

**Gates** (per player): buy each zone once. Higher zones pay far more per unit, so progress feels huge.

**Finds Book**: 30 hidden finds (5 per zone-set + 5 rainbow). 4 rarities with odds shown in the book.
Found by clearing a cell to bare ground (chance, boosted by Treasure Luck). Each find pays coins, the first
of each type is celebrated, and finishing a zone set gives a permanent small coin boost. No gambling for
money; luck only affects discoveries during normal play.

**Cool Down (prestige)**: when allowed, reset coins/tools/upgrades/gates/helpers; keep Finds Book,
Sparks, Spark perks and stats. Sparks = based on this run's lifetime coins. Each Spark: permanent coin boost.
Spark Shop: ~8 perks (start coins, bigger starting backpack, free Push Broom, etc).

**Daily Reward**: 7-day streak ladder; server decides day by UTC date; never double-claimable.
**Goals**: ~14 one-time goals with coin/Spark rewards (sweep 1k ash, sell 50 times, find 10 treasures...).

## The Volcano (events)
A shared "Burp Director" runs a loop. No one ever dies or loses progress; being hit is a bounce + you drop a
little carried ash (Burp Armor lowers it). Phases: Calm → Rumble (6 s warning, sky reddens, camera rumble) →
Event → Recover. Event types:
- **Lava Pops:** glowing target circles appear (2 s telegraph), then lava bombs land. Dodging is the fun.
- **Ash Storm:** extra ash rains onto the island (good: more to sweep). Soft grey snow VFX.
- **Golden Burp:** for 45 s a scatter of golden cells appear worth 5x. Racing for gold is the co-op rush.
- **Gem Geysers:** treasure pops out of vents; touch to grab for coins.
Perfect Dodge: if nobody was hit in an event, the team gets a 3 minute +10% coin boost.
Frequency scales gently with how clean the island is (cleaner → more burps → never boring).

## Co-op
Shared island clean meter (HUD). Milestones 25/50/75/100% per zone trigger an Island Party for everyone in
the server: fireworks, +coins gift, 60 s of x2 coins. Helping is never punished. No stealing between
players (ash is shared; swept units go to the sweeper's own backpack). Friends see each other's sweeps.

## UI (phone first, seamless)
One visual style everywhere: Theme tokens (colours, fonts, corner radius, spacing) + Components library;
no raw colours/numbers in panels. UIScale based on screen size. Safe areas respected. Everything tappable
with a thumb (min 44px touch targets). Landscape and portrait both usable. Panels open with one tween,
close the same way, one panel at a time, dimmed backdrop, big close X.
HUD: coins (top left), backpack bar (under it, pulses when full), island clean bar (top centre), burp
banner (below it), toasts (centre top), sweep button (right thumb, hold), sell button (appears near hut or
when full), menu bar (left edge: Upgrades, Tools, Helpers, Book, Goals, Cool Down, Settings).
Desktop: hold mouse / E to sweep, F to sell, number keys not needed. Gamepad: R2 sweep, X sell.
Auto-Sweep toggle (owned by default as a setting): sweeps whenever you are moving near ash.

## Look and sound
Bright, sunny, rounded toy look with Neon accents (ash glows soft orange at the cracks). Lighting set by
server code (Atmosphere, ColorCorrection, Bloom, SunRays; Future lighting is NOT required). No Robux ids,
no invented asset ids. Sounds are silent unless ids are added in `Config.Audio` (empty list by default; a
test confirms the game works with none). Particles use built-in textures only if the id is known to exist;
otherwise use plain Parts/ParticleEmitters with no texture (default square sparkle is fine).

## Not in v1 (say so in handoff, do not fake)
Robux products/passes, trading, pets, leaderboards (OrderedDataStore) — list as "later".

## Quality bar (judges score each 1–10, we need >= 8 on every line)
1. Core feel of sweeping  2. Economy/progression pacing  3. Upgrade variety and clarity
4. Phone UI quality and consistency  5. Co-op feel  6. Volcano events fun/fairness
7. Visual polish of the island  8. Reliability (no errors, saves safe)  9. Security (server decides)
10. First 5 minutes (a 7-year-old can play without reading).

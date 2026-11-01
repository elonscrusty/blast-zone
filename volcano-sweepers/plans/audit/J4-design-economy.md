# J4 audit: game design, economy and fun

Judge: J4. Lens: design, economy, fun (7-year-old and 14-year-old). Read-only on `src/` and `tests/`.
`lune run tests/run`: 465 passed, 0 failed (so every problem below is invisible to the current tests).

## How I verified
I read the catalogs, rules, AshGrid, AshService, ProgressRules, BurpTuning/Director/Glue, FindRoller, FindsService,
SweepService, SellService, HelperService/Rules, Controls, Vfx, Tutorial. For every number claim I ran a small Lune script
that `require`s the REAL shared modules (not copies), kept in the scratchpad (never in the repo):
`/tmp/claude-0/-home-user-blast-zone/71618d2d-1187-59d0-90bd-994b5af92f84/scratchpad/j4/`
- `cells.luau`, `reach.luau`: real AshGrid cone sizes per tool and per Reach level.
- `supply.luau`, `supply2.luau`, `supply3.luau`: how much ash the island can ever hand out (ceiling).
- `sim.luau`: the pacing test's own buy-policy and rate model (copied from tests/pacing.test.luau) but fed by the real
  AshGrid + real regrow (`ProgressRules.regrowBudget`) + real `BurpDirector` storms + real party tracker.
  Env knobs: `PLAYERS=n HANDMULT=n NOSTORM=1 NOPARTY=1 HOURS=n LOG=1`. Run: `lune run sim.luau`.
- `clearrate.luau`: cleared cells per second (find rolls) per tool. `cells2.luau`: effect of the proposed AshGrid fix.
The sim models a perfect player (best-value zone, no mistakes, no walking between zones), so absolute times are
indicative; the DIRECTION and the supply ceilings (`supply*.luau`, no player model at all) are solid.

## Scores (1-10, need >= 8)

| # | Quality bar line | Score | Why (one sentence) | Biggest single raise |
|---|---|---|---|---|
| 1 | Core feel of sweeping | 6 | Puff, nudge, haptic and bar climb exist, but there is no "+N" number per swing and every sound hook is silent (`Config.Audio.ids = {}`). | M3: floating "+N" per swing (and carter pasting real sound ids). |
| 2 | Economy / progression pacing | 5 | The pacing test passes only because it assumes endless ash; with the real regrow and storms the late milestones land 2-3x late solo and worse in a full server. | M1: make the pacing sim supply-aware and raise the ash supply. |
| 3 | Upgrade variety and clarity | 6 | Ten clear, distinct-sounding upgrades and a nice cheap ladder (12-coin start), but Reach is nearly dead on small tools, tools 1-2 and 5-6 cover the same ground, and three upgrades have awful value per coin. | M4: fix the AshGrid "near circle" so reach/arc mean something. |
| 4 | Phone UI quality | 7 (provisional) | Not my lens; models are unit-tested and touch buttons exist, never seen on a device. | Defer to J3. |
| 5 | Co-op feel | 4 | Parties and golden rush are good ideas, but ash per player falls from 44 u/s solo to 5 u/s in a full server and bots/big tools simply starve friends. | M2: scale ash supply with players. |
| 6 | Volcano events fun / fairness | 7 | Honest 2 s telegraph, no deaths, hub safe, first burp delayed 75-100 s; rewards (Perfect Dodge +10%, flat Golden) and event frequency (24-54% of the time active) are weak/high. | m4/m5: stronger Perfect Dodge, scale Golden. |
| 7 | Visual polish of the island | 7 (provisional) | Not my lens; nobody has seen it. | Defer to J3 / carter's first play. |
| 8 | Reliability | 7 (provisional) | Not my lens; pcall'd services, 465 tests; see J2. | Defer to J2. |
| 9 | Security | 8 (provisional) | Sweep/Sell/Buy read were server-authoritative (no position in Sweep, range checks, Pricing re-check); see J1. | Defer to J1. |
| 10 | First 5 minutes | 7 | First sale and first upgrade come within about 20 s and Auto-Sweep is on by default, but the tutorial stops at the first sale, with no pointer to the first purchase. | m1: extend the tutorial to "buy your first upgrade". |

## BLOCKERS
None by the strict definition (no crash, data loss or exploit found in my lens). M1 and M2 below each cap their lines
(2 and 5) under 8 and should be treated as release-gating for the "8/10" goal.

## MAJOR

### M1. Pacing test is blind to ash supply; the real island hands out far less ash than the sim assumes
- Where: `tests/pacing.test.luau:13` ("The sim ignores how fast the island regrows ash"), `src/shared/Sweep/ProgressRules.luau:164-186,227`
  (regrow `0.9 + 1.1 x (n-1)`, cap 18, x4 boost, `TOTAL_CAP = 60`), `src/server/Ash/AshService.luau:112` (regrowStep),
  storms `src/shared/Burp/BurpTuning.luau:92-94` (+30% of cells, 1-2 units, 5 pulses).
- Verified by: `supply2.luau` removes EVERY unit on the island every 2 s (an impossible infinite vacuum) with the real regrow
  and the real BurpDirector storms for 6 h. Island-wide ceiling after hour 1: **1 player 44 u/s, 4 players 47 u/s, 16 players 85 u/s**
  (storms alone are 23.6 u/s; regrow without storms is only 3.6 u/s solo, `supply.luau`). The pacing sim assumes hand rates of
  20 u/s (Turbo Vac) to 58 u/s (Volcano Vac) PER PLAYER, and a start stock worth only ~171K base coins in the whole island
  (`cells.luau`: 3004 cells, 85% fill) while Zone 5 alone costs 1.8M.
- Failing scenario (`sim.luau`, real regrow + storms + parties, solo, HANDMULT=1): zone 4 at 38 min (target 35, ok),
  Lava Mop 1h15, **Zone 5 at 2h25 (target 70 min), Cool Down offered at 4h21 (target 90 min), Dragon Vac 3h10, Volcano Vacuum
  not bought in 6 h**. With hand rates doubled (`HANDMULT=2`): Zone 5 2h13, Cool Down 3h49. Without the 2x party buff
  (`NOPARTY=1`) it is worse: Zone 5 3h40, Cool Down never in 6 h. So Lava Heart and Cool Down (the "session" loop in DESIGN)
  are 2-3x later than CONTRACTS promises, and the 45M tool is a 10 h+ item.
- Why tests are green: tests check +-30% of targets against a model with endless ash.
- Fix: (a) add a supply-aware phase to `pacing.test.luau` (copy of my `sim.luau` loop: real `AshGrid`, `regrowBudget`, a storm every
  gap) and re-tune to the same targets; (b) raise supply (see M2 numbers); (c) keep Volcano Vacuum at 45M only once (a) shows
  3-5 h, or lower it.

### M2. Co-op: ash per player collapses as friends join; bots and big tools starve everyone
- Where: `ProgressRules.luau:164-176` (cap 18), `:186` (TOTAL_CAP 60); storm fraction is the same for 1 or 16 players
  (`BurpTuning.luau:94`); bots never report their removals: `HelperService.luau:229-243` calls `HelperRules.sweepAround`
  but NOT `AshService.noteSwept` (only `SweepService.luau:198` calls it, although `AshService.luau:8` and
  the ProgressRules header say helper bots do).
- Verified by: `supply2.luau` per-player ceiling = 44 u/s (1 player), **11.7 u/s (4), 5.3 u/s (16)**. A Twig Broom alone sweeps
  8.8 u/s (`cells.luau`), so in a full server a Turbo/Dragon/Volcano tool has almost nothing to chew on. The sim with
  `PLAYERS=4/16` (each player gets 1/n of regrow and storms): zone 4 at 56 min / 1h07, Lava Heart at 5h07 / never in 6 h. More friends make
  every friend slower: the opposite of co-op. Six level-15 bots sweep 18.6 u/s (`Helpers.luau` 0.108 x 1.25^15 x 6) out of the shared
  pool and are invisible to the demand-based regrow.
- Failing scenario: 8 friends join; the beach goes bare in 20 min, everyone is stuck with ~5 u/s each, the person with the
  Dragon Vac visibly empties the cells friends were walking toward.
- Fix (tested starting point, `supply3.luau`): `REGROW_BASE = 3.0`, `REGROW_PER_EXTRA = 3.0`, `REGROW_CAP = 48`, `TOTAL_CAP = 200`
  and storm `fraction = min(0.6, 0.3 + 0.03 x (players - 1))` passed into the `rain` event. Result: per-player ceiling 83 (1), 26 (4),
  15 u/s (16) instead of 44 / 11.7 / 5.3. Solo then doubles, so lower `REGROW_BASE` to ~1.5 and re-run the supply-aware pacing test.
  Also call `AshService.noteSwept(result.units)` in `HelperService` after `sweepAround`.

### M3. The swing has no number and no sound: the "moment" loop is only half built
- Where: `src/client/Core/Controls.luau:176-209` (`feedback`: sound name, haptic, camera nudge, puff only);
  `grep floatText src/client/Core` finds nothing; `Vfx.floatText` is only used for Sold, hit, find, and others' puffs never get numbers;
  `src/shared/Config.luau:64` `ids = {}`.
- DESIGN.md "Moment (3 s)" requires "numbers pop: '+5' float text" and a tick sound. With empty audio ids the whole game is silent,
  so the first 5 minutes are visual-only.
- Fix: in `feedback()` (or a `Store.subscribe("carried")` handler) read the server's new `carried`, compute the delta
  `new - old`, and call `Vfx.floatText(puffPos + Vector3.new(0, 3, 0), "+" .. delta, "ash")`, throttled to one per 0.2 s, size by
  delta. Gold when the zone value >= 8. Ask carter to paste sound ids into `Config.Audio.ids` (never invent them).

### M4. AshGrid's "near circle" makes tools 1-4 almost identical and Reach nearly dead on small tools
- Where: `src/shared/Ash/AshGrid.luau:146` (`near2 = cs * cs`) and `:169` (`ok = d2 <= near2`): every cell within 8 studs is hit in
  EVERY direction regardless of reach and arc.
- Verified by `cells.luau`: real cells per swing: Twig 3.00, Push 3.23, Leaf 3.92, Dust 4.01, Turbo 4.99, Mop 5.03, Dragon 5.84, Volcano 17.05.
  The pacing model (`Tools.cellsHit`) assumes 1.0 / 1.21 / 1.61 / 2.14 / 3.46 / 3.46 / 4.54 / 17.8, so low tiers are really 2-3x faster
  than the model and the "wide / long" traits do not exist: the Push Broom's "Wide sweep" covers 0.2 more cells than the Twig for 130 coins.
  `reach.luau`: Twig Reach level 0 -> 12 (+48%, 16.7K coins) goes 3.00 -> 3.48 cells (+16%); levels 1-3 add nothing at all (reach 7.0 -> 7.84, still under 8).
- Failing scenario: a kid buys Reach (the "best next buy" star can pick it, `UpgradesModel`) and nothing visibly changes; buys Push Broom
  and the sweep fan looks the same as the Twig.
- Fix (tested): `near2 = (cs * 0.5) * (cs * 0.5)` (only the cell you stand in is always hit). `cells2.luau` then gives
  Twig 1.10, Push 1.70, Leaf 2.13, Dust 2.54, Turbo 3.66, Mop 3.77, Dragon 4.68, Volcano 16.2: each tier is visibly bigger and it matches
  the pacing model. `tests/ash.test.luau` / `sweep_rules` cone tests need updating. Also give Turbo/Mop (3.66 / 3.77) a real difference
  (Mop could burn a 2-cell trail or pull from 1.5x reach) or cut the Mop price: 120K for +13% rate over a 16K tool is poor.

### M5. Island Party re-arms after every storm: a party every ~2.7 min solo, x2 coins about 37% of the time
- Where: `ProgressRules.luau:37` (`REARM_DIP = 0.10`) vs a storm that adds ~2 units per cell (about -24% clean) on every zone
  (`BurpTuning.luau:92-94`); gifts `ProgressRules.luau:79-83`; buff `AshService.luau` `celebrate` (60 s x2).
- Verified: `sim.luau` solo, 6 h: **132 parties**. The x2 is not in the pacing test, so the real economy swings ~1.37x faster than the
  sim says in some phases and then the parties lose all meaning (fireworks every few minutes).
- Fix: after a milestone, put the whole tracker on a 5-minute cooldown (or re-arm only when the fraction dips 25% below
  AND 10 min passed), and keep 100% parties rare. Add the party buff to the pacing sim.

### M6. Finds out-earn ash in the late game and are not in the pacing sim
- Where: `src/shared/Finds/FindRoller.luau:21` (3% per CLEARED CELL), `Catalog/Finds.luau` zone bases (20 / 80 / 320 / 1500 / 6000),
  `BurpGlue.findCoins` (x sellMult), `FindsService.luau:44-82`.
- Math (Finds.luau + FindRoller): expected coins per cleared cell = 0.03 x E[rarity] x base = 1.5 / 6 / 24 / 113 / 453 (zones 1-5), times sellMult.
  A zone-4 cell holds 1-2 units after a storm (worth 22-44), a zone-5 cell 60-120: finds are 3-5x the ash value per cleared thin cell.
- `clearrate.luau`: finds per minute at 3%: Twig on fresh ash 0.3, Turbo on storm-thin ash 7, Volcano Vac 10-15. At those rates a
  Legendary (2% of finds, 150K x mult in zone 5) arrives every 3.5-6 min per player, a toast/FindFound every 5-8 s, the 12-find and 40-find goals
  fall in minutes and Treasure Luck (+150% chance, 1.5M total) becomes the best late upgrade by far.
- Fix: cap rolls to 1 per 0.5 s per player (not per cleared cell), or lower `baseChance` to 0.015 in zones 3-5 while raising the legendary coins less
  steeply (`coinMult` 25 -> 12). Include expected find coins in the pacing sim.

## MINOR

- m1 First 5 minutes: `Core/Tutorial.luau:262-270` ends at the first `Sold`; nothing points a 7-year-old at the Upgrades button
  (only the red dot). Fix: stage "buy": when `coins >= 12` and no upgrade bought, bounce the Upgrades menu button and float "Tap to get stronger!".
- m2 Daily reward is flat 100-3000 coins (`Daily.luau:23-31`; `DailyRules.luau:64,73,82,102` never pass `scale`). After the first hour day 7's 3000 coins is seconds of income;
  only the 3 Sparks matter. Fix: pass `scale = clamp(lifetimeCoins^0.5 / 30, 1, 200)` into `rewardFor`.
- m3 Value per coin: Lucky Coins costs ~20.9M for +12% expected income (150K base x 1.4^n over 12 levels), Burp Armor ~20.7M to trim a loss of at most 20% of ONE
  backpack (dropped ash is re-placed within 12-48 studs and can be re-swept), while Sell Boost gives +100% for ~1.3M and Treasure Luck +150% for ~1.5M.
  Not a trap by definition, but the 150K/60K base costs make them dead ends. Fix: Lucky Coins `baseCost` 150000 -> 20000, `perLevel` 0.01 -> 0.02; Armor `baseCost` 60000 -> 8000.
- m4 Perfect Dodge is +10% for 3 min (`Config.luau:49` `perfectMult = 1.10`, `BurpTuning.luau:108`) after 12 s of dodging; x2 Party is the benchmark. Fix: 1.25 for 120 s, or a free Treasure roll.
- m5 Golden Burp does not scale with progress: 12 + 2/player cells (cap 45, `BurpTuning.luau:99`) each x5 on 6-9 units; ~4K coins early, trivial late (income is ~1000+/s).
  Fix: goldenMult = 5 x (best zone value ^ 0.3) or flag more cells for stronger tools.
- m6 Event frequency: gaps 80-140 s (`BurpTuning.luau:64-65`) with rumble 6 + event 12-45 + recover 8 means the volcano is "on" 24-54% of the time on a clean island
  (gap shrinks as it gets cleaner). Fix: `gapMin` 80 -> 110, keep `gapMax` 140.
- m7 The first Helper Bot (450 coins) earns 0.108 u/s: 0.1 coin/s in zone 1, 0.3 in zone 2 (`Helpers.luau:13,15`). Payback > 20 min until zone 3. It is cute but feels dead; `HelpersModel` shows the estimate so it is honest.
  Fix: first bot 150 coins, or `BASE_UNITS` x2 with growth 1.2.
- m8 Goals: `ash_legend` needs 1,000,000 hand-swept units (`Goals.luau:47`); my sim has 89K in 6 h (hand only counts). Fix: 150000. Only 4 of 14 goals sit after the first hour.
- m9 Cool Down: first reset gives 10 Sparks = +49% coins (`StatsCalc.sparkBonus(10)`) and throws away every purchase; Head Start max is 9000 coins and Free Push Broom
  saves ~2 minutes. Combined with M1 it is reached around 4 h, so many players never see it. Fix after M1: show a projected "run 2 reaches Lava Heart in N min" on the Cool Down card.
- m10 Walk to the hut from Lava Heart is ~160 studs (hub radius 222, zone 5 outer 62): 20 s round trip at base speed vs 12 s assumed (`Config.luau` `tripSeconds`). Fix: a one-tap "Teleport to Hut" in the Gates panel after buying zone 4+.

## What is good (keep)
- First sale about 15-30 s, first upgrade costs 12-15 coins, cheapest ladder is dense so there are no 20-minute dead zones in the first hour (`sim.luau` log).
- Auto-Sweep default on (Economy.blankProfile settings) means a 7-year-old needs no thumb gymnastics.
- Volcano: 2 s telegraph, bomb radius 7 and aim jitter 4 (`BurpTuning.luau`) are dodgeable at 16 studs/s, hub safe (`BurpService.luau:287`), hits cost <= 20% of the pack and give 2.5 s shield, no deaths.
- Server-owned prices, ranges and cooldowns.

## Five changes that would raise the fun most
1. Make ash supply a first-class balance variable: supply-aware pacing sim + per-player regrow and storm scaling (M1, M2).
2. Show the numbers: "+N" per swing, gold for rich zones, louder reveal on the cleared ground; get sound ids pasted in (M3).
3. Fix the near-circle so every tool is visibly bigger (M4) and give Mop/Dragon real traits (trail, pull).
4. Calm the party and find spam (cooldowns, 1 roll per 0.5 s) so rewards stay special (M5, M6).
5. Extend the tutorial to the first upgrade and add the Teleport-to-Hut button (m1, m10).

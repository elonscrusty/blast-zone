# 48 Gear slots (video 3 gap #15)
- Done: three new loadout slots, HEAD / BODY / FEET. Each has Plain (free) plus 3 pieces (the first one free, two earned on the Rewards board at levels 2 to 6). All free, no Robux, no ids, no prices.
- Every piece is a small trade, never plain power: it gives in one dial and takes in another (health, speed, reload, range, Slide wait, Slide reach). `Gear.worth` weighs each dial; a test makes every piece add up to zero or less, and every 3-piece outfit too.
- Limits: the sum of the three pieces is clamped by `Config.Gear.limits`; Slide keeps its floors. Knob: `Config.Gear.spread` (0 none, 1 as written, 1.5 bigger trades).
- Code: `src/shared/Gear.luau` (pieces, totals, sheet tuning, card lines), `Loadout` slots/items, `LoadoutView` (gear cards carry the trade as short lines), `src/server/Core/GearBook.luau`, `LobbySystem` (stat-sheet modifier + player attributes GearHead/GearBody/GearFeet), `Combatants.ensure` (health bonus read once at match start).
- Server decides: same `LoadoutEquip` remote and checks as every pick; no changes during a match; bots wear nothing; saved with the profile loadout like the other slots (new keys, no schema change).
- Looks: each piece has a placeholder `shape` and `color` for the look layer. Nothing is drawn yet; Claude Design / art reads the three player attributes. The placeholder panel just gets three more tabs.
- Tested: `tests/gear.test.luau` (catalogue, trades, all 64 outfits stay in limits, spread, sheet copy, slots, store, cards), stylua, lune (989 pass), rojo build. selene runs in CI. Not tested until carter plays: how the trades feel.
- Left: gear on the character (art), a "power rating" number (gap #16), analytics for gear picks, bots picking gear, gear in the results screen.

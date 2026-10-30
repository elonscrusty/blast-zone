# 43 Power Picks (video 3 bundle B, big level-up powers; carter said "do them all")
- Done: 5 new level-up cards that change how a fight plays. Piercing Rounds (bullets fly through 1 more body, each takes 40% less), Rapid Fire (40% faster, 10% softer), Aftershock (every mortar blast goes off again 0.7 s later for half damage), Heavy Shell (mortar +50% damage, +30% wider, reload +35%), Long Slide (+40% slide length). Catalogue is now 14 cards.
- Numbers: the card numbers sit in `src/shared/UpgradeDefs.luau`; the shot-side numbers in `Config.Powers` (falloff 0.6, delay 0.7 s, share 0.5). Hard caps added: shot delay never under half, pass-through max 1, aftershock max 1, slide max +50%. All placeholders until carter plays.
- Two new stats ride the stat sheet: `firearm.pierce` and `explosive.aftershock` (Types, StatBook, WeaponCatalog). Found guns get Piercing too (the power belongs to the fighter).
- Server decides: `Ballistics.line` (pure) finds the bodies a shot passes through, `Firing.fireBullets` hurts each (walls still stop it), `Shells` schedules the second blast and drops it if the match moved on.
- Cards: the two mortar powers are only offered when the mortar is on (existing rule). Card icons are text placeholders (`PIERCE`, `RAPID`, `AFTER`, `HEAVY`, `ZIP`); Claude Design owns the real art.
- Tests: `tests/powers.test.luau` (11 cases) plus two edits in `tests/upgrades.test.luau` (14 cards; the "offer no longer fits" test finds any mortar card). stylua, lune (892 pass) and rojo build are clean; selene runs in CI.
- Not tested until carter plays: how piercing and the double blast look and feel, whether Rapid Fire on the Hornet is too fast, how often the new cards show up (weights 5-6).
- Left: a look for the second blast and for a bullet going through someone, sounds, bots choosing powers on purpose.
- Bundle C (Fast Feet) is next.

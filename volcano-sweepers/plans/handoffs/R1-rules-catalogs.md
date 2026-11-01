# R1 handoff: rules, catalogs, economy, balance sim
1. Catalogs in `src/shared/Catalog/` (Tools, Upgrades, Zones, Finds, Helpers, SparkPerks, Goals, Daily). Rules in `src/shared/Rules/` (StatsCalc, Economy, Pricing).
2. Server AND client price things only with `Pricing.priceOf(kind, id, profile)`; the server rejects a Buy when `Pricing.reason(...) ~= nil` (it also checks coins/Sparks).
3. `StatsCalc.compute(profile, buffs, now)` returns Types.Derived plus extras: sweetChance, luckyChance, helperMult, buffTime. Send them in `derived` too.
4. Sale: `Economy.sellValue(carriedValue, derived, rng)` -> coins (total paid), bonusCoins (the Lucky part), luckyDouble.
5. Bots: coins/s = `Helpers.coinsPerSecond(count, level, zoneValue, derived.sellMult, derived.helperMult)`.
6. Cool Down: check `Economy.canCoolDown`, then `Economy.coolDownReset(profile)` -> (newProfile, sparksGained). Buying a Spark perk: apply `Economy.perkGrant(id, newLevel)` (coins / free tool) at once.
7. Sparks bonus counts unspent + spent Sparks (`StatsCalc.totalSparks`), so buying perks never lowers it.
8. Ash supply: the sim assumes endless ash. Hand sweeping reaches ~2 ash/s (Twig) to ~58 ash/s (Volcano Vac + upgrades); regrow / storms must keep up.
9. Pacing sim (`tests/pacing.test.luau`): push 2:21, zone 2 6:27, leaf 9:16, zone 3 15:15, zone 4 33:53, zone 5 1h08m, Cool Down 1h28m, Volcano Vac 3h36m. Retune the catalogs, not the test.
10. Not done by R1: marking NEXT-PIECES.md (caller does it), Robux/ids (none).

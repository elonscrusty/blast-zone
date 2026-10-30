# 35 Smarter bots
1. Tiers: easy / normal / hard, set in `Config.Bots.tiers`. Bot number picks one from `Config.Bots.tierCycle` (b1 normal, b2 easy, b3 hard, ...), same every match. A tier changes sight, reaction, aim, cover chance, gun hunting and how early it leaves the zone wall. Never health, damage, speed or ammo (a test checks the key names).
2. Calm start kept: warm-up numbers are not scaled, so every tier starts as gentle as #21. A test checks all three tiers at second 0.
3. Cover: a bot that is reloading, empty or hurt looks around (8 spots, 2 rings) for a spot the enemy cannot see, walks there, waits until the reload is done (max `coverHold` 3 s), then steps out. No spot = old behaviour (flee when hurt, keep fighting when reloading).
4. Zone wall: it turns back earlier while the zone is closing (+8 studs) and by tier (+0/+4/+10). It keeps shooting while it runs in, slides back in when 12+ studs outside, and a hurt bot no longer stays at the wall. No orbs or guns outside the safe circle.
5. Guns (#31): `BotGuns.luau` gives each gun a habit. Breaker rushes in and fires within 80% of reach, Hornet holds mid range, Longline keeps away. Bots use the gun in hand's real range (`BotPort.state` now returns `gunId` and `range`).
6. Gun hunting: bots walk to a found gun that is an upgrade (hornet > breaker = longline > pistol, never swap sideways) and ask for the swap within 5 studs. Same server checks as a player: `WeaponDrops.claimFor` shares `trySwap` with the button. Easy bots do not hunt guns.
7. Code: `src/server/Bots/{BotGuns,BotBrain,BotTuning,BotRunner,BotSystem,BotPorts}.luau`, `src/server/Combat/{BotPort,WeaponDrops}.luau`, `Config.Bots`. No UI, no lobby setting (carter picks nothing visible here).
8. Tests: `tests/bots_smart.test.luau` (tiers, calm start, zone, cover with a fake wall, guns, runner). All 628 pass; stylua clean; rojo builds. Selene runs in CI only.
9. Not run in Studio. Cover uses the shot-blocking test, so low fences do not hide a bot.
10. Left: no real pathfinding around corners, bots never use the mortar, no lobby difficulty picker. If bots feel too hard: lower `hard` scales or edit `tierCycle`.

# 03 Aiming, firearm, health, eliminations, Arc Mortar
- Done: Volt Pistol (slot 1) and Arc Mortar (slot 2, `Features.explosiveWeapon` now on), server-checked shots, health and elimination, feedback in the world (tracers, blasts, damage numbers, head health bars).
- Code: `src/server/Combat/` (CombatSystem starts it; pure rules in Ballistics, WeaponState, HealthBook, ShellFlight) and `src/client/Combat/`. Numbers: `Config.Weapons`, `Config.Combat`.
- Shots fly flat from the body. Only `BlocksShots` parts stop them (`LowCover`, fences, roofs do not). A shot that starts in a wall hits the wall and still spends the round.
- Mortar shell flies straight, bursts on a wall, any body but the shooter's, or at max range. Blast needs a clear line, hurts the shooter at 50%, breaks crates via `ContainerSystem.damage`.
- Health: `Damage:bind(Combatants.applyDamage)`. Zone has no killer credit. `Combatants.heal(id, n)` for heal pickups. Bots use `Combat/BotPort` (fire, reload, switchSlot, state, registerBotBody, shotParams, isLineClear). A self-kill reports killerId == victimId: XP and kill feeds must ignore it.
- Input is piece 10's `Controls`. I read `Controls.isFiring` and `getAimWorld` and send FireRequest only; piece 10 sends reload and switch. I turn the body to the aim with a torque-only constraint.
- Piece 05: set `Players.CharacterAutoLoads = false`, or an eliminated player (humanoid killed) respawns mid-match. Call Damage only from combat phases.
- Tested: `lune run tests/run` (fire rate, ammo, reload, switch, walls, blasts, health, damage door), luau type check, rojo build. Not tested: Roblox-side raycasts, remotes, visuals (only when carter plays).
- Left: no lag compensation (hits use current positions, body circle 1.8 studs); sounds; the mortar has no held model (its shell is drawn); the pistol model is carter's picked A++ look built from about 50 welded parts (no mesh art pass).

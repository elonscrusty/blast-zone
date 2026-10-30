# Piece 04: Combat (health, weapons, projectiles, dodge, heal)

**Goal:** Everything that hurts or protects a bot. The heart of the game.
**Read first:** build plan, `02-design.md` (heroes, weapons, perks).

## You own
- `src/server/Systems/Combat.luau`
- `src/shared/Config/Heroes.luau`, `src/shared/Config/Weapons.luau`
- `src/shared/CombatMath.luau` (pure): stat scaling, damage, splash falloff, crit roll (random passed in), shield-first damage, cooldown and reload helpers, perk stat modifiers
- `src/shared/Projectile.luau` (pure step + hit test on a simple world interface)
- tests: `tests/combat_math.test.luau`, `tests/projectile.test.luau`

## Build
1. **Stats.** From `Loadout` + `Perks`: max HP (hero base x (1 + 0.06 per hero level above 1) x Thick Skin), damage (weapon base x (1 + 0.08 per weapon level above 1) x Hot Shots), cooldowns (Quick Fuse), reload (Quick Hands), move speed (hero speed x Zoomies), splash (Big Bang). Write the perk ids as constants shared with `Loot` (`Config/Weapons.luau` exports `PerkIds`).
2. **Register / unregister.** Restyle a player character (hide accessories, add the wind-up key and a green "you" ring client-side via Attribute), set Humanoid WalkSpeed and Health handling (use Attributes `Hp`/`MaxHp`, keep Humanoid health at max so Roblox never auto-kills).
3. **Blaster.** On `Intent.fire` and ammo > 0: fire at 4.5/s along `aim` (server clamps the angle to the character, ignore if dead). Projectiles are simulated on the server each Heartbeat (speed 120, range 40) with raycasts against fighters and props; send `Shot` for looks. Ammo 24, reload 1.6 s automatic at 0 (Attribute `ReloadingUntil`). Crit 10%.
4. **Boom Cannon** (`Action "heavy"`): needs the cooldown ready (6 s). One shell (two with Twin Boom), speed 70, range 55, explodes on hit or at range: splash radius 9, 100% at the center to 50% at the edge, hurts fighters (not the shooter for blasters; the shooter **is** hurt by 25% of their own cannon) and calls `Arena.splash`. Send `Explosion`.
5. **Zip Roll** (`Action "dodge"`): 12-stud dash along the current move direction, 0.35 s untouchable, cooldown 5 s, server-moved.
6. **Fix-it Kit** (`Action "heal"`): needs a kit and not full HP; heals 35% of max HP over 2 s; cancel nothing on damage. **Bubble** shield absorbs 150, damage hits shield first.
7. **applyDamage / eliminate.** Shared by blasters, cannon, pits, ghosts: reduce shield then HP, fire `FighterDamaged` and send `Hit` (pos above the head, amount, crit). At 0 HP: mark `Alive = false`, fire `FighterEliminated` once (with the last source), play a topple (ragdoll-lite or fall over), send `KillFeed`, and a `Banner` for streaks (2 kills in 6 s = MULTI KILL, 3 = MEGA KILL, 5 total = MASSACRE, 3 in a row with no damage taken = INVINCIBLE).
8. **Movement guard.** Players walk on their client. Every 0.2 s compare each player's position change with `walkSpeed x 1.6 + dash allowance`; if too far, teleport back to the last good spot. Also keep fighters inside the Arena bounds.
9. **Intent.** `Net.onServer("Intent")`: validate `aim` is a Vector2 with a finite length, normalize it, store it. `Net.onServer("Action")`: check the string is one of the three, call `Combat.act`. Only for players registered and alive.
10. Provide every function in the contract. Everything is keyed by `FighterId`, so bots and players use the same code.

## Server checks
Never trust client aim length, fire spam (the 4.5/s cap is server side), or action timing. Dead fighters do nothing. Damage is never negative or NaN.

## Tests (Lune)
`CombatMath`: stat scaling per level, perk stacking (cap 3), shield-first damage, splash falloff at 0%, 50%, 100% of the radius, cooldown boundaries. `Projectile`: moves at speed, stops at range, hits the first target on the line, no tunneling at 120 studs/s with a 1/60 s step.

## Done when
Checks pass, contract (`Combat.*`, Attributes, Bus events) matches, row 04 marked, handoff written.

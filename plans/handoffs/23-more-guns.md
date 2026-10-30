# 23 More guns (Breaker, Hornet, Longline)
1. carter picked all 3 on the 3D preview (`plans/previews/guns.html`, built from the real part lists by `python3 tools/gun_preview.py`).
2. Numbers: `Config.Weapons.Guns`. Breaker 6x7 pellets, 26 range. Hornet 5 dmg at 11/s, 30 mag. Longline 34 dmg, 1.25 s, 80 range.
3. How you get one: a container broken by a shot or blast drops a gun 35% of the time, 1 in 3 each (`Config.Weapons.Drops`). Free, never bought.
4. Swap = ProximityPrompt on the gun (tap on phone, E, gamepad X). Server checks phase, alive, match, distance, cooldown. Old gun drops unless it is the pistol.
5. Found gun takes slot 1 with a full mag (`WeaponState.replace`); mortar ammo untouched. New match = pistol again (`Combatants.ensure`).
6. Upgrades only know the pistol; `Combat/WeaponCatalog.stats` scales each gun by the same share (pellets/spread added). Steady Aim does nothing to Hornet spread (known).
7. Held gun follows the `WeaponId` character attribute; `CombatGun` is rebuilt on swap and keeps parts named `Slide` and `Grip` (character piece must re-weld on ChildAdded).
8. Also fixed: the Volt Pistol grip now rakes back (tilt -0.2) like a real pistol. AmmoState now carries weaponName, fireInterval, reloadSeconds, muzzleOffset; HudModel reads them.
9. Tested: `lune run tests/run` (fire rates, scaling, odds, swap, part lists), stylua, rojo build. Not tested: prompts, drops, visuals in Roblox (carter plays). selene runs in CI only.
10. Left: bots never pick up guns; no gun sounds per weapon; drops only come from combat damage to containers.

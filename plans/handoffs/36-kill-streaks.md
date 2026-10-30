# 36 Kill streak rewards
- Done: a kill within 12 s of the last one grows a streak. Tiers pay once: 2 kills = +15 HP, 3 = speed x1.2 for 4 s, 5 = +30 HP and speed x1.25 for 5 s. Numbers: `Config.Streaks` (placeholders until carter picks).
- Code: `src/shared/StreakRules.luau` (pure, Lune-tested) and `src/server/Combat/StreakSystem.luau` (starts itself, order 140).
- Server decides: reads `Damage.Eliminated`; no reward for self-kills, zone deaths, a dead killer, or a stale match. Dying resets the streak. Match reset clears all streaks and boosts.
- Heal uses `Combatants.heal` (never over max). Speed uses `MovementSetup.setSpeed`, so the 1.4x walk-speed cap still applies. An upgrade picked mid-boost keeps the boost.
- Bots earn streaks too (same rules, no hidden advantage).
- Look: placeholder only. Text goes out as the existing `Notice` remote. Claude Design owns the real streak banner/aura; no new remotes, no new ScreenGui.
- Tests: `tests/streaks.test.luau` (6 cases). Checks run: stylua, lune (329 pass), rojo build. selene needs network for its std dump, so CI runs it.
- Left: carter picks which rewards he likes; Studio play check; speed boost is clamped if upgrades already sit at the speed cap.

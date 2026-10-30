# Piece 06: Bots (so the lobby is never empty)

**Goal:** Funny little toy bots that move, loot, shoot and run from the blast, and can be beaten.
**Read first:** build plan, `02-design.md`.

## You own
- `src/server/Systems/Bots.luau`
- `src/shared/Config/Bots.luau` (60 funny names, 3 skill levels, think rate)
- `src/shared/BotBrain.luau` (pure decision logic), `src/shared/BotNames.luau` (pure pick without repeats)
- tests: `tests/bot_brain.test.luau`, `tests/bot_names.test.luau`

## Build
1. **Models.** `Bots.create(n)` builds n rigs from Parts (same shape as a player bot: Humanoid, HumanoidRootPart, body, big head, wind-up key, random body color from the theme). Names from `BotNames` (no repeats in one match). Returns `Fighter`s with `isBot = true`, ids `b1..bn`. Match registers them with Combat. `removeAll()` destroys them.
2. **Brain (pure).** `BotBrain.think(view): Decision`. `view` is a plain table: own position/HP/ammo/kits/cooldowns, visible enemies (position, HP, distance), nearest chest, danger cells (warned or blasted), safe-cell hint, time. `Decision` = `{ move: Vector2, aim: Vector2, fire: boolean, action: Action? , goal: string }`. Priorities: (1) leave a pit or a warned cell, (2) heal if HP < 40% and a kit exists, (3) dodge when a shell is close and roll is ready, (4) fight the best target (nearest, lowest HP), keep a preferred range (kite: back off if closer than 12, close in if farther than 30), use the cannon when the target is 15-45 away, (5) walk to the nearest chest, (6) drift toward the safe area. Three skill levels change reaction time (0.5 / 0.3 / 0.15 s), aim error (12 / 6 / 3 degrees) and how well they dodge. Add a little randomness so they are not robots. No wall hacks: only enemies within 45 studs and in line of sight count.
3. **Driver.** One Heartbeat loop at 10 Hz for all bots (not one thread each). Build the `view` from `Combat.getState`, `Match.getAlive`, `Arena.cellAt/isBlasted`, chest positions from the world. Apply `Humanoid:Move`, `Combat.setIntent`, `Combat.act`. Do cheap checks first (skip dead bots).
4. **Fair.** Bots use the same Combat calls and limits as players. They never apply damage themselves.
5. Stuck detection: if a bot has not moved 2 studs in 2 s, pick a random direction for 1 s.

## Server checks
Bots go through `Combat` only, so every Combat check applies. Cap the loop work (max 16 bots) so one frame stays cheap.

## Tests (Lune)
`BotBrain` with hand-made views: leaves a danger cell first, heals when low, dodges only when roll is ready, picks the nearest enemy, kites at close range, does not shoot with no ammo, heads to a chest when idle, skill level changes reaction time. `BotNames`: no repeats, never runs out (wraps with numbers).

## Done when
Checks pass, contract (`Bots.create/remove/removeAll`) matches, row 06 marked, handoff written.

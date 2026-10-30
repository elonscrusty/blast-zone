# V16 Power rating (video 3 gap #16)
- Done: one number for how far a player has come. Pure rules in `src/shared/Power/PowerRules.luau`, knobs in `Config.Power` (points per level, per look, per win, per elimination, per match; a cap on each; 7 bands).
- Made only from things earned by playing: account level, looks owned beyond the free ones (store tiers and level gifts), wins, eliminations, matches. Coins, Robux and hero picks do not count. Nothing in combat, loot or matchmaking reads it, so it can never be Robux power. Do not change that.
- Max is 1640 points (level 50 = 490, looks 150, wins 500, eliminations 300, matches 200). A new player is 0. Change the knobs only before the game is live.
- Server `src/server/Power/PowerSystem.luau` reads progression (via `ProgressionSystem.progressOf`) and the saved stats (via `Profiles`), computes, and sends `PowerUpdate` to that player only. It re-sends when progression changes, the profile loads, or a match pays (one beat later, after Stats). It writes nothing and saves nothing.
- Client `src/client/Power/PowerClientSystem.luau`: `get()` gives `{ power, band, toNext?, parts }`; `Changed` fires on every update. No screen on purpose: Claude Design picks where it shows (lobby card, results, name plate). Part ids never change; `PowerRules.LABELS` are starter words only.
- Remotes: `PowerRequest` (no arguments, 1/s) and `PowerUpdate` (`PowerPayload` in Types).
- Tested: `tests/power.test.luau` (11: sums, caps, junk input, bands, saved-table reading, same(), remotes). Lune 982 pass, StyLua clean, rojo build ok. Selene runs in CI only. Not run in Roblox.
- Left: a screen for it, a band name set, showing it on other players' name plates (needs sending it to everyone, a small change), gear slots (gaps 14-15) can add parts later.

# 25 Daily challenges
- Done: 3 challenges a day (one easy 20, medium 35, hard 50 Scrap: `Config.Daily.rewards`), same for every server, new at `Config.Daily.resetHourUtc` (0 = midnight UTC). Kinds: eliminations, crates, XP orbs, matches, top 3, wins. List: `src/shared/Daily/DailyDefs.luau` (saved ids, never rename).
- Server counts, client only asks: `RunXp.Awarded` (new signal: elims, crates, orbs) and `MatchSystem.RewardGranted` (matches, top 3, wins; a shared first place counts as a win). Bots never count. Wiring: `src/server/Daily/DailySystem.luau`.
- Pay: `ProgressionSystem.grant` -> new `ProgressService.grant` (piece 18), once per key `d:<day>:<id>`. A failed payment is tried again on the next count or `DailyRequest`; a "duplicate" just marks it paid.
- Saving: `data.daily = { day, progress, paid }` through `Profiles.update` (piece 17). Without the profile module it runs in memory and the board says "Test mode: not saved".
- Remotes (25 block): `DailyRequest` (ask), `DailyState` (tell). Types: `DailyState`, `DailyChallengeView`.
- Client: `src/client/Daily/` (DailyUiSystem, DailyIcon = 3D part icons in ViewportFrames). Look `Config.Daily.look`: A Sticker Stack (default), B Ticket Row, C Big Board. DAILY button at lobby (0.26, 0.88) next to TRACK; top strip "DAILY DONE! +N Scrap".
- Branch contains PR #17 (coins). Merge #17 first; then this PR only adds piece 25.
- Tests: `tests/daily.test.luau` (picks, day turn, caps, pay once, retry, new day, text); 2 deliberate breaks made it fail. Nothing run in Studio.
- Left: carter's look pick (preview: Daily Challenge Tries artifact). Tune goals/rewards after playing.

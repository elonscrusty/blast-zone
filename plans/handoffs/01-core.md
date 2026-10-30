# 01 Core + shared rules
- Done: Config (all tuning + game name), Types, Ids, Signal, Guard (arg checks + rate limit), RemoteDefs (every remote, by owner), Remotes.
- Server Core: Net (guarded remotes), Participants, MatchContext, Damage (one door), RunXp, EffectiveStats, CollisionGroups.
- Client Core: Net. Boot finds any `*System` ModuleScript and starts it (no edits to Main files).
- Read `plans/CONTRACTS.md` (who owns what, how to call things) and `plans/ASSUMPTIONS.md` (decisions and open items).
- Tests: `lune run tests/run` (guard, phases, damage door, registry, XP, stats, config checks).
- Checked by tools only: stylua, lune tests, rojo build, luau-analyze on pure files. Nothing was run in Studio.
- Not tested: Remotes/Net/Core singletons use Roblox services; they only get exercised when carter plays.
- Left: nothing blocks others. Open: upgrade list (08), arena layout (04), bot detail (09), controller map (10).
- Merge check: piece 01 will check all PRs fit together once the others land.

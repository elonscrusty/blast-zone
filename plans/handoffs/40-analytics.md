# 40 Player analytics (server only)
- Done: `src/server/Analytics/AnalyticsTracker.luau` (pure, Lune-tested) decides what to send; `AnalyticsSystem.luau` (starts itself, order 900) sends to Roblox AnalyticsService. Every send is in a pcall.
- Events (LogCustomEvent): `match_start` (value = participants, field `botsN`), `match_end` (value = seconds, field win/out/draw/abandoned), `death` (value 1, fields cause, killer player/bot/none, gun id), `gun_pick` (field gun id).
- Funnel (LogOnboardingFunnelStepEvent, once per player per session): joined, pressedPlay, firstMatchStarted, firstElimination, firstMatchEnded.
- Already wired: joined, match start/end, deaths (from Damage.Eliminated), firstMatchStarted/Ended, firstElimination.
- Other pieces call `AnalyticsSystem.funnelStep(player, "pressedPlay")` (lobby/onboarding PRs) and `AnalyticsSystem.gunPicked(player, gunId)` (more-guns PR). Not wired yet: those two hooks, because those PRs are not on main. Integration thread: add the two calls when folding in.
- Privacy: no names, user ids, chat or positions. Unknown gun ids and causes become `other`. Labels are fixed lists.
- Tests: `tests/analytics.test.luau`. Nothing run in Studio.
- Left: StyLua, Selene, Lune and Rojo checks were NOT run (tools missing in this container); run them before merge.

# A1 Whole-game audit to 7/10
- Score before 6/10, after 7/10 (game systems: match flow, bots, guns, saving, anti-cheat, perf). UI layout is owned by the UI thread and not scored here.
- Checked: Lune 1367 pass; type check of all of src finds no real bug (only Roblox-stub noise); read the match flow, remotes door, firing, saving and bots; fire-rate limit already covers the fastest gun.
- Proof of soundness: 240 fuzz matches (120 seeds, 3 maps, 1-4 people, leavers, 2 matches each) all finished, no errors, none stuck. Median fight 108 s, 90th percentile 188 s.
- Fix 1: bots no longer ask Roblox for 24 rigs per match (slow web-backed call, the likely start-of-match stall). One Crash Dummy is built once at boot (`BotRoblox.warm`) and every bot is a Clone; failed builds retry 3 times.
- Fix 2: a bot with no body (build failed, or it fell out of the world) never met the zone, so it could hold a match open until the 210 s draw. Now `dropBodiless` / `reapLostBodies` eliminate it through the damage door (cause "other").
- Test: `full match: mixed seeds, lobby sizes and leavers never get stuck` (12 seeds, 3 maps, a leaver after match 1).
- Not proven: Roblox-side clone and reap (needs a real play); look for "[bots] building the Crash Dummy failed" in Output.
- Left, keeps it under 8/10: no sound ids (silent game; need real ids from carter), phone layout (UI thread), nothing proven live yet (saving, 25 fighters on a weak phone), Lighting.Technology is Future (heavy on weak phones; carter's call).

# A handoff: big island (4x area), Trade Posts, re-balance

1. Files: shared/{Config,WorldPlan,Ash/Layout,Sweep/ProgressRules,Burp/*}, server/World/* (+ new `TradePosts.luau`), server/Ash/AshService, default.project.json (MaxPlayers 24), tests (ash, burp, burp_glue, helper_rules, island_sim, pacing, progress_rules, sweep_rules, ui_math, world_plan).
2. Island: radii 2x (beach 500 .. cone 60), 12,038 cells (8 studs), hub at radius 444; sea, wall, volcano (scale ~2, ~80 tall), gates (x1.5), vents (16, ~1 per 190 studs of ring) and decor (326 items, landmarks drawn 1.3-2.6x) all derive from Config.World. ~2,160 world Parts.
3. Trade Posts: one per zone 2..5, 15 studs inside the outer edge, 24 studs beside the gate (`WorldPlan.postSpots`). Pad tagged VSSellPad, counter prompt tagged VSSellPrompt (range 10), so SellService/HUD/Vfx already work. Layout keeps a 10-stud circle clear.
4. Regrow: half lands 32-90 studs around players (`ProgressRules.regrowNear`); the bare patch around players feeds the pace part (`nearClean`, PATCH_WEIGHT 0.7). REGROW_CAP 27, TOTAL_CAP 720 (24 players). Solo paceShare 0.42.
5. Events: bombs/decoys land within 30 studs of a kid, up to 6 a wave; geysers pop near a kid; gold 40 + 20/kid (cap 380, same density); storms x sqrt(3004/N) ~0.5.
6. Economy: Cool Down offered at 7M run coins (was 3M) because the big island is ~15% faster mid-game.
7. Pacing (median of 3): push 2:02, zone2 5:42, leaf 9:05, zone3 12:19, zone4 28:25, zone5 52:34, cool down 1h22m, Volcano Vac 3h15m. Zone 3 and 5 sit near the -30% edge.
8. Crowds (ash swept per kid vs solo, first 40 min): 2 kids 1.1x, 4 0.9x, 16 0.76x, 24 0.78x; supply per kid stays ~1x what they sweep.
9. Needs a phone/Studio look: walking distances on a 1000-stud island, Trade Post look and prompt reach, gate size, volcano proportions, storm delta bursts (~3,600 cells per pulse with 24 players).
10. Not mine, worth a look: SellService toast still says "Walk to the Trade Hut to sell!" (a Trade Post works too). Checks: stylua clean, lune 548/548, rojo build ok, selene (luau std, no warnings in these files).

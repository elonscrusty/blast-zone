# S4 handoff: player services + bootstrap
1. `src/server/Main.server.luau` boots its modules by path (MoveWatch right after PlayerState) (FindFirstChild + pcall require + pcall init); a missing/broken one only warns.
2. Pure rules (Lune-tested) in `src/shared/Player/`: PurchaseRules, DailyRules, GoalRules, HelperRules, Wallet. Services are thin glue.
3. PurchaseService: Buy/EquipTool/SetSetting/TutorialDone + VSGate prompts (buy zone, or Toast "Collect N more coins" / "Already open!"). Spark perks pay out at once via `Economy.perkGrant`.
4. DailyService uses `Profiles.grantOnce(Profiles.dailyKey(day))`; hint Toast 6 s after ready when a gift waits.
5. GoalService: ClaimGoal once; a Toast when a goal becomes ready (checked every 10 s).
6. CoolDownService: `Profiles.update` + `ProfileSchema.assign` (live table identity kept), clears backpack, recompute, fullSync, `CoolDownDone`, `saveNow`.
7. HelperService: bots follow at 20 Hz, sweep once a second via `AshService.grid` (and report it with `AshService.noteSwept`), pay owner coins directly, "+N" label at most every 2 s per bot, 60 bodies max (fair share), teleport when owner > 80 studs.
8. Helper pay share is 1 (not 0.35): `Catalog/Helpers.unitsPerSecond` already holds the 35% rate (pacing test prints it). Change `HelperRules.PAY_SHARE` to tune.
9. Added `PlayerState.toast(player, text, kind)`.
10. Not done: bots do not count toward ashSwept/cleared stats or finds; no purchase stats (Types.Stats has no such keys).

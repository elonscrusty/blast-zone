# J-fix handoff: server + shared (audits J1-J5)
1. Movement trust: `shared/Player/MoveRules` (pure) + `server/Core/MoveWatch`. Sweep, sell, gems, gates and bombs use `MoveWatch.position` and refuse while the player is suspect; repeated jumps snap back (no kick).
2. Saves: a locked/busy/failed load plays offline, never saves, and retries in the background (`ProfileManager.tick`, 8 tries x 20 s). State key `offlineRetrying`; Toasts for "still loading", "back", "rejoin". "noAccess" (403 / Studio API off) is never retried. playSeconds commits every minute.
3. PlayerState: recompute/setBuff only for ready players; a leaving player is out of `all()`. Character attributes `VSTool` (equipped tool id) and `VSSweeping` (true ~0.4 s per accepted swing).
4. Sweep cone: own cell always, other cells when their centre is within reach + a quarter cell and inside the arc (`AshGrid.ownCell`, `AshGrid.coneReach`). Every Reach level and arc degree counts. Lava Mop and Volcano Vac melt leftovers (`melt`). RATE_SLACK 0.95.
5. Regrow (ProgressRules): fed by what players COULD sweep (`pace`), share grows with friends, cap 30 u/s per player (480 max), drops small piles. Storms and golden ash scale with players.
6. Parties: 5 min cooldown, re-arm needs a real dip, gifts only to players who swept in the last 2 min, capped to their own best zone.
7. Finds: roll budget 1.5/s per player; coins lowered (finds ~12% of income). Perfect Dodge +25% for 2 min.
8. Prices retuned with the supply-aware sim (`tests/island_sim.luau`); targets hold within +-30% solo, and 2/4/16-kid islands keep a fair share.
9. World: Hub and Gates build piece by piece (parented first), fallback SpawnLocation; gate prompt keys G / ButtonY.
10. Needs a Play test: snap-back feel on laggy phones, LinearVelocity bounce, regrow look with 16 players.

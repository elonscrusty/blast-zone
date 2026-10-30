# 32 Spectate after you die
- Done: server picks who an out player watches. Only out players (and late joiners) in Spawning/combat/Finished; living players are never sent a target.
- New rule `MatchRules.pickWatchTarget`: keep the current target while alive, else the player who eliminated you (`killedBy`, cleared at reset), else the first survivor. `SpectateCycle` (-1/1) walks the living list; rate limit unchanged.
- `SpectateTarget` payload now also has `name`; client shows "Watching <name>" (placeholder look, Claude Design restyles).
- Camera: `Config.Spectate` has styles same/wide/close; `Config.Spectate.style` picks one (default "same" = play view). `CameraRules.viewFor` chooses pitch and distance; `CameraSystem` uses it while `SpectateTargetId` is set. Snap on target swap already existed.
- carter has a 3D preview of A/B/C; change `style` when he picks.
- Arrows + Q/E existed (piece 05) and stay on `UiLayers.Spectate`.
- Tests: tests/match_rules, match_controller (killer first), movement (viewFor).
- Not run in Studio.
- Left: finish pick of style; look is placeholder.

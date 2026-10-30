# 18 Coins and unlock track
- One earned currency (name/look: `Config.Progression.look`, A Volts until carter picks; B and C are built as skins). Earned only from matches: `MatchSystem.RewardGranted` -> `ProgressService.onReward`, paid once per match key (`Profiles.matchReceiptKey`). Never from a client.
- Track = 6 tiers bought in order for coins (100-540); rewards are slide-trail and shot-tracer colors only. No combat power. Items: `src/shared/Progression/TrackDefs.luau` (saved ids, never rename).
- Rules are pure and Lune-tested: `ProgressRules`, `ProgressService` (talks to a Store), `MemoryStore` (stand-in), `ProgressText`. Roblox wiring: `src/server/Progression/ProgressionSystem.luau`.
- Saving: calls piece 17 (`Profiles.grantOnce/update/saveNow`, data in `data.progression`). If `Profile/Profiles` is missing it falls back to memory and the client says "Test mode: coins are not saved". Failed load = nothing paid, "Progress not loaded".
- Remotes (18 block): `ProgressRequest`, `UnlockRequest`, `EquipRequest`, `ProgressState`. Server checks price, order and ownership. Look is copied to Player attributes `CosmeticTrail` / `CosmeticTracer`.
- Client: `ClaimUiSystem` (strip under the Big Banner: coins, bar, UNLOCK/TRACK; lobby TRACK button), `TrackPanel`, 3D spinning `CoinView`, `CosmeticLook`. Small edits in other pieces: `SlideTrail.play` and `CombatFx.tracer` take the owner's color.
- Merge notes: `Config.Rewards.currencyName` is now "Volts" (a test keeps it equal to the look name). Merging with piece 17 (#15) conflicts only in text (`Config.luau`, `RemoteDefs.luau`, `tests/run.luau`): keep both.
- Tests: `tests/progression.test.luau` (pay-once, caps, order, afford, ownership, not-loaded; 4 deliberate breaks made it fail). Nothing run in Studio.
- Left: gun paint and more slots (piece 19 loadout). Coin is parts only. `selene` runs in CI. Waiting on carter's coin pick.

# G17 Counter bar (video 3 gap 17)
- Done: a top bar with several counters. Two now: Scrap (the main coin, piece 18, read only here) and Sparks (new, saved in `data.wallet`). List and order: `src/shared/Wallet/WalletDefs.luau` (saved ids, never rename). A new counter = one line there.
- Sparks are only earned: win = 3, 2nd/3rd (or shared 1st) = 1, once per match (`MatchSystem.RewardGranted`, receipt key `<match key>:sparks`). Numbers in `Config.Wallet`. Bots have no wallet.
- Not built on purpose: energy (gates play, not for kids), gems/Robux sales (no ids or prices made up). Sparks have no use yet: they wait for the shop (gap 18) and chests (gap 19).
- Server: `src/server/Wallet/WalletSystem.luau` (order 65). Other pieces call `WalletSystem.grant(player, id, amount, key)` (once per key), `WalletSystem.spend(player, id, amount)` (all or nothing, "tooPoor") and `WalletSystem.balance`. Nothing else changes a balance.
- Rules/service/tests-friendly parts: `shared/Wallet/` (WalletRules, WalletService, WalletMemoryStore, WalletBarModel). No profile module: runs in memory, bar says "Test mode: not saved".
- Remotes (G17 block): `WalletRequest` (ask, 1/s), `WalletState` (tell). Type: `WalletState` in Types. Scrap changes (`ProgressionSystem.Changed`) re-push the bar.
- Client: `src/client/Wallet/WalletBarSystem.luau`, PLACEHOLDER look through `Ui/Components` roles, `UiLayers.Calm`, top right, hidden while fighting. A counter that goes up pops. Claude Design restyles it.
- Saving: `data.wallet` created on demand through `Profiles.update` (no schema bump; a missing or broken table is repaired by `WalletRules.fill`).
- Tests: `tests/wallet.test.luau` (19 tests: list, rules, caps, pay once, spend, bar text); 2 deliberate breaks made it fail. Nothing run in Studio. Left: the look; the bag button from the video (gear slots, gap 15); a use for Sparks.

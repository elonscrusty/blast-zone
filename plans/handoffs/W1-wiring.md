# W1 Whole-game wiring check
- Goal: main is one game from lobby to match to results, with no piece left half plugged in.
- Audit (2026-10-30): all 76 System modules have start(); every require path resolves; no require cycles; one owner each for LoadCharacter, WalkSpeed and Health; every ScreenGui uses UiLayers; key binds do not clash (emote 1-4 only while the wheel is open, spectate Q/E only while spectating).
- Remotes: 41 asks each have exactly one server handler and a client sender; 44 tells are all sent. Two were never heard on the client: `VaultFx` and `PickupSpawned`.
- Fix: `client/Movement/SlideFxSystem` now draws the slide streak on other players' hops (`VaultFx`). `client/Pickups/PickupFxSystem` hears `PickupSpawned` (orbs still come by tag) so it never piles up unread.
- Guard: `tests/wiring.test.luau` reads src and fails on: a System without start/return, an ask with 0 or 2+ handlers or no client sender, a tell never sent or never heard, a remote used the wrong way, character loading outside `Match/MatchSystem`.
- New pieces (airdrop, chests, missions, crafting, big map, street life, currency bar): when this test fails after you merge main, plug in the missing half; do not loosen the test.
- Proof: Lune all pass, full-match tests pass, StyLua clean, rojo build ok. Selene in CI.
- Not proven: a real Roblox boot. In Studio Output, look for "[server] ... up (N systems)" and no "could not load" / "failed to start" lines.

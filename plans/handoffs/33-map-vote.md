# 33 Map vote (logic only)
- Players tap a map in the lobby; the server counts. Open: Results, Resetting, Waiting, Countdown. Locked at Spawning or when `takeWinner()` is called.
- Rules (pure, tested): `src/shared/MapVote/VoteBook.luau` (count, ties, no repeat on a tie) and `VoteFlow.luau` (phases, locking, leavers).
- Server: `src/server/MapVote/MapVoteSystem.luau`. One vote each, server checks the map is in the pool and the window is open. Counts go to everyone at most once a second.
- Remotes (RemoteDefs block 33): `MapVoteRequest(mapId)`, `MapVoteStateRequest`, `MapVoteState` (open, maps with counts, yourVote, nextMapId).
- Second-map hook: `MapVoteSystem.setPool({{id,name}})`; `MapVoteSystem.takeWinner()` returns the winning id or nil (then the normal rotation runs). It also calls `ArenaSystem.setChooser` (PR #34) and reads `Config.Arena.rotation` when they exist; without them the vote is just empty.
- Tie rule: random among the leaders, but never the map just played if another leader exists. Names for ids: `Config.MapVote.names`.
- Client: `src/client/MapVote/MapVoteClientSystem.luau` is a PLACEHOLDER (plain buttons on `UiLayers.MatchFlowExtra`, 48pt tall). Claude Design replaces the look; keep the `MapVoteState` / `MapVoteRequest` calls.
- Tests: `tests/map_vote.test.luau` (22). Full run 627 passed. stylua clean, rojo build ok. selene could not run here (no std dump); CI will.
- Left: Claude Design look (can reuse the 3D map previews); show the winner on the countdown screen using `nextMapId`.

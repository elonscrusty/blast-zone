# Rules for this repo

- Rojo + strict Luau (`--!strict` on every file). Code lives in `src/server`, `src/client`, `src/shared`.
- The server decides everything. Check every remote on the server.
- Saves go through `src/shared/SaveRetry.luau` (tries again, waits longer each time).
- Phone first: every control has a touch button.
- Before a PR: `stylua src tests`, `selene src`, `lune run tests/run`, `rojo build default.project.json -o BlastZone.rbxl`.
- No Play tests in Studio. Finish each piece as a PR; all pieces go in together, then carter plays.
- When a piece is done: mark it in `plans/NEXT-PIECES.md` and write a 10-line handoff in `plans/handoffs/`.
- carter presses Publish himself, only after he says "publish". Never make up Robux ids or prices.

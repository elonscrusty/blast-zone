# Piece 01: Foundation (loader, remotes, saving)

**Goal:** The base everything stands on, plus saved player data. This one lands first.
**Read first:** `plans/design/03-build-plan.md` (whole), `plans/design/02-design.md` (rewards, profile numbers).

## You own
- `src/server/Main.server.luau`, `src/server/Services.luau`, `src/server/Bus.luau`, `src/server/Systems/Data.luau`
- `src/client/Main.client.luau`
- `src/shared/Net.luau`, `src/shared/ProfileSchema.luau`, `src/shared/Config/Game.luau`, `src/shared/Config/Products.luau`
- tests: `tests/profile_schema.test.luau`, `tests/data_flow.test.luau`, `tests/bus.test.luau`

## Build
1. **Loader.** `Main.server` requires every ModuleScript in `Systems/` (sorted by name), calls `init()` on all, then `start()` on all. Each call in a `pcall`, errors printed with the system name. `Main.client` does the same for `Controllers/`. `Services.get(name)` returns a started system (error with a clear message if missing).
2. **Bus.** `Bus.on` / `Bus.fire` as in the build plan, typed with `BusEvents`. Use `Signal`. A listener that errors must not stop the others.
3. **Net.** Server: makes the folder `ReplicatedStorage.Remotes` and one remote per entry in `RemoteNames`. `Net.onServer(name, handler)` wraps the handler: per-player `RateLimit` (from `perSecond`), `pcall`, ignore bad calls quietly. `Net.fire(name, player, payload)` and `Net.fireAll(name, payload)`. Client: `Net.get(name)` waits for the remote; `Net.send(name, payload)`; `Net.onClient(name, fn)`. Function remotes: `Net.onInvoke(name, handler)`.
4. **Config/Game.luau.** All constants from the match-rules table in `02-design.md` (players 16, lobby wait 20, countdown 5, match cap 240, map size 300, grid 5, cell 60, first-gift cogs 100, trophy rules, etc.). Plain table, typed.
5. **Config/Products.luau.** A table of ideas (`cogs2x`, `bigChest`, `extraHero`) with `id = nil` and no prices. Nothing sells.
6. **ProfileSchema (pure).** `default(): Profile`, `migrate(raw: any): Profile` (fills missing fields, keeps `version`, clamps numbers, never errors on junk). Version 1.
7. **Data system.** Load with DataStore `Profiles` key `p<UserId>` through `SaveRetry`. Session lock (a `lockedBy` JobId field using `UpdateAsync`; if locked by another live server, kick with a short message after a few waits). Autosave every 60 s for dirty profiles, save on leave, `BindToClose` saves all (parallel, with a 25 s budget). Welcome gift (100 cogs) on first load. Provide `get`, `waitFor`, `update`, `changed`, and `Wallet.add/trySpend` exactly as in the contract. Send `ProfileUpdate` to the player after every change. If DataStore returns 403 / is off in Studio: use defaults, log once, do not save.
8. Keep the DataStore calls behind a small interface (`{load, save}`) so the flow can be tested with a fake store in Lune.

## Server checks
Wallet never goes negative, amounts must be finite integers, `reason` is a string. `update` runs `fn` in a `pcall` and re-clamps with `ProfileSchema.migrate` before keeping the result.

## Tests (Lune)
Schema defaults and migration from old/junk data. Bus ordering and listener errors. Data flow with a fake store: load, update, autosave, failure then retry, lock conflict, 403 path. Wallet edge cases.

## Done when
`stylua`, `selene`, `lune run tests/run`, `rojo build` pass; the contract for `Data`, `Bus`, `Services`, `Net` matches the build plan word for word; row 01 marked and handoff written.

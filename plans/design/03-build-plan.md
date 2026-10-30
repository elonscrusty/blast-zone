# Phase 4: Roblox build plan

Ten threads build this at the same time, so the rules below keep them from stepping on each other. Read this first, then your own brief in `plans/pieces/`.

## Ground rules
1. Follow `CLAUDE.md`. `--!strict` everywhere. The server decides everything. Phone first.
2. **One piece = one thread = the files its brief says it owns.** Never edit a file another piece owns. If you need a change there, tell the coordinator.
3. Files every piece may read but nobody but the coordinator edits: `src/shared/Types.luau`, `src/shared/RemoteNames.luau`, `src/shared/Signal.luau`, `src/shared/RateLimit.luau`, this folder.
4. Tests: add `tests/<name>.test.luau`. `tests/run.luau` finds them by itself, so nobody edits it.
5. Put the rules in pure modules (no `game`, no `workspace`) so Lune can test them. The Roblox code around them stays thin.
6. No Play tests in Studio. Proof = `stylua src tests`, `selene src`, `lune run tests/run`, `rojo build default.project.json -o BlastZone.rbxl` all pass, plus a clear read-through against the contract below.
7. Saves go through `src/shared/SaveRetry.luau`.
8. Never invent Robux ids or prices. Never print keys.
9. Finish: mark your row in `plans/NEXT-PIECES.md`, write `plans/handoffs/<NN-name>.md` (10 lines), tell the coordinator, stop.

## Folder layout (Rojo, already wired in `default.project.json`)
```
src/shared/            -> ReplicatedStorage.Shared   (both sides)
  Types, RemoteNames, Signal, RateLimit, SaveRetry     done by the coordinator
  Net.luau, ProfileSchema.luau, Config/Game.luau, Config/Products.luau   piece 01
  Config/<Thing>.luau                                  data tables, each owned by one piece
src/server/            -> ServerScriptService.Server
  Main.server.luau     loader (piece 01): requires every ModuleScript in Systems/, calls init() on all, then start() on all
  Services.luau, Bus.luau                              piece 01
  Systems/<Name>.luau  one system each: `Data`, `Match`, `Arena`, `Combat`, `Loot`, `Bots`, `Meta`
src/client/            -> StarterPlayerScripts.Client
  Main.client.luau     loader (piece 01): same idea for Controllers/
  Controllers/<Name>.luau   `Controls`, `CameraRig`, `Hud`, `Effects`, `Menu`
tests/                 *.test.luau
```
Each system is a ModuleScript that returns a table with `init()` and `start()`. Cross-system calls go through `Services.get("Combat")` after `start()` has begun (never at the top of the file), so load order never matters.

## Contract: who offers what
All signatures are the promise. Build against them even if the other piece has not landed yet (stub it in your tests).

### `Data` (piece 01), `Systems/Data.luau`
```
Data.get(player: Player): Profile?            -- nil until loaded
Data.waitFor(player: Player): Profile?        -- yields, nil if the player left
Data.update(player: Player, fn: (Profile) -> ()): boolean   -- the ONLY way to change a profile; marks it dirty
Data.changed: Signal<(Player)>                -- fired after any update; also sends ProfileUpdate
Wallet.add(player, currency: Currency, amount: number, reason: string): boolean
Wallet.trySpend(player, currency: Currency, amount: number, reason: string): boolean  -- false if too poor, never goes below 0
```
Studio with no API access (403) must still work: use defaults, do not save, keep playing.

### `Match` (piece 02), `Systems/Match.luau`
```
Match.getPhase(): Phase
Match.getFighters(): { Fighter }      -- everyone in the current match, alive or not
Match.getAlive(): { Fighter }
Match.isAlive(id: FighterId): boolean
```
Fires on the Bus: `MatchPhase`, `FighterSpawned`, `MatchEnded`. Listens for `FighterEliminated`.

### `Arena` (piece 03), `Systems/Arena.luau`
```
Arena.build(themeName: string)            -- once at start; builds the floor, props, walls out of Parts
Arena.getSpawnPoints(): { Vector3 }       -- 16 spots, well spread
Arena.getChestSpots(): { Vector3 }        -- 14 spots
Arena.cellAt(pos: Vector3): Vector2?      -- grid cell (1..5, 1..5) or nil when outside
Arena.cellCenter(cell: Vector2): Vector3
Arena.isBlasted(cell: Vector2): boolean
Arena.startMatch()                        -- resets props, starts the Blast schedule (listens to MatchPhase=Playing)
Arena.splash(pos: Vector3, radius: number, damage: number): ()   -- Combat calls this for rockets: hurts blocks/barrels
```
Fires `BlastBoom` on the Bus. Pit damage is dealt through `Combat.applyDamage`.

### `Combat` (piece 04), `Systems/Combat.luau`
```
Combat.register(fighter: Fighter, loadout: Loadout)
Combat.unregister(id: FighterId)
Combat.setIntent(id: FighterId, intent: Intent)            -- humans via the Intent remote, bots direct
Combat.act(id: FighterId, action: Action): boolean          -- "heavy" | "dodge" | "heal"; checks cooldown and alive
Combat.applyDamage(id: FighterId, amount: number, sourceId: FighterId?, weapon: string): number  -- returns damage really dealt (shield first)
Combat.heal(id: FighterId, amount: number)
Combat.addShield(id: FighterId, amount: number)
Combat.addKits(id: FighterId, n: number)
Combat.addReloadBoost(id: FighterId, seconds: number)       -- "Quick reload" pick-up
Combat.setPerks(id: FighterId, perks: Perks)                -- recomputes stats
Combat.getState(id: FighterId): FighterState?
```
Combat owns Hp, Shield, projectiles, cooldowns, ammo, the dodge and the movement-speed check. It fires `FighterDamaged` and `FighterEliminated`. It sets these Attributes on the model: `Hp`, `MaxHp`, `Shield`, `Kits`, `Ammo`, `Alive`, `HeavyReadyAt`, `RollReadyAt`, `ReloadingUntil` (times use `workspace:GetServerTimeNow()`).

### `Loot` (piece 05), `Systems/Loot.luau`
```
Loot.getXp(id: FighterId): (level: number, xp: number, needed: number)
Loot.awardXp(id: FighterId, amount: number)
```
Listens to `MatchPhase`, `FighterEliminated`. Fires `XpGained`, `LevelUp`. Calls `Combat.setPerks` and `Combat.heal/addShield/addKits`. Uses `Arena.getChestSpots()`. Shows `PerkOffer`, answers `PickPerk`.

### `Bots` (piece 06), `Systems/Bots.luau`
```
Bots.create(count: number): { Fighter }     -- makes bot models (Humanoid rig out of Parts) and names; Match then registers them
Bots.remove(id: FighterId)
Bots.removeAll()
```
Bots call only `Combat.setIntent`, `Combat.act` and read `Match`, `Combat.getState`, `Arena.cellAt/isBlasted` like a player would. They never cheat on damage.

### `Meta` (piece 10), `Systems/Meta.luau`
Owns the `Menu` RemoteFunction. Commands: `selectHero`, `upgradeWeapon`, `upgradeHero`, `unlockHero`, `openChest`, `claimDaily`, `claimLogin`, `getLeaderboard`, `finishTutorial`. Every command checks on the server, changes things only with `Data.update` and `Wallet`, and replies `{ok, reason?}`. Listens to `MatchEnded` to add task progress (matches played, kills, chests) and writes trophies to an OrderedDataStore leaderboard.

## Bus (server only, piece 01)
```
Bus.fire(name: keyof BusEvents, payload)
Bus.on(name, fn): () -> ()      -- returns the disconnect function
```
Names and payload shapes: `BusEvents` in `src/shared/Types.luau`.

## Remotes
Names, kinds, directions and rate limits: `src/shared/RemoteNames.luau`. Piece 01's `Net` creates them from that list in `ReplicatedStorage.Remotes`, and wraps every c2s handler in the `RateLimit` and a `pcall`. A piece never creates a RemoteEvent by hand.

## Fighter models
A fighter is a Model with a `Humanoid`, a `HumanoidRootPart` and a few Parts (body, big head, wind-up key). Players use their own character, restyled by Combat on register (hide accessories, add the key). Bots are built by `Bots` with the same shape. Camera, HUD and effects only read the Attributes.

## Build order (all ten start now; this is the merge order)
1. Piece 01 first. It has no one to wait for. Others can rebase on it when it lands.
2. Pieces 02-06, 07-10 in any order after that.
3. Every piece is a PR into `main`. They all wait until all ten are ready, then go in together (carter's rule). Then carter plays.

Smallest playable version = pieces 01 + 02 + 03 + 04 + 07 together (join, fight on a floor with the blast grid, move and shoot on a phone). 05, 06, 08, 09, 10 make it a full game.

## Server-authoritative checklist (every piece)
- Every c2s payload: check type, check range, check the player is allowed right now (alive? in the match? cooldown?).
- Never trust positions, damage, ids or counts sent by a client.
- A client can ask. It cannot tell.
- Anything random (chests, perks, bots) runs on the server. Odds sit in a `Config/` table.
- Rate-limited by `Net`, not by hand.

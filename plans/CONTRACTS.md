# Contracts (piece 01)

The shared rules every piece builds against. Change them only through piece 01 / the coordinator.

## Who owns what (no overlap)

| Piece | Owns (create files only here) |
| --- | --- |
| 01 | `src/shared/*` (except what is noted), `src/server/Core/`, `src/client/Core/`, `Main.*.luau`, `default.project.json`, `tests/{harness,run,config,guard,core}*` |
| 02 | `src/server/Movement/`, `src/client/Movement/`, `src/shared/Movement/` (slide/camera maths used by both sides), `tests/movement*.test.luau`; may add keys inside `Config.Movement`, `Config.Camera`, `Config.Slide` only |
| 03 | `src/server/Combat/`, `src/client/Combat/`, `tests/combat*.test.luau` |
| 04 | `src/server/Arena/`, `src/client/Arena/`, and may add a `ServerStorage` mapping to `default.project.json` |
| 05 | `src/server/Match/`, `src/client/Match/` |
| 06 | `src/server/Zone/`, `src/client/Zone/` |
| 07 | `src/server/Pickups/`, `src/client/Pickups/` |
| 08 | `src/server/Upgrades/`, `src/shared/UpgradeDefs.luau` |
| 09 | `src/server/Bots/` |
| 10 | `src/client/Hud/`, `src/client/Controls/`, `src/client/Settings/` |

Each piece adds its own tests as `tests/<name>.test.luau` and ONE `require("./<name>.test")` line in `tests/run.luau`
(add the line in alphabetical order to keep merges easy). Edit only your block in `src/shared/RemoteDefs.luau`
and your own constants in `src/shared/Config.luau`. New shared type? Add it to `Types.luau` at the end of its section.

## Starting a system

Any ModuleScript named `<Something>System` anywhere under `src/server` or `src/client` is started automatically:

```lua
--!strict
local MovementSystem = {}
MovementSystem.order = 100 -- optional; lower starts first
function MovementSystem.start() ... end
return MovementSystem
```

One failing system never stops the others. No need to edit `Main.*.luau`.

## Requiring things

- Same folder / pure shared code: `require("./Name")` (Roblox require-by-string; Lune tests use the same text).
- From server or client code: `local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")` then `require(Shared.Config)`.
- Server core: `require(script.Parent.Parent.Core.Damage)` style, or `ServerScriptService.Server.Core`.
- Keep pure logic in files that need no Roblox services so `lune run tests/run` can test them.

## Remotes (`shared/RemoteDefs.luau`)

- All remotes are RemoteEvents. No RemoteFunctions.
- Server: `Net.onRequest("FireRequest", function(player, origin, dir, seq) end)`. Rate limit and argument checks
  (finite numbers, unit vectors, ids) are done before your handler. You still check phase, ownership, ammo, cooldowns.
- Server to client: `Net.fire(name, player, payload)`, `Net.fireAll`, `Net.fireMany`.
- Client: `Net.send(name, ...)`, `Net.on(name, handler)` from `src/client/Core/Net.luau`.
- Never accept damage, XP, rewards or hit results from a client.
- Times in payloads are server time (`workspace:GetServerTimeNow()`).

## Identity

- `ParticipantId` is `"p<userId>"` for players and `"b<n>"` for bots (`Ids.luau`). Never use a bare UserId as identity.
- `matchId` goes up by one per match (`MatchContext`). Put it on every delayed event (projectile, timer, offer) and drop it if `not MatchContext:isCurrent(id)`.
- `Core/Participants` is the roster (enroll, alive list, markEliminated). Piece 05 enrolls and clears. Bots are enrolled like players with `enrollBot`.

## Damage (`Core/Damage`)

```lua
Damage.apply({ matchId = id, targetId = "p1", amount = 10, cause = "bullet", sourceId = "p2", weaponId = "volt_pistol" })
```

- Everything that hurts someone (bullets, explosions, zone, bots) goes through `apply`. Nothing else changes health.
- The router already drops: stale match, non-combat phase, bad amounts, dead or unknown targets, and a second elimination of the same target.
- Piece 03 calls `Damage.bind(backend)` once. `backend(request) -> { applied, reason?, dealt, remaining, eliminated }`. The backend owns health numbers and must not fire events.
- Listen: `Damage.Damaged:connect(function(e) ... end)`, `Damage.Eliminated:connect(function(e) ... end)` (`EliminationEvent` in Types). The roster flips `alive = false` before listeners run.
- Zone damage: `cause = "zone"`, `sourceId = nil`. Disconnect: piece 05 removes the participant, not via Damage.

## Match phase (`Core/MatchContext`)

Piece 05 only calls `beginMatch()` and `setPhase(phase, seconds?)`. Everyone else reads `getPhase()`, `getMatchId()`,
`isCombat()`, `isCurrent(id)` and listens to `PhaseChanged`/`MatchStarted`. Legal moves are in `MatchPhase.luau`; illegal ones return false.

## Run XP (`Core/RunXp`)

`award(participantId, reason)` where reason is `containerBreak`, `orbPickup` or `elimination` (values in `Config.Xp.rewards`).
Enrolling a participant resets them to level 1. `LevelUp` fires with the pending offer count. Piece 08 spends offers with `takeOffer(id)`.
Piece 07 sends the `XpState` remote from `Changed`.

## Stats (`Core/EffectiveStats`)

Movement and combat read `EffectiveStats:get(participantId)` (a `StatSheet`) instead of `Config` for anything an upgrade can change.
Piece 08 calls `setProvider(fn)` and `invalidate(id)`. Until then everyone has base stats.

## Geometry rules (see `Config.Tags`, `Config.ShotRules`)

- `BlocksShots` tag: walls, solid cover, crates. Blocks shots and movement.
- `LowCover` tag (fences, low barriers): blocks movement only. Bullets pass.
- Roofs are `Roof`-tagged, `CanCollide=false`, `CanQuery=false`. Hiding them never changes gameplay.
- Spawns: `ArenaSpawn` tag (>= `Config.Arena.minSpawns`). Container spots: `ContainerSpot`.
- Characters get `ParticipantId`/`IsBot` attributes and the `Participants` collision group (`Core/CollisionGroups.apply`).

## Checks before a PR

`stylua src tests`, `selene src`, `lune run tests/run`, `rojo build default.project.json -o BlastZone.rbxl`.

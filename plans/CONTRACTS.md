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
| 17 | `src/server/Profile/`, `src/shared/Profile/`, `tests/{profile,fake_datastore}*`; own blocks `Config.Profile` and the 17 remotes |
| 10 | `src/client/Hud/`, `src/client/Controls/`, `src/client/Settings/` |
| 24 | `src/server/Stats/`, `src/client/Stats/`, `src/shared/Stats/`, `tests/stats*.test.luau`; `Config.Stats`, the 24 block in `RemoteDefs` |
| 19 | `src/server/Lobby/`, `src/client/Lobby/`, `src/shared/Loadout*.luau`, `src/shared/LobbyLayout.luau`, `tests/lobby.test.luau`; added `StatBook.addModifier` |

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
- Selene accepts these string requires because of `luau_require.yml` + `std = "luau_require+roblox"` in `selene.toml` (commit 3b79613). Your branch must contain that commit (merge the piece 01 branch) or CI shows `require` errors. Do not change `selene.toml`.
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
Damage:apply({ matchId = id, targetId = "p1", amount = 10, cause = "bullet", sourceId = "p2", weaponId = "volt_pistol" })
```

- Everything that hurts someone (bullets, explosions, zone, bots) goes through `apply`. Nothing else changes health.
- The router already drops: stale match, non-combat phase, bad amounts, dead or unknown targets, and a second elimination of the same target.
- Piece 03 calls `Damage:bind(backend)` once. `backend(request) -> { applied, reason?, dealt, remaining, eliminated }`. The backend owns health numbers and must not fire events.
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

## Saving (`Profiles`, piece 17)

Only `src/server/Profile/Profiles.luau` talks to DataStore. Read the header of that file for the calls:
`get`, `update(player, fn)`, `grantOnce(player, key, fn)` (use `matchReceiptKey(matchId)` for match rewards), `getFlag/setFlag`,
`saveNow`, `retryLoad`, and the `Loaded` / `Released` / `StatusChanged` signals. A profile that did not load is nil and
refuses every write; never fall back to defaults. Items are saved by stable lowercase ids. Details: `plans/handoffs/17-saving.md`.

## Screen layers (piece 22)

Every `ScreenGui` sets `DisplayOrder` from `src/client/Ui/UiLayers.luau`, never a bare number.
`tests/ui_layers.test.luau` fails the build if a file in `src/client` makes a ScreenGui without `UiLayers`.

| Layer | Value | What goes there |
| --- | --- | --- |
| `ZoneTint` | 5 | zone screen edges and arrow (no taps) |
| `TouchControls` | 9 | thumb sticks and buttons |
| `Hud` | 10 | health, minimap, timer, gear |
| `Calm` | 15 | between-fight widgets that are not lobby buttons |
| `Popups` | 20 | upgrade cards, bots banner |
| `Spectate` | 30 | spectate arrows |
| `MatchFlow` | 50 | lobby, countdown, banners, results |
| `MatchFlowExtra` | 55 | add-ons drawn over results (coins strip) |
| `Modal` | 100 | full panels with a dim: settings, track, loadout, shop |
| `Onboarding` | 110 | first-time intro (blocks everything) |
| `Toast` | 120 | short messages like "Saved" (no taps) |

- Full panels also call `ModalGate.opened(name, closeFn)` when shown and `ModalGate.closed(name)` when hidden,
  so only one panel is open at a time.
- Lobby buttons never get their own ScreenGui or numbers. Put them in a slot:
  `button.Size = UDim2.fromScale(1, 1); button.Parent = LobbyMenu.slot("track")`. Slots live in
  `src/client/Ui/LobbyLayout.luau` (`status`, `play`, `settings`, `track`, `looks`); add a slot there and the tests
  check it fits on every phone. The top of the lobby (above `LobbyLayout.bannerBottom`) is for banners.
- Pieces placed with `UiKit.place` keep their distance to their screen edge in height units, so phones from 16:9
  to 21:9 get the same spacing; tablets get the 16:9 layout shrunk.
- Open PRs to switch when they land: #16 intro `55` -> `UiLayers.Onboarding`, save strip `52` -> `UiLayers.Toast`;
  #17 coin strip `55` -> `UiLayers.MatchFlowExtra`, track panel `60` -> `UiLayers.Modal` (+ `ModalGate`),
  lobby TRACK button -> `LobbyMenu.slot("track")`; #20 look picker `15` -> `UiLayers.Calm` (or `LobbyMenu.slot("looks")`).

## Look and logic (UI system)

Claude Design makes the whole UI, so a screen's **look** and its **logic** live apart and a new design drops in
without touching game code.

| Layer | Files | May do | Must not do |
| --- | --- | --- | --- |
| Look | `src/client/Ui/Tokens.luau`, `src/client/Ui/Skins/*` | colours, fonts, text sizes, corners, shadows, motion | know about any screen |
| Parts | `src/client/Ui/Components.luau` (+ `Hud/UiKit`, `Hud/Theme` for older code) | build screen, panel, text, button, bar, modal from **roles** | hold game state |
| Layout | `Hud/Layout.luau`, `Ui/LobbyLayout.luau`, `Ui/UiLayers.luau` | where things sit, which layer | colours or fonts |
| View | `*View.luau`, `*Panel.luau`, the drawing half of a `*System` | put parts in layout spots, show a model | pick a colour, font or size; decide anything |
| Model / System | `*Model.luau`, `*System.luau` logic, `Core/Net` | read remotes, keep state, send requests | make Instances for looks |

- A view asks for a role (`"accent"`, `"title"`, `"primary"`), never `Color3.fromRGB`, a `"#RRGGBB"` hex, `Enum.Font.*`
  or `Config.Palette`. `tests/ui_tokens.test.luau` fails on new files that do. 3D world art (guns, effects, zone wall,
  coin model) keeps its own colours and is listed there as `WORLD_ART`.
- Older screens are listed as `LEGACY`. When you touch one, move it onto `Ui/Components` and delete its line.
  The test fails if a listed file is already clean, so the list only shrinks.
- Every skin has every key in `Tokens.COLOR_KEYS` etc. and passes `Tokens.check` (fonts are Roblox built-ins, ink on
  panel 4.5:1 contrast, text on gold or coral 3:1). New skins come from Claude Design JSON through
  `lune run tools/import-design design/<id>.json` (template: `design/skin-template.json`).
- Full panels use `Components.modal` (Modal layer + `ModalGate` + DONE). Buttons use `Components.button`
  (never under `Tokens.MIN_TOUCH` = 48 design points; tap, click and gamepad A all fire `onPress`).
- Every screen and its states, data and remotes: `plans/UI-SCREENS.md`. Brief for Claude Design:
  `plans/UI-DESIGN-BRIEF.md`. Bringing it back: `plans/UI-BRING-BACK.md`.


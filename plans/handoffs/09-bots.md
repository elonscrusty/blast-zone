# 09 Test bots
- Done: labeled "[BOT] name" Crash Dummies (carter's pick: yellow, black legs, chest bullseye, hazard tag). A lone player waiting gets "Alone? Bots join in 10s" plus an "Add bots now" button; bots top the match up to `Config.Match.targetParticipants`.
- Code: `src/server/Bots/` (BotBrain thinking, BotRunner timer, BotRoster auto-fill rules, BotTuning, BotPorts, BotRoblox body, BotSystem wiring), `src/client/Bots/BotBannerSystem`. Remotes `AddBotsRequest`, `BotFillState` (09 block).
- Same rules as players: no health/damage/speed/ammo numbers of their own (`BotTuning.from` refuses `hiddenStatAdvantage = true`). Sight uses the shot-blocking test, so no seeing or shooting through walls.
- Match flow: bots are asked for with `MatchSystem.requestBots(n)` and placed on `MatchSystem.SpawnAssigned` (piece 05). I clear bodies on Waiting/Resetting.
- Needs from others: `Combat/BotPort` (fire, reload, state, registerBotBody, optional shotParams) and `Movement/BotPort` (slide, slideReady, registerBotBody). Without Combat/BotPort bots stand still and warn once.
- Uses piece 06 `ZoneSystem.getSample()` and piece 07 `PickupSystem.tryClaim` (bots grab orbs they stand next to).
- Tests: `tests/bots.test.luau` (sight, walls, reaction delay, reload, zone, flee, loot, stuck, auto-fill, runner). Nothing run in Studio; the Roblox-side rig and wiring are untested until carter plays.
- Left: bots use no pathfinding (stuck bots sidestep); no explosive-weapon logic; the two looks carter did not pick (Tag Bot, Hologram Bot) are not built as skins.

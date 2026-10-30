# 08 Upgrade choices
- Done: 9-upgrade catalogue + all stat maths (`shared/UpgradeDefs`), per-match state and pick checks (`server/Upgrades/RunUpgrades`), wiring (`UpgradeSystem`), cards (`client/Upgrades/UpgradeCardsSystem`).
- Flow: RunXp.LevelUp -> 3 cards -> UpgradeChoose(offerId, optionIndex) -> checked -> takeOffer + EffectiveStats:invalidate. Extra offers wait (Config.Upgrades.queueMax); bots pick at random after ~1-2 s.
- Stats are always base + stacks in a fixed order (add, pct, mult) with hard limits, never a running multiply. Changing a number: only `UpgradeDefs.list` / `limits`.
- Picks refused: wrong or old offer id, bad index, eliminated, wrong phase, tap within 0.35 s of the card appearing. Stacks and offers reset every match (Participants.Enrolled / phase Resetting).
- Cards: carter picked "Bottom Row" in Street Sticker style, x 26%-74%, y 76%-96% (agreed with the HUD thread). Keys 1-3, D-pad left/up/right, tap. Icon tiles use short text labels until real icon art exists.
- Added two optional fields to `Types.UpgradeOption` (`change`, `kind`) and a doc tweak in my RemoteDefs block. Mortar upgrades (Bigger Boom) only appear when `Config.Features.explosiveWeapon` is on.
- Tests: `tests/upgrades.test.luau` (68 pass overall). Not run in Studio: server wiring and the card UI only get exercised when carter plays. Selene was not run here (no API dump); CI runs it.
- Open: real icon art; match colours to `Hud/Theme.luau` once it exists; "postpone" is just ignoring the cards (they stay until picked).
- Needs: piece 05 to call Participants enroll/eliminate and set phases; piece 03/02 to read `EffectiveStats:get(id)`; piece 07 sends XpState (the "+N waiting" chip uses it).

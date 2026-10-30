# Every screen and UI piece

The full list Claude Design has to style. Main = on `main` now. A PR number = still in that open PR.
Code that draws each one is under `src/client/`. Rule for new code: `plans/CONTRACTS.md`, "Look and logic".

## Sizes (same for every screen)

| Device | Design size | How it scales |
| --- | --- | --- |
| Phone (first) | **780 x 360 points**, landscape, 19.5:9 | Everything scales with screen **height** and hugs its nearest edge. 16:9 to 21:9 phones keep the same spacing. |
| Tablet | 4:3 | The 16:9 layout, shrunk evenly. |
| PC | 1920 x 1080 (and any size) | Same layout x3 by height. Mouse hover = slightly lighter fill. Keys shown on hints (WASD, Space, R, Q, 1-3). |
| Controller | Same as PC | One button has a **focus ring** (thick gold outline) in every menu. Hints show A / B / X / Y, L1 / R1, D-pad. |

Hard rules: thumb targets **48 points or more**. Text never under 9 points. Keep clear in a fight:
the **player box** (screen centre, 120 x 120) and the **cards band** (bottom centre, x 26-74%, y 76-96%).
Thumbs own both bottom corners (left: move, right: aim and fire). Phone notch: the safe area is respected.

## Layers (bottom to top, from `Ui/UiLayers.luau`)

Zone tint 5, touch controls 9, HUD 10, calm widgets 15, popups 20, spectate 30, match flow 50,
results add-ons 55, full panels 100, first-time intro 110, toasts 120.

## Screens

| # | Screen | Where / when | States | Data shown | Remotes (server decides) | Layer | Code |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Combat HUD: vitals** | top-left, in a fight | normal, low health (coral pulse), hurt (red edge), level-up pending (gold dot) | health now / max, run level `LV3`, XP bar | HealthState, XpState | Hud | Hud/HudView (main) |
| 2 | **HUD: status chips** | top centre | normal, zone warning, zone closing, sudden death | players left `7 LEFT`, zone timer `0:24` | MatchState, ZoneState | Hud | Hud/HudView (main) |
| 3 | **HUD: warning line** | under the chips, one at a time | danger (coral), warn (gold), info (cream) | OUTSIDE THE ZONE, SUDDEN DEATH, LOW HEALTH, RELOAD!, ZONE CLOSING IN 5, notice text | (from HUD data) | Hud | Hud/Warnings (main) |
| 4 | **HUD: minimap** | top-right circle | normal, outside zone (arrow to safe circle) | you, safe circle, next circle | ZoneState | Hud | Hud/HudView (main) |
| 5 | **HUD: weapon panel** (also the swap button) | right, above fire stick | ready, low ammo, empty, reloading (fill), one weapon (no swap pips) | weapon name, ammo / magazine, slot pips 1-2 | AmmoState, SwitchWeaponRequest | Hud | Hud/HudView (main) |
| 6 | **HUD: hit feedback** | screen edges + centre | hit taken (edge + arrow), hit landed (marker) | direction, strength | DamageTaken, HitConfirm | Hud | Hud/HudView (main) |
| 7 | **Settings gear** | top-left, under vitals (36 pt, the one small button) | normal, pressed | - | - | Hud | Hud/HudSystem (main) |
| 8 | **Touch controls** | both bottom corners, phones only | idle ring, held, floating stick (#18), cooling down | move stick, aim+fire stick, Slide (cooldown ring), Reload | SlideRequest, ReloadRequest, FireRequest | TouchControls | Controls/TouchControls (main, #18) |
| 9 | **Upgrade pick chips** | by the aim thumb while cards are up (#18) | hidden, 1-3 chips | chip number 1-3 | UpgradeChoose (via cards) | TouchControls | Controls/TouchControls (#18) |
| 10 | **Upgrade cards** ("Bottom Row") | bottom centre band, during the fight | hidden, offer in (taps ignored 0.35 s), picked, more waiting `+2` | icon, name, short text, real numbers `Reload 1.2s -> 0.96s`, stacks `2/5`, kind (weapon / move accent) | UpgradeOffer, UpgradeChoose, UpgradeApplied | Popups | Upgrades/UpgradeCardsSystem (main) |
| 11 | **Bots banner** | top band | hidden, counting down, button pressed | "Alone? Bots join soon", seconds, `Add bots now` | BotFillState, AddBotsRequest | Popups | Bots/BotBannerSystem (main) |
| 12 | **Enemy health bars** | over heads in the 3D world | hidden, showing for a few seconds after a hit, spawn shield (#21) | health fraction | (character attributes) | world billboard | Combat/HealthBars (main) |
| 13 | **Lobby menu** | lobby only, slots `status`, `play`, `settings`, `track` (shown as REWARDS), `looks` | waiting, ready, match starting, too few players | status line, PLAY, SETTINGS, REWARDS | PlayRequest, MatchState | MatchFlow | Match/ResultsClientSystem + Ui/LobbyMenu (main, #24) |
| 14 | **Lobby stations** (3D Crosswalk Plaza) | world prompts at PLAY gate, Settings kiosk, Rewards board, Loadout garage | far, near (prompt shows), pressed | station name, key / button hint | same as the lobby buttons | world billboard | lobby thread (stage 2, 19) |
| 15 | **Countdown + phase banners** | top centre | get ready 3-2-1, FIGHT!, final pressure, match over | big word, seconds | MatchState, Announce | MatchFlow | Match/ResultsClientSystem (main) |
| 16 | **Kill feed** | top right, under the minimap, ends above the player | 0-3 lines fading | `Name -> Name` | Announce (kind = kill) | MatchFlow | Match/ResultsClientSystem (main) |
| 17 | **Eliminated banner** | centre | shown 2-3 s after you are knocked out | ELIMINATED, place `#4`, who did it, hitters list | Eliminated, DefeatSummary | MatchFlow | Match/ResultsClientSystem (main) |
| 18 | **Spectate bar** | bottom centre (out of the fight) | watching someone, nobody to watch | name of who you watch, < > arrows (Q / E, L1 / R1) | SpectateTarget, SpectateCycle | Spectate | Match/SpectateClientSystem (main) |
| 19 | **Results** ("Big Banner") | full screen after the match | win, lose, draw, abandoned, READY! (pressed) | giant title `#1 WINNER!`, three numbers (place, knock-outs, time alive), reward, PLAY AGAIN, lobby | Results, ReplayRequest, ReturnToLobbyRequest, ClaimResults | MatchFlow | Match/ResultsClientSystem + ResultsText (main) |
| 20 | **Scrap strip** under the results | under the results column | loading, paid `+40 Scrap`, can unlock, not enough yet | Scrap gained, progress bar to the next reward, UNLOCK or REWARDS | ProgressState, ProgressRequest | MatchFlowExtra | Progression/ClaimUiSystem (#17) |
| 21 | **Rewards panel** (the unlock track; say "Rewards", never "track") | full panel | loading, list, item: locked / UNLOCK (can afford) / WEAR / WORN, refused message | Scrap total, free looks, six tiers, prices from Config only | UnlockRequest, EquipRequest, ProgressState | Modal | Progression/TrackPanel (#17) |
| 22 | **Scrap coin** | spinning 3D coin in the strip and panel | spinning | - | - | (inside 20, 21) | Progression/CoinView (#17) |
| 23 | **Look picker** | lobby side slot `looks` | 3 looks (Runner, Courier, Spark), worn, pressed | look name, small 3D preview | SetLookRequest | MatchFlow slot | Character/LookPickerSystem (#20) |
| 24 | **Settings panel** | full panel | open, slider dragging, controller focus on a row | Music, Effects, Camera shake, Fewer flashes, HUD size, Aim speed, Button size, Left-handed, Floating sticks (#18), DONE | (local only for now) | Modal | Settings/SettingsPanel (main, #18) |
| 25 | **First-time intro** ("Four Tiles") | over the lobby, first visit only | showing, skipped, GOT IT | four tiles: move, aim, fire, slide, with the right words for phone / PC / controller | ProfileStatus, SetFlagRequest | Onboarding | Onboarding/IntroView (#16) |
| 26 | **Save message** ("Top Strip") | top band, never blocks play | loading (gold, no button), failed (coral, TRY AGAIN), lost (coral) | one headline, one short line | ProfileStatus, RetryProfileLoadRequest | Toast | Onboarding/StatusStripView (#16) |
| 27 | **Invite button** | lobby and while watching | normal, pressed (opens Roblox's own invite box) | INVITE | (Roblox SocialService) | MatchFlow slot | Social/InviteButtonSystem (#22) |
| 28 | **Zone screen tint** | screen edges when outside the zone | off, outside (red edges + arrow) | arrow to safety | ZoneState | ZoneTint | Zone/ZoneHud (main) |
| 29 | **Toasts** | top centre, no taps | short message 2 s | "Saved", notices | Notice | Toast | (new, uses Components) |
| G20 | **Season pass** | lobby slot `season` (PASS button) opens a full panel | loading, tiers locked / TAKE / DONE, paid cell SOON (nothing sells it yet), TAKE ALL, dot on the button when something is ready, toast `TAKEN!` | TIER n/20, time left (`Ends in 3d 5h`), bar to the next tier, free and paid reward per tier (`+25 Scrap` or a look name) | SeasonRequest, SeasonClaimRequest, SeasonState | Modal + Toast | Season/SeasonUiSystem (G20) |

Not on screen (no look needed): audio (#13), anti-cheat reset lock (#23), performance (#14).

## Words on buttons

PLAY, PLAY AGAIN, READY!, SETTINGS, REWARDS, UNLOCK, WEAR, WORN, LOCKED, DONE, GOT IT, Skip, TRY AGAIN,
INVITE, Add bots now, PASS, TAKE, TAKE ALL, SOON. Coins are called **Scrap**. Prices come from the game's Config, never made up.

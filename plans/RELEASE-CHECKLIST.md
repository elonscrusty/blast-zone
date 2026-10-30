# Release checklist (piece 20)

Circuit District (placeholder name, see `Config.Game.Name`). Read top to bottom before Publish.
Nobody here presses Publish. carter does, only after saying "publish".

Status words: **[ ]** not done, **[x]** done and seen working. Nothing below is ticked yet because nothing has been played.
Claude never runs Play in Studio (project rule). Every "should see" line is for carter to confirm by playing.

Written against the integration branch with Phases 1-3 plus pieces 17 (saving) and 20 (this). Re-read the
"Known limits" section after the Phase 4 and 5 pieces land; some items will be gone and new ones will appear.

## 1. Before you open Studio

- [ ] The one big PR is merged (or you are on its branch) and CI is green.
- [ ] On the branch: `stylua --check src tests`, `selene src`, `lune run tests/run`, `rojo build default.project.json -o BlastZone.rbxl` all pass.
- [ ] `BlastZone.rbxl` opens in Studio with no red errors in Output on load.
- [ ] Output shows `[client] ... up` and `[server] ... up` lines and no `failed to start` line for any system.

## 2. Things that need your eyes (carter)

| What | Why it is yours |
| --- | --- |
| Press Publish | You press it, after you say "publish". |
| Game name | "Circuit District" is a placeholder and not checked for availability. Change `Config.Game.Name` and the place name together. |
| Robux ids and prices | None exist. Nothing in the game sells anything. Never invent one. |
| Security / API settings | Studio "Enable Studio Access to API Services" and the game's "Allow API access" are settings you change. Steps are in section 5. |
| Max Players (25 fighters) | The file asks for 25 (`default.project.json`), but check it once. Studio: Home tab > Game Settings > Players > Maximum Players = 25 > Save. Or on the Creator Hub: your experience > Places > the place > Settings > Max Players = 25. Never below 8. Bots fill the rest, so a small server still works. |
| Final numbers | All tuning lives in `src/shared/Config.luau`. Change a number there, not in code. |

## 3. Manual multiplayer test scenarios (brief section 26)

Use Studio **Test > Local Server** with 2 or 3 clients (one client can be a phone-sized emulator). Bots can stand in
when you need a third body: they are labelled `[BOT]` and follow player rules.
For each one: do it, look, tick the box, and write what you saw if it was wrong.

1. **Two players shoot at one another.**
   - Do: both press PLAY, fight in the open.
   - Should see: both screens agree on who was hit, damage numbers match, one winner, no double kill.
   - [ ]
2. **One shoots from behind a wall.**
   - Do: stand with a solid wall (not a low fence) between you and a rival, fire at them.
   - Should see: shots stop at the wall, no damage. Over a low fence or low cover the shot does pass (walls block, low cover does not).
   - [ ]
3. **Both contest one pickup.**
   - Do: break a crate with two players close, both walk onto the orb.
   - Should see: only one player gets the XP. The breaker has 1.5 s first dibs. The orb is gone for the other player.
   - [ ]
4. **A player slides into a corner.**
   - Do: slide straight into a wall and into a corner, then at the map edge.
   - Should see: the slide stops at the wall, never goes through, never leaves the arena. Spamming Slide does not beat the 5 s wait.
   - [ ]
5. **A player is eliminated during an upgrade offer.**
   - Do: level up, leave the three cards open, let a rival (or the zone) finish you.
   - Should see: cards close, picking does nothing, you see the defeat banner and can spectate. No error in Output.
   - [ ]
6. **A player disconnects during the countdown.**
   - Do: 2 players press PLAY, close one client while the number counts down.
   - Should see: with too few players the match goes back to waiting ("Not enough players") and does not start alone and stick.
   - [ ]
7. **A final participant disconnects.**
   - Do: with two left, close the client of one of them.
   - Should see: the other is declared winner once (or "abandoned" with no winner if the survivor is the one who left). Results show, replay works.
   - [ ]
8. **The last two players eliminate each other.**
   - Do: arrange a trade within 0.1 s (two mortar blasts at the same spot work well).
   - Should see: a draw, both marked 1st, shown once. No second winner.
   - [ ]
9. **A late shot arrives after the match is over.**
   - Do: fire a mortar shell, then end the match before it lands (or fire as the last player dies).
   - Should see: the shell does nothing to results or to the next match. Nobody is hurt in the Results or Waiting phase.
   - [ ]
10. **Several matches in a row.**
   - Do: play 5 matches without closing the server (PLAY AGAIN each time).
   - Should see: no stuck countdown, crates and orbs come back, upgrades and XP start fresh, health and ammo reset, no leftover effects, no growing error list in Output.
   - [ ]

## 4. First-time intro and data messages (piece 20)

Intro (shown once, skippable, in the lobby before PLAY):
- [ ] A brand new player sees the intro. It names move, aim, fire, slide with the right words for their device (phone, keyboard, controller).
- [ ] Skip works at any time and the intro does not come back in that session.
- [ ] After finishing or skipping, rejoin the game: the intro does **not** show again (needs a working save; see below).
- [ ] The intro never shows during a countdown or match.
- [ ] Every intro control has a touch button on a phone.

Data did not load:
- [ ] When the save cannot load you see a clear message and can still press PLAY. Nothing is wiped.
- [ ] TRY AGAIN loads the save if the problem is gone, and the message disappears.
- [ ] While the save is loading too long (over `Config.Onboarding.slowLoadSeconds`) you see "Still loading your save...".
- [ ] If the save was opened on another server ("lost") the message says to rejoin and has no TRY AGAIN.
- [ ] Credits and progress earned in a no-save session are **not** presented as saved.

## 5. Saving test (needs a real place, not only Studio)

- [ ] Studio can only save if "Enable Studio Access to API Services" is on in Game Settings > Security. If it is off, saves fail with a 403 on purpose, which is a free way to see the "saving is off" message. Turn it on to test real saves. (A setting you change, not Claude.)
- [ ] Play, earn credits, leave, rejoin: the credits are still there.
- [ ] Join the same account on a second server at the same time: only one session saves, the other gets the "rejoin to save" message.
- [ ] Claim the same result twice: the credits are granted once.

## 6. Phase acceptance gates (from the brief, section 25)

- [ ] Phase 1: two players see the same outcomes. Hits respect walls. Ammo and cooldowns cannot be skipped. Slide stops at obstacles. Desktop and touch both work.
- [ ] Phase 2: several matches in a row finish. No duplicate winners. No stuck countdown. Disconnects do not break the match. A simultaneous last elimination is a draw.
- [ ] Phase 3: rewards cannot duplicate. Offers are valid. Upgrades show a visible change. Stats reset every match. Choices stay usable while fighting.
- [ ] Phase 4: combat is readable. Touch targets are big enough. Settings work. FPS numbers measured (section 7).
- [ ] Phase 5: leave and rejoin keeps data. A failed load does not destroy progress. Rewards grant once. Two sessions do not overwrite each other.
- [ ] Phase 6: a new player can start with no explanation. Players understand why they lost. Repeated sessions stay stable. No placeholder in an essential system. Known limits written down (section 8).

## 7. Devices (measure, do not guess)

| Device | Target | Measured | Notes |
| --- | --- | --- | --- |
| Desktop (your PC) | 60 FPS | | |
| Lower-end phone | stable 30 FPS | | |
| Controller | all controls reachable | | left stick, right stick, R2 fire, A slide, X reload, L1/R1 swap, D-pad 1-3 |

Also try: a full match with the most players and bots you plan to allow (`Config.Match.maxParticipants`), many shots at once, a few mortar blasts, the zone closing, and the match reset. Watch frame time and Output.

## 8. Known limits (as of Phases 1-3)

Plain list. None of these block a first play test; all are things to decide before Publish.

- Nothing has been run in Studio yet. Remotes, raycasts, visuals, camera feel, slide feel, roof fade and touch controls are only proven by the Lune tests of their rules, not by play.
- `selene` could not run in the cloud sessions (no Roblox API download). CI runs it.
- Hits use current positions with a 1.8 stud body circle. There is no lag compensation. High ping will feel off.
- Graybox arena (layout C "Arcade Row"). Layouts A and B exist but only one is live. One map only.
- Upgrade icons are short text labels, not art.
- Placeholder looks: character and gun are built from blocks. Skins for the looks carter did not pick (HUD A and C, zone B and C, bots Tag Bot and Hologram Bot, slide looks B and C) are not built.
- Bots use no pathfinding (a stuck bot sidesteps) and have no mortar logic.
- Zone floor is assumed to be at Y=0.
- The game name is a placeholder.
- A self-kill reports no killer; kill feeds and XP ignore it.
- Heal pickups are off (`Config.Features.healPickup`).
- Development helpers: `Config.Features.devQuickStart` and the bot auto-fill button ("Alone? Bots join in 10s", "Add bots now") are clearly labelled. Decide before Publish whether the button stays.
- Saving needs real place settings (section 5). Until a place has API access on, every session is a no-save session and says so.
- If a player's save loads late or fails, the intro can show once more in that session. It is skippable and writes nothing.
- Basic analytics are not built. Add only if you want them, and say what to count first.

## 9. When everything above is ticked

Tell the coordinator "ready". Say "publish" when you want it live, and press Publish yourself in Studio.

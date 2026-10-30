# 42 One lobby layout for every lobby piece (logic only, placeholder looks)
- Problem (playtest, 1914x604): INVITE sat on the SETTINGS/REWARDS row, the look buttons sat under INVITE, button words spilled out, the map vote overlapped the bots banner. Each piece placed itself.
- Fix: `Ui/LobbyLayout` has two new groups/slots: `top` (`banner`, `vote`), `invite` in the right column. `looks` is now used (3 stacked 48 point buttons).
- `LobbyMenu.dock(root, slot)` puts a piece's root Frame in its slot; `LobbyMenu.fitText(button, max)` keeps one line inside the button.
- Moved onto it: BotBannerSystem, MapVoteClientSystem, InviteButtonSystem, LookPickerSystem. SETTINGS, PLAY, REWARDS (TRACK) use `fitText`.
- Those four no longer have their own ScreenGui; they show only while the lobby frame shows (Waiting, Countdown). Side effect: INVITE is not shown while spectating, and the look buttons are not shown on the results screen.
- Tests (`tests/ui_layers.test.luau`): every slot on screen, nothing touches anything, touch slots 48 points, at 4:3, 16:9 ... 21:9, 1914x604 and 2.6; groups never overlap; vote fits 4 maps.
- Looks stay placeholders; Claude Design makes the real UI and keeps the slots.
- Not played in Studio. selene runs in CI.

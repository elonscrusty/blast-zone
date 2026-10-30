# 26 Invite friends
1. Client `src/client/Social/InviteButtonSystem.luau`: "+ INVITE" sticker, bottom middle (y 0.88), touch-sized, DisplayOrder 39 (under Settings). Opens `SocialService:PromptGameInvite` with launch data `inv:<userId>`; shows in lobby/countdown and while watching a match you are not in.
2. Server `src/server/Social/SocialSystem.luau`: on join, finds the host from launch data or `Player.FollowUserId` (host must be in this server). If the host is queued or in the match, the friend is queued too (`MatchSystem.queuePlayer`) and gets attribute `QueuedByFriend` (PLAY reads READY). Feed lines: "Sam joined you!" / "You joined Carter!". No new remote.
3. Rules are pure in `src/shared/FriendInvite.luau`. Game stays solo free-for-all.
4. `MatchController.setReady`: in a full Countdown, a person who readies takes a planned bot's seat. Full of people = friend watches, then plays the next match.
5. `MatchSystem` gained `queuePlayer(player)` and `isQueued(player)`. `ResultsClientSystem` listens to `QueuedByFriend`.
6. Tests: `tests/friend_invite.test.luau` and two new cases at the end of `match_controller.test.luau`.
7. Invites need the live game: in Studio the button says "NO INVITES HERE". Test with a real friend after publish.
8. Roblox only puts a friend in your server if it has room: set Game Settings > Places > Max Players to at least 8 (carter does this).
9. Not done: parties across servers (teleport together). Not needed while one server = one match.
10. Nothing run in Studio.

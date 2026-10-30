# V11 Squads: duo and trio (video 3 gap #11)
- Done: Solo / Duo / Trio. Players vote in the lobby (same window as the map vote); the server counts and picks. Nobody voted = Solo (`Config.Squads.defaultMode`).
- Seating (pure, tested, `src/shared/Squads/SquadBook.luau`): friends who joined each other stay together, loose people fill open seats, bots fill the rest. Fewer than 2 squads possible (2 people in Duo) = plays Solo. Trio with 4 people becomes duos.
- Server: `src/server/Squads/SquadSystem.luau` (vote, parties, damage guard, tells each human their squad). `Core/Squads` is the one book. `SocialSystem.Joined` tells it who came for whom.
- Teammates cannot hurt each other (`Config.Squads.friendlyFire = false`): damage door guard, bullets and shells fly through them, bots never target them and often walk to a teammate. Your own blast and the zone still hurt.
- Match end: a squad is out when its last member falls; last squad standing wins, everyone on it shares place 1 and the win reward. `TeamRank` ranks squads like one fighter. Final pressure counts squads. A fallen fighter watches a living teammate first.
- Results rows carry `teamIndex`; payload has `winnerTeam` and `squadSize`; `Eliminated` has `teamIndex` and `squadOut`.
- Client placeholders (look from Claude Design): vote buttons (`SquadVoteState`/`SquadVoteRequest`), squad list (`SquadState`), teammate health bars turn the friendly colour.
- Tested: `tests/squads.test.luau` (29): seating, friendly fire, squad rank, whole squad matches, reset, bots. Not tested until carter plays: how it feels, touch buttons, the real vote look.
- Left: results screen text for squads ("YOUR SQUAD WON"), minimap dots and rings for teammates, reviving a fallen teammate, party invite for squads, analytics for modes, team colours (`Config.Squads.colorCount` is ready).

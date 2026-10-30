# 27 Anti-cheat audit (stop cheaters)

1. Audited all 13 client-to-server remotes: all go through `Core/Net` (rate limit + `Guard` shape check); handlers re-check phase, owner, ammo, cooldowns. No RemoteFunctions. Damage, XP, upgrades and Credits are only ever granted by the server.
2. New `src/server/AntiCheat/MoveCheck.luau` (pure): distance budget per player (walk speed +30%, 1s lump, slide credit). Too-far moves are held 0.5s, then snapped back. Also catches flying (steep climb budget).
3. `MoveGuard.luau` runs it every Heartbeat on player bodies. Server moves must use `MoveGuard.place(player, cframe)` (MatchSystem does). Slides add credit via `SlideService.PlayerSlid`.
4. Shots (`Firing.fire`) are refused while a move is held; `PickupRequest` uses `MoveGuard.trustedPosition`.
5. `AntiCheatSystem`: a body dying outside the damage door during a fight (Reset, self-kill cheat, void) now knocks the player out via `Damage:apply` (cause "other"). Before, they stayed "alive" with no body and could not be hit. Client `ResetButtonSystem` hides Reset.
6. `Core/Net`: server-to-client remotes get a no-op server listener (no junk queue); per-player warn keys are cleared on leave.
7. Tests: `tests/anticheat.test.luau` (19 bad-client cases: junk args on every remote, floods, trigger spam, orb/upgrade abuse, teleport, speed 1.5x/2x/5x, fly, slide timing, NaN).
8. Tuning in `Config.AntiCheat`. If honest phone players rubber-band, raise `burstSeconds` or `speedSlack`.
9. Not covered: hovering off a ledge, aim-assist cheats (shots are still server-cast and rate-limited). Coins/saving PRs (#15, #17) were not on main: audit them when they land.
10. No Studio Play test by Claude; carter's playtest thread checks that walking and sliding never snap back.

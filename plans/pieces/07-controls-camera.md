# Piece 07: Controls and camera (phone first)

**Goal:** The player can move, aim and fight with two thumbs, and with keys on a PC.
**Read first:** build plan, `02-design.md` (UI design section).

## You own
- `src/client/Controllers/Controls.luau`, `src/client/Controllers/CameraRig.luau`
- `src/client/Ui/TouchStick.luau`, `src/client/Ui/ActionButton.luau` (reusable pieces; piece 08 may use them, it must not edit them)
- `src/shared/Config/Controls.luau`
- `src/shared/AimMath.luau` (pure): stick vector to world aim, deadzone, dead-zone curve, screen position to ground aim for the mouse
- tests: `tests/aim_math.test.luau`

## Build
1. **Camera.** Scriptable camera, high 3/4 top-down (about 60 degrees, 55 studs up), follows the character smoothly, slight lead toward the aim direction, a little FOV kick on explosions (`Explosion` near you) and a short shake when you are hit (`Hit` with your id). Zoom out a little during `Results`. Works at any screen size; keep the player at the center.
2. **Move.** Left virtual stick (bottom-left, safe-area aware, floating: appears where the thumb lands in the left half). Feeds `Humanoid:Move` relative to the camera. WASD on PC. Gamepad left stick too.
3. **Aim + shoot.** Right virtual stick: pushing it aims, and past a threshold it **fires** (sends `Intent{aim, fire=true}`), releasing stops. A thin aim line shows. On PC: mouse aims (screen ray to the floor), left button fires. Send `Intent` at most 20 times a second and only when something changed (plus a heartbeat every 0.25 s while firing).
4. **Buttons** (each at least 72 px, 16 px gaps, ring shows cooldown from the `HeavyReadyAt` / `RollReadyAt` Attributes): **Boom** `Action "heavy"`, **Roll** `Action "dodge"`, **Fix** `Action "heal"` with the kit count from `Kits`. PC keys: E, Space, Q. Gamepad: RB/A/X. Buttons hide when you are out of the match; a ghost sees a **Poke** button instead (tap the map spot: use the minimap click that piece 08 provides, or a simple "tap anywhere on the world" mode if you must; coordinate through the coordinator).
5. **Haptics** (short) on hit for phones where available. All motion respects the safe area and `UserInputService.TouchEnabled`.
6. Disable the default Roblox touch controls and jump button while a match runs; give them back in the lobby.

## Server checks
(The server is the judge, so the client is dumb.) Never send anything but the allowed payloads from `RemoteNames`. Never read positions from the server to aim for you.

## Tests (Lune)
`AimMath`: deadzone, normalized output, fire threshold, mouse-ray hit on a flat floor, no NaN for zero vectors.

## Done when
Checks pass, every control has a touch button, row 07 marked, handoff written.

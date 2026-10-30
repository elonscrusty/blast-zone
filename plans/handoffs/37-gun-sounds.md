# 37 Gun sounds
1. Built on the stack (#28), using #13's audio system. Files: `src/client/Audio/` and `tests/audio.test.luau`.
2. New cues: `fire_breaker`, `fire_hornet`, `fire_longline` (each with a `_other` far version that reuses the same id), `gun_drop`, `gun_swap`. Briefs are in `plans/AUDIO-IDS.md`.
3. Shot sound follows `weaponId` in ShotFx. Unknown guns fall back to the pistol sound.
4. `gun_swap` plays for you when the gun in slot 1 changes in AmmoState. The first AmmoState of a match is only a baseline, so no sound at match start.
5. `gun_drop` plays at the spot where the server puts a gun on the floor (new part in the WeaponDrops folder). Box hit and box break sounds already existed and are unchanged.
6. NO ids added. None were invented (Roblox sites are blocked here). The game stays silent for these cues until carter sends numbers: paste into `AudioIds.luau`.
7. Hornet fires 11 a second, so its cue has a 0.07 s gap and 4 voices; the limiter keeps it from flooding.
8. Tested: `lune run tests/run` (616 pass), stylua, rojo build. Not run: selene (no API dump here; CI runs it), real playback.
9. Left: per-gun reload sounds (reload still shares one cue); bots picking up guns make no sound.
10. Server untouched. No remotes changed.

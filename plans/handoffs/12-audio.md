# 12 Audio (sounds + music)
- Done: the whole sound system, listening only to messages the server already sends. Files: `src/client/Audio/`.
- Cues (25, in `AudioCatalog.luau`): pistol, mortar, blast, reload start/end, hit, kill, hurt, slide, box hit/break, orb pickup, level-up, upgrade pick, zone warning, sudden death, out (you / others), victory, defeat, and 3 music loops (lobby, match, last minutes).
- NO sound ids yet: none were invented and Roblox sites are blocked here. `AudioIds.luau` is empty, so the game is silent and nothing breaks. Steps for carter: `plans/AUDIO-IDS.md`.
- Volume: every sound is in the Music or Effects SoundGroup made by Settings, so both sliders work. Others' shots, slides, boxes and blasts get quieter with distance (ground distance from who you watch) and drop out far away.
- Caps: per-cue repeat gap and voices, 18 effects at once (+4 reserve for your own), far sounds refused first. 200-shot firefight test stays under the caps.
- Reset: a new match id or Resetting/Waiting stops all effects and forgets levels, reload and zone-warning memory. Music fades (1 s out, 1.5 s in) between lobby, match, last minutes; Finished is quiet.
- Tests: `tests/audio.test.luau` (23 checks: cue rules, ids, distance maths, limiter, every event, reset). Not tested: real playback, loudness balance, whether chosen ids load (needs Studio/Play).
- Not run: selene (no API dump here; CI runs it) and a Roblox type check. Own shot sound waits for the server's ShotFx (one round trip); a local early sound would need a hook in piece 03.
- Left: pick and add ids; music mood is picked (neon synth, already in the cue wording); maybe a countdown tick and UI click.

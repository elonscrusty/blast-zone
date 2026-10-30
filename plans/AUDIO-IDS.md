# Sound ids (piece 12)

Every cue below is wired to the game. None has a sound yet: no id was invented, so the game is silent
until ids are added. Nothing breaks without them.

## How to add one (about 2 minutes each)
1. Open the Creator Store audio page in a browser (create.roblox.com, Store, Audio).
2. Search the words in the table. Listen. Pick one that matches.
3. Open its page and copy the number at the end of the web address.
4. Send the cue name and the number to Claude, or paste a line into `src/client/Audio/AudioIds.luau`:
   `fire_pistol = 1234567890,`
5. If a sound is silent when you play, Roblox does not allow it in our game. Pick another.

Use only sounds you are allowed to use in a game. Your own uploads work too (Creator Hub, Audio).
One file can fill several cues: `fire_pistol_other` uses `fire_pistol`, `slide_other` uses `slide`.

## Rules the game already follows
- Music and effects follow the two volume sliders in Settings.
- Far away sounds are quieter, then gone. Each sound has a limit on repeats and the whole mix has a cap.
- Everything stops and resets between matches. Music fades between lobby, match and last minutes.

## Cues
| Cue | What to look for |
| --- | --- |
| `fire_pistol` | Your pistol shot: short sci-fi zap or laser pop, under 0.5 s |
| `fire_pistol_other` | Someone else's shot (uses the pistol sound) |
| `fire_mortar` | Mortar launch: low thump with a whistle, under 1 s |
| `explosion` | Mortar blast: punchy explosion boom, 1 to 2 s |
| `reload_start` | Magazine slide out, click |
| `reload_end` | Magazine in, slide clack |
| `hit_confirm` | You hit someone: short tick or ping, under 0.2 s |
| `kill_confirm` | You knocked someone out: rising ping or crunchy ding |
| `damage_taken` | You got hurt: dull thud or buzz, under 0.4 s |
| `slide` | Quick whoosh or skid, about 0.4 s |
| `slide_other` | Someone else's slide (uses the slide sound) |
| `container_hit` | Box takes a hit: plastic crack or tap |
| `container_break` | Box bursts: crack and sparkly burst, under 1 s |
| `pickup` | XP orb grab: bright blip or coin-like chime, under 0.3 s |
| `level_up` | Short happy rising jingle, about 1 s |
| `upgrade_pick` | Upgrade card chosen: confident power-up click |
| `zone_warning` | Safe zone will shrink: low alarm pulse, 2 to 3 s |
| `sudden_death` | Dramatic hit and siren sweep |
| `eliminated_self` | You are out: falling power-down |
| `eliminated_other` | Someone else is out: soft low thump |
| `victory` | You win: bright fanfare, 3 to 5 s |
| `defeat` | You lose: sad but short descending sting, 2 to 4 s |
| `music_lobby` | Calm night-city neon synth, loops cleanly |
| `music_match` | Driving neon synth beat, loops cleanly |
| `music_final` | Tense, faster than the match music, loops cleanly |

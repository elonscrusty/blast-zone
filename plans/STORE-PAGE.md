# Store page (piece 30)

Everything carter needs for the Roblox game page. carter uploads it all himself.
The game name is still the placeholder `Circuit District` (`Config.Game.Name`).

## Pictures (in `art/store/`)

| Idea | Icon (512x512) | Thumbnail (1920x1080) | What it shows |
| --- | --- | --- | --- |
| A Hero Shot ⭐ | `icon-A.png` | `thumb-A.png` | Your fighter aiming the A++ pistol, Neon Night street, Crash Dummy bot behind |
| B Gun Glow | `icon-B.png` | `thumb-B.png` | The A++ pistol firing up close, brass flying, a bot down the street |
| C Zone Closing | `icon-C.png` | `thumb-C.png` | The game camera: you vs 3 Crash Dummies, red zone wall, crates, XP orbs |

- Pick ONE icon. Use all three thumbnails: the picked one first, the others after it.
- Thumbnails say "Neon Lockdown". If you keep another name, open `art/store/preview.html`,
  tap the name, and ask a thread to re-render the PNGs.
- All art is built from the game's own looks (gun parts copied from `src/client/Combat/GunModels.luau`,
  Crash Dummy colors from `src/server/Bots/BotTuning.luau`, palette from `Config.Palette`).

## Name ideas

1. ⭐ **Neon Lockdown**: neon city + the zone locks you in.
2. **Volt District**: matches Volts (the coin) and the city.
3. **Last Spark**: last one standing, short and easy to say.
4. Circuit District: the current placeholder.

Nobody has checked these names. Search each one on Roblox before you pick it.
To change it in the game: edit `Config.Game.Name` in `src/shared/Config.luau` (one line), plus the name in Roblox.

## Description (paste into Roblox, under 1000 characters)

```
Drop into a neon city. Grab loot. Be the last one standing!

Every match is a free-for-all. Run, slide and shoot your way through the streets while the red zone wall closes in.

- Smash purple crates for better loot
- Pick up XP orbs and choose a power-up card when you level up
- Slide under fire to dodge shots
- Not enough players? Crash Dummy bots fill every match, so you never wait
- Earn Volts and unlock new stuff

Made for phones first. Works on PC and controller too.

Tip: stay inside the zone!
```

Keep it true to the game. Every line is in the code on main today, except "Earn Volts":
that needs the coins PR (#17) merged first. Remove that line if it is not in yet.

## Genre and search words

- Genre: **Shooter**. If Roblox shows a sub-genre list, pick the closest one (Battle Royale or Arena).
- Roblox has no free tags. Search words already sit in the description: free-for-all, zone, loot, slide, bots, neon city.

## Upload steps (carter does these; no settings were changed by Claude)

1. Open create.roblox.com and sign in. Click **Creations**, then the game.
2. Open the game's settings page (Configure / Basic Settings). Paste the name and the description.
3. Find **Icon**. Upload the picked `icon-?.png`. Save.
4. Find **Thumbnails**. Upload `thumb-A.png`, `thumb-B.png`, `thumb-C.png`. Drag the picked one to the front. Save.
5. Set the genre to Shooter.
6. Fill in the **Maturity & Compliance** questions honestly: the game has guns and shooting, no blood.
7. New pictures are checked by Roblox first. They can show as "pending" for a little while. That is normal.

If a menu has moved, look for the same words (Icon, Thumbnails, Description) on the game's page in Creator Hub.
Do NOT press Publish for the game itself until carter says "publish".

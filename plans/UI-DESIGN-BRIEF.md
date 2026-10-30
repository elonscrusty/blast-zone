# Brief for Claude Design: the whole UI of Circuit District

> carter: copy everything below the line and paste it into Claude Design.

---

Please design the **complete UI system** for my Roblox game **Circuit District** (name may change).

## The game

- An original **3D** solo free-for-all arena shooter. Everyone fights alone in a neon city at night.
  The safe zone shrinks, and the last one standing wins.
- The camera is up high and looks down at about 55 degrees. The player stays in the middle of the screen.
- Most players are on a **phone held sideways**. PC (mouse and keys) and controller come next.
- Players are kids and teens, so use short, loud words and big buttons that are easy to hit.

## The style picks so far (keep them)

- **HUD look B, "Street Sticker"**: cream sticker panels with thick navy outlines, a hard drop shadow
  (no blur), chunky rounded type, gold and coral pops. The owner said "but better", so push it further.
- **City "Neon Night"**: dark navy streets and cyan neon, going from day to night during each match.
  The UI must read well on top of both the bright day and the dark night.
- **Results "Big Banner"**: a giant title, three small numbers, and one huge PLAY AGAIN button.
- **Coins are called "Scrap"** (grey-silver metal bits). The unlock track is called **Rewards** on screen.
- Earlier picks to keep: upgrade cards in a **bottom row**, intro "Four Tiles", save message as a
  "Top Strip", the zone is a "Neon Wall".

Current colours (you may improve them, but keep the spirit): cream `#FFF4D6`, navy `#14243A`,
gold `#FFC44D`, coral `#F15B64`, cyan `#36D9E8`, green `#7BD88F`, pavement `#C8A675`.

## Sizes and rules (must follow)

- Design on a **780 x 360 landscape phone** (in points). The UI scales with screen height; each piece hugs
  its nearest edge. Also show one **PC frame (1920 x 1080)** and the **controller focus ring**.
- Every tap target is **at least 48 points**. Text is never smaller than **9 points**.
- In a fight, keep these clear: the **player** (screen centre, 120 x 120) and the **cards band**
  (bottom centre, 26-74% across, 76-96% down). Thumbs own both bottom corners.
- Show every screen **on top of a 3D game view** of the neon city (never on a flat blank page).
  It is a 3D game.
- Only Roblox built-in fonts can be used. Pick from: FredokaOne, LuckiestGuy, Bangers, GothamBlack, GothamBold,
  Gotham, BuilderSans, BuilderSansBold, BuilderSansExtraBold, Montserrat, Michroma, Oswald, Sarpanch,
  TitilliumWeb, Ubuntu, Arcade, PermanentMarker.
- No pictures that need uploading for now: shapes, outlines, gradients and emoji-free icons drawn from
  simple shapes are best (they become Roblox frames).
- Never show real-money prices or Robux numbers. Scrap prices are placeholders like "120 Scrap".

## Screens to design (every one, with its states)

1. **Combat HUD**: health + level + XP bar (top-left), players-left chip + zone timer chip (top centre),
   one warning line (OUTSIDE THE ZONE / LOW HEALTH / RELOAD! / ZONE CLOSING IN 5), round minimap
   (top-right), weapon panel with ammo, reload fill and slot pips (right), hit edges and hit marker,
   small settings gear. Keep it small: the owner said the first HUD was "way too cluttered".
2. **Phone controls**: move stick (left), aim-and-fire stick (right), Slide button with a cooldown ring,
   Reload button, floating-stick look (faint ring at rest), upgrade pick chips 1-3 by the right thumb.
3. **Upgrade cards** (bottom row of 3): icon, name, one short line, the real numbers ("Reload 1.2s -> 0.96s"),
   stacks "2/5", weapon or move colour, "+2 more" waiting badge, picked state.
4. **Bots banner**: "Alone? Bots join in 10" with an "Add bots now" button.
5. **Lobby**: status line, big PLAY, SETTINGS, REWARDS, the look picker (Runner, Courier, Spark), INVITE,
   and the 3D station prompts (PLAY gate, Settings kiosk, Rewards board, Loadout garage).
6. **Match flow**: countdown 3-2-1 + FIGHT!, banners (final pressure, match over), kill feed (3 lines max),
   ELIMINATED banner with place and who did it, spectate bar with < name >.
7. **Results (Big Banner)**: win, lose, draw and abandoned versions; three numbers (place, knock-outs, time alive);
   PLAY AGAIN and READY! states; the **Scrap strip** under it (+40 Scrap, bar to the next reward, UNLOCK / REWARDS).
8. **Rewards panel**: Scrap total, free looks, six tiers; each item LOCKED / UNLOCK / WEAR / WORN; a "not enough Scrap" note.
9. **Settings panel**: sliders (Music, Effects, Camera shake, HUD size, Aim speed, Button size) and switches
   (Fewer flashes, Left-handed, Floating sticks), DONE.
10. **First-time intro "Four Tiles"**: move, aim, fire, slide; GOT IT and Skip; phone, PC and controller wording.
11. **Save message "Top Strip"**: gold "Still loading your save..." and coral "Saving is off for now." with TRY AGAIN.
12. **Toast**: a small "Saved" style message.
13. **Over-head health bars** for enemies, and the spawn-shield look.

For each screen show: phone, one PC frame, the controller focus on its first button, and every state listed.

## What to hand back (important)

When the designs are done, please also give me **one JSON block** in exactly this shape, so my game can use your
look straight away. Every colour is "#RRGGBB". Text sizes are points on the 780 x 360 phone.

```json
{
  "id": "street_sticker_plus",
  "name": "Street Sticker+",
  "colors": {
    "panel": "", "panelAlt": "", "ink": "", "inkOnAccent": "", "inkOnDark": "",
    "outline": "", "shadow": "", "accent": "", "good": "", "danger": "", "info": "",
    "dim": "", "backdrop": "", "coin": "",
    "winTop": "", "winBottom": "", "loseTop": "", "loseBottom": "", "drawTop": "", "drawBottom": ""
  },
  "fonts": { "display": "", "body": "" },
  "text": { "display": 44, "title": 24, "body": 14, "caption": 10 },
  "shape": { "strokeScale": 0.0085, "cornerScale": 0.32, "shadowOffset": 0.011, "backdropAlpha": 0.45 },
  "motion": { "pop": 0.18, "slide": 0.25, "fade": 0.2 }
}
```

What the keys mean: `panel` panel fill, `panelAlt` second panel shade, `ink` text on panels, `inkOnAccent` text on
gold or coral buttons, `inkOnDark` text on dark backdrops, `outline` thick outline, `shadow` hard shadow,
`accent` main button gold, `good` green, `danger` coral, `info` cyan, `dim` empty bars and disabled, `backdrop` the dim
behind a full panel, `coin` the Scrap colour, `win/lose/draw Top/Bottom` the results banner gradients.
`strokeScale` outline thickness as a share of screen height, `cornerScale` corner radius as a share of the
piece's height, `shadowOffset` shadow depth as a share of screen height, `backdropAlpha` 0 = solid, 1 = clear.
Text must be easy to read: ink on panel at least 4.5:1 contrast, text on gold or coral at least 3:1.

Please also give me a **picture of each screen** (phone size) so the builder can match the layout.

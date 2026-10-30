# 30 Store page

- What: 3 icon + 3 thumbnail ideas (A Hero Shot ⭐, B Gun Glow, C Zone Closing), 3 name ideas, store description, upload steps.
- Files: `art/store/icon-*.png` (512x512), `art/store/thumb-*.png` (1920x1080), `art/store/preview.html`, `plans/STORE-PAGE.md`.
- Art is real 3D (three.js r128) built from the game's looks: A++ gun parts list, Crash Dummy colors, Config.Palette, Neon Night city.
- Re-render: open preview.html locally with `#shot=A&mode=thumb&w=1920&h=1080&title=Neon%20Lockdown`, screenshot `#shot` (Playwright, swiftshader).
- No game code changed. Name in the game is still `Config.Game.Name` = "Circuit District".
- Live preview for carter: https://claude.ai/artifact/XARRj36mR1ef9tjF2ZjKHH
- Names are not checked against Roblox. carter must search them first.
- carter uploads everything himself; no account settings were touched.
- Left: carter picks A/B/C and a name; if the name changes, re-render thumbnails and edit Config.Game.Name.

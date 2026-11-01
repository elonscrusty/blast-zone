# B: ash layer look (after carter: "the whole map should be a complete layer you carve through")
1. The ash is now ONE flat blanket (1.4 studs at full, 0.35 at level 1, a little darker when thinner), no mounds. Sweeping carves a trench down to the zone ground; the side faces are the cut wall.
2. Trench edges use marching squares on the cell centres (`AshShape.outerLevel`): straight or 45-degree edges, filleted corners, diagonal sweeps stay one stripe. Level steps (part-scraped ash) are chamfered the same way.
3. Parts: a full cell is 1 block; edge cells add a 45-degree diamond and flat WedgeParts. Edge neighbours differ by 0.012 studs (checkerboard) and overlap by 0.05, so no gaps and no z-fighting.
4. Colour: zone ash tint blended over 24 studs at zone borders + soft 44-stud noise (no per-cell speckle). Gold = Neon patch 0.05 above the layer. Embers (zones 4-5) capped at 20.
5. Culling is per chunk (4x4 cells, `AshChunks`): detail within 112 studs (+12 margin), flat far tiles out to 300 (+24), so the blanket reaches the haze. Caps: 1080 detail + 300 far + 20 embers = 1400 Parts.
6. Swept cells sink over 0.14 s, then only their corner fillets stay; part-scraped cells sink to the new depth.
7. Vfx: other players' sweep puff and the new trench dust use the layer colour (`AshRenderer.layerHex`); lava discs sit on the layer top.
8. Not mine, worth a look: Controls' own-swing puff still mixes 30% tool colour and starts at y 0.6 (inside the layer). Boundary ropes are under the full layer.
9. Files: src/shared/Client/{AshShape,AshChunks}.luau, src/client/Ash/AshRenderer.luau, src/client/Vfx/Vfx.luau, tests/ash_shape.test.luau.
10. Needs a phone/Studio: WedgePart corners land on the right side (model in `AshShape.wedgeFrame`), FPS with ~1200 Parts, how the near/far seam reads at max zoom.

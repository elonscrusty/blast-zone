# C3 handoff: shop panels (Upgrades, Tools, Helpers, Gates)

1. Panels (each registers itself with PanelHost on require): `src/client/Panels/{Upgrades,Tools,Helpers,Gates}.luau`, ids `upgrades` `tools` `helpers` `gates`, menu orders 10/20/30/40, icons 🛠 🧹 🤖 🚪 (the HUD red dots key off these ids).
2. Pure view-models (all strings, states and choices live here, covered by Lune tests): `src/shared/Ui/{UpgradesModel,ToolsModel,HelpersModel,GatesModel,ShopModelUtil}.luau`, tests `tests/{upgrades,tools,helpers,gates}_model.test.luau`. `ShopModelUtil.profile(view)` turns the half-filled client store into a safe Profile before calling `Rules/Pricing`, so the panels show exactly the prices and reasons the server uses.
3. Client helpers: `src/client/Panels/Shared/{PanelKit,StoreBinding}.luau`. StoreBinding coalesces store changes into one repaint per frame and retries until the store exists. PanelKit has the header, scroll/grid, pop/flash, glow and wobble. Main loads them too (they register nothing).
4. The client never spends: a tap only sends `Buy` / `EquipTool`; cards pop only when the SERVER's State shows a level/tool/bot/gate change (and only after `Store.ready`). No hold-to-buy.
5. `Buy` always needs an id string: bots and bot levels send `""`, zones send `tostring(zoneId)` (the remote schema rejects missing or numeric args).
6. Layout: decided from the panel body size in virtual px (screen scale and pop-in scale divided out). Landscape (>= 480 wide): 2-column upgrade cards, 8 tool tiles in one row, ring picture left of the zone list. Portrait: one column, 4x2 tool tiles, ring picture on top. Short bodies (< 300 high) use tighter cards. Every panel scrolls, so nothing is ever cut off.
7. "Best next buy" star = lowest current price among not-maxed upgrades (cheapest affordable, else closest). Tools: LOCKED = not the next tier and not affordable (the rules still allow buying a far tool if you can pay). NEXT = lowest unowned tier above your best tool.
8. Sound hooks used: `click`, `error` (via Components), `upgrade`, `unlock` (silent without ids).
9. Never opened in Studio or on a device; checked by Lune model tests, stylua, rojo build only. Emoji art (🤖 🧹 🌋 ⭐ 🔒) depends on Roblox's emoji font.
10. Not done: no ViewportFrame tool models (emoji on a coloured disc instead), no Robux anything, no teleport from Gates.

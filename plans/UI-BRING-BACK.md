# Bringing Claude Design's work back into the game

## carter's steps (tiny)

1. In Claude Design, paste `plans/UI-DESIGN-BRIEF.md` (everything under the line).
2. When you like it, say: **"give me the JSON block and a picture of each screen"**.
3. Copy the JSON block. Paste it here in the chat.
4. Send the pictures too (tap the paperclip). A link to the Claude Design page also works.
5. Claude checks it, builds it, and sends a PR. You say **"merge"** when you are happy.

## Builder steps (for the Claude thread that gets it)

1. Save the JSON as `design/<id>.json` (pictures: `design/<id>/<screen>.png`).
2. `lune run tools/import-design design/<id>.json`. It checks every colour, font, size and the text contrast, and
   writes `src/client/Ui/Skins/<Name>.luau`. If it lists problems, fix the JSON (or ask carter one short question).
3. Add the skin to `Tokens.skins` in `src/client/Ui/Tokens.luau`. If carter picked it, set `Tokens.defaultSkin`.
   Every screen built with `Ui/Components` (and everything using `Hud/UiKit` / `Hud/Theme`) changes at once.
4. Layout changes from the pictures: move one screen at a time onto `Ui/Components`, keep its Model/System logic
   untouched, and delete its line from `LEGACY` in `tests/ui_tokens.test.luau`. Positions go in a Layout file
   (`Hud/Layout.luau`, `Ui/LobbyLayout.luau`), never inline numbers in the view.
5. Run the four checks (`stylua src tests tools`, `selene src`, `lune run tests/run`, `rojo build`), open the PR,
   and show carter a 3D preview of the new look before asking for "merge". Never Play-test in Studio.

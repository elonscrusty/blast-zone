# Save test for carter (do this only after you publish)

Saving is NOT proven yet. It only counts once this works on the real game.

## Before
1. Publish the game yourself (only you press Publish).
2. In Studio only (to test there): Home > Game Settings > Security > turn on **Enable Studio Access to API Services**. Not needed in the live game. Claude never changes this.

## Test (phone is fine)
1. Join. Play one match to the end. Tap to claim. Write down your Credits.
2. Close the game. Wait 10 seconds.
3. Join again. Credits must be the same.
4. Leave in the middle of a match. Join again. Credits must be the same (no extra, no loss).
5. Leave and join again fast (under 5 seconds). It may say loading a bit. Then Credits must be the same.
6. Play two matches in a row. Each one pays once.

## If it fails
Tell Claude which step and the number you saw. On PC: Developer Console (F9) > Server log, lines that start with `[Profile]` say why.

# Task 43: A Pets screen made for a beginner

## Goal
Playtest 3: with one pet the screen is 75% empty, the tile thumbnail is 55
px in a 180 px tile, the panel covers half of the EGGS and PETS menu
buttons, the detail shows HP, Attack, Speed and two move paragraphs that
mean nothing yet, stat boxes do not fit their text, and EQUIP is an outlined
text button inside a gold outline.

## Build
1. While the tutorial is active or the player owns fewer than 4 pets: show
   name, rarity, type, Click Power and a filled primary EQUIP button; battle
   stats and moves behind a "Battle stats" toggle.
2. Stat rows sized from text size plus padding, so every label fits.
3. With fewer than 4 pets: bigger tiles (thumbnail at least 100 px) and a
   narrower centered panel.
4. The panel never covers the menu: keep its left edge right of the menu
   rect, or hide the menu while any screen is open. PetsLayout spec at
   1280 x 720 and 1348 x 672.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

# Task 41: Signs that read cleanly from spawn

## Goal
Playtest 3: from spawn the two egg-stand billboards sit right in front of
the gym sign and chop it into fragments; their text is tiny and breaks
"Egg" into "E gg"; the world sign's post crosses its lettering; a lone fence
block sits at the right edge of the arrival view.

## Build
1. Egg-stand labels just above the egg (about 6 to 7 studs) and about 8 x 3
   studs, or stands moved to the sides of the path, so from the arrival point
   their screen rectangles never overlap the gym sign.
2. Larger text and a font that does not split words.
3. Sign post at the board's edge or behind it; no fence piece ending as a
   lone block in the arrival camera frame.
4. A Scenery or Layout spec that projects the stand labels and the gym sign
   from the arrival point and asserts no overlap.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

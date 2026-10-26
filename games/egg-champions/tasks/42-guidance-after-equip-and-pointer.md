# Task 42: Guidance never stops, and the pointer is unmistakable

## Goal
Playtest 3: after equipping, the tutorial strip disappears, the panel jumps
up 48 px and the player sits in the Pets screen with no instruction; after
closing, the card no longer says how to earn coins; the gold pointer is a
thin 3 px outline that is almost invisible; there are two calls to action
for the same thing (menu pointer and the OPEN button on the card).

## Build
1. After the equip step, while the gym step is held back: the Pets screen
   strip says "Pet equipped. Close this and click to earn more coins". Keep
   the strip slot reserved so nothing jumps.
2. The goal card keeps a short "Click anywhere to earn coins" line whenever
   the next goal is coin gated and coins are below its price.
3. Pointer: 5 to 6 px outline, opaque at the low end of the pulse, plus a
   bouncing arrow next to the target.
4. One call to action: keep the pointer, remove the OPEN EGGS and OPEN PETS
   buttons from the goal card during the tutorial.
5. Tutorial and NextGoal specs for the step 3 to 4 transition while the
   team is not full.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

# Task 31: The first minutes have a next step, and the gym is easy to find

## Goal
Playtest: right after the first equip the only goal is a 50,000-coin gym fee
(about 6,000 clicks) with nothing in between, and the gym is behind the spawn
camera with a barely visible highlight. Do not change any economy number in
config; add intermediate goals instead.

## Build
1. Goals between the tutorial and the first gym, from config values only:
   "Hatch 2 more pets", "Fill your team of 3", "Save for the Forest Egg"
   (its price), then the gym. Shown in the goal card with progress.
2. Move the first world's gym in front of spawn, beyond the egg stands, so
   the default camera sees it (layout data in Layout.luau; keep the layout
   specs, add one that the gym is in front of spawn and clear of stands,
   portal and island edge).
3. Gym step guidance: a Beam or ground arrow from the character to the gym,
   and a screen-edge arrow when it is off camera. Stronger Highlight
   (FillTransparency about 0.6, pulsing).
4. Pure specs for the goal sequence.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

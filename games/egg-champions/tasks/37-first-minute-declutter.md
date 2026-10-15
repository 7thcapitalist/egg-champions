# Task 37: Less on screen in the first minute

## Goal
Playtest: four menu buttons, two gold buttons and pass text show on minute
one; the Pets screen shows four filter buttons and two extra tabs to a player
with one pet; the EQUIP outline overlaps the pet picture and is clipped;
stats show decimals.

## Build
1. Menu unlocks: REBIRTH appears once the player can afford a rebirth or has
   beaten the first gym; SHOP once the tutorial is done. Rules in HudLayout
   with specs.
2. Egg shop during the tutorial: HATCH X3 neutral, no pass footer line.
3. Pets screen with fewer than 4 pets: no filter row, no INDEX and FRUIT
   EDITION tabs.
4. EQUIP outline drawn inside the button (stroke Border mode) with padding;
   HP and Attack shown as whole numbers.
5. On minute one exactly one gold element is on screen: a spec over the HUD
   state for a new profile.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

# Task 40: The egg shop shows its eggs, and less clutter

## Goal
Playtest 3: every egg card's ViewportFrame holds an empty Model (no parts),
so the shop shows no eggs; HATCH X3 shows on every card, even locked ones;
the card swaps its name for a duplicate result row during the reveal; the
last card is cut off; the EGGS title does not fit.

## Build
1. Build the card's egg view from the same source the world egg stands use
   (the egg templates in ReplicatedStorage.PetModels); wait for the template
   if it is not loaded yet; fall back to a coloured egg shape, never nothing;
   frame the camera on the model's bounding box.
2. Hide HATCH X3 unless the player owns Triple Hatch and the tutorial is
   done; never on locked cards.
3. No duplicate result row on the card while the reveal shows.
4. Pad the list so the last card is fully visible; make the title fit.
5. Specs on the view logic (which buttons show, fallback path).

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

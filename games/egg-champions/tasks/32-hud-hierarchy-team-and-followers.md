# Task 32: Clear HUD priorities, team bar, and pets that follow you

## Goal
Playtest: the gold SHOP button is the loudest thing on screen during the
tutorial, the goal line is 11 px, "34 / 50" has no label, the team bar shows
"Empty" for an owned but unequipped pet and covers the character, "+8 per
click" and "Puddlet +3 CLICK" look contradictory, and equipping changes
nothing in the world.

## Build
1. Goal line at least 18 px, no TextScaled shrink, two lines allowed; the
   progress box becomes a labelled bar ("Coins for your first egg 34 / 50").
2. SHOP loses its gold accent until the tutorial is done; during onboarding
   the tutorial pointer is the only gold element.
3. Team bar: hidden until at least one pet is equipped; slot text "Puddlet
   Click +3"; top bar shows the total only ("+8 per click"); in compact sizes
   the bar moves bottom-left and is short enough not to cover the character.
4. Equipped pets follow the character in the world: client-side followers
   using ReplicatedStorage.PetModels, hovering in a small arc behind the
   player with a gentle bob, for every player in view. Shiny and golden
   variants use the variant look. No server cost per frame.
5. Keep and extend the HudLayout specs (no overlaps at 808 x 432, 1280 x
   720, 1920 x 1080).

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

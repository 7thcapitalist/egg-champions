# Task 28: First-time tutorial

## Goal
A new player must know what to do in the first minute. Today there is no
guidance at all.

## Build
1. Steps, in order, each with one short line in the next-goal card and a
   pointer (an arrow or a pulsing outline) at the thing to use:
   1. "Click anywhere to earn coins" until the player can afford the first egg.
   2. "Open EGGS and hatch your first pet" (points at EGGS, then at the
      Meadow Egg HATCH button).
   3. "Equip your new pet to your team" (points at PETS, then EQUIP).
   4. "Earn more and challenge the Grass Gym" (points at the gym).
   Then the tutorial ends and the card shows normal goals.
2. Store the step in the profile (add a migration). A returning player
   resumes the step; a player who already owns a pet skips steps 1 to 3.
3. A small SKIP on the card ends it.
4. Step logic is a pure module with tests: advancing on the right events
   only, resuming, skipping, migration of old profiles.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

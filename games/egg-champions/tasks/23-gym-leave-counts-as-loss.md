# Task 23: Leaving mid-battle counts as a loss

## Goal
A player who is losing a gym battle can leave, rejoin, and start again at
once, which skips the retry wait. Leaving with a running battle must count
as giving up, so the wait applies.

## Build
1. In GymService, when a player leaves (PlayerRemoving) with a running
   battle session, finish it as a loss (gave_up) through the same rule path
   as a normal loss, so `gymRetryAt` is written before the profile saves.
   Make sure the profile save on leave runs after this, not before.
2. Return the seconds left with the "retry_wait" refusal so the client can
   show a countdown after a rejoin, and show it in the gym UI.
3. Tests in the rules layer: a session that ends by leaving sets the same
   deadline as a loss; the refusal carries a correct seconds-left value.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Start a gym battle, leave mid-battle, rejoin, and confirm the wait applies with a countdown.

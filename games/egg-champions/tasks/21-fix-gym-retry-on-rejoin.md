# Task 21: Gym retry wait survives a rejoin

## Goal
A player who loses a gym battle must wait `gym_retry_seconds` even if they
leave and rejoin. Today the wait is cleared when the player leaves.

## Build
1. Store the retry deadline in the player's profile (a server timestamp),
   not only in server memory. Add a profile migration if the shape changes.
2. GymService reads the stored deadline when the player starts a battle.
3. Tests in the rules layer: a loss sets the deadline from config, a start
   before the deadline is refused, a start after it is allowed. The rule
   takes the current time as an argument.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Lose a gym, rejoin, and confirm the wait still applies.

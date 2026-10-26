# Task 39: Follower pets beside you, not in front of the camera

## Goal
Playtest 3: the follower pet sits 5 studs straight behind the character, on
the camera line, as tall as the character, so it fills the middle of the
screen, hides the avatar and blocks the path.

## Build
1. Place each follower about 3 to 4 studs to the side (alternating left and
   right per slot) and 1 to 2 studs behind the root part.
2. Scale follower models so their largest dimension is about 2.5 studs
   (half a standard character), numbers in the visual budget module.
3. Specs: every follower offset has |x| >= 2.5; scaled height at most half
   a standard character.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Avatar fully visible from the default camera with 1 and 3 pets equipped.

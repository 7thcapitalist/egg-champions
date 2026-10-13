# Task 20: Fix test runner gaps

## Goal
Close two holes the reviewer found in the test harness from task 02, so a
broken rule can never pass silently.

## Build
1. `Runner.expect(x):toBeCloseTo(expected, epsilon)` must fail when either
   value is NaN or infinite.
2. `factory/tools/run_tests.py` must fail, naming the file, when a
   `*.spec.luau` file exists under `src/shared` but is not listed in
   `src/shared/testing/specs.luau`.
3. Add `math.random` and `os.time` to the trapped list for rule modules, with
   a clear message: rules take an injected rng or time instead.
4. Add tests for all three.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] A spec asserting `toBeCloseTo` on `0/0` fails, then is removed.
- [x] An unregistered spec file makes the run exit 1 and name it, then is removed.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Out of scope
New game rules.

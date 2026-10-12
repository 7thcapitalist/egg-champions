# Task 02: Test harness

## Goal
A way to run Luau unit tests with no person in the loop, so every later task
can prove its own rules. One command, exit 0 or 1.

## Build
1. `src/shared/rules/` is where every game rule module will live. Modules in
   this folder must require no Roblox service and touch no `game` global, so
   they run outside the engine. This is the rule that makes headless testing
   possible; later tasks depend on it.
2. `src/shared/testing/Runner.luau`: a tiny test runner.
   - `Runner.describe(name, fn)` and `Runner.it(name, fn)` collect tests.
   - `Runner.expect(value)` with `toEqual`, `toBeCloseTo(expected, epsilon)`,
     `toThrow`, `toBeTrue`, `toBeFalse`. Deep compare tables in `toEqual`.
   - `Runner.run(specs)` returns `{passed, failed, failures}` and never
     errors out of a failing test: catch with `pcall` so one failure does not
     hide the rest.
   - No Roblox services here either.
3. `src/shared/testing/specs.luau`: the list of spec modules to run. It
   starts empty. Every later task adds its own spec module to this list.
4. `factory/tools/run_tests.py` plus a `factory/tools/run_tests` shim so the
   entry point works as named:
   - Takes `<game-dir>` as its argument, like every other factory tool.
   - Runs the suite with the Luau interpreter named in `rokit.toml`, prints
     one line per failure and a final count, and exits 0 or 1.
   - Add `luau` to `rokit.toml` so the interpreter is pinned like the rest of
     the toolchain, and run the suite with it. Do not require Studio.
   - If a rule module accidentally requires a Roblox service, the run fails
     with a message naming the module. That failure is the point.
5. `src/shared/rules/Example.luau` and a matching spec, both tiny, only so
   the harness has something real to run and later tasks have a pattern to
   copy. Delete the example in the first task that adds a real rule module.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0 and
      prints the test count.
- [x] A deliberately broken expectation makes it exit 1 and name the failing
      test. Revert the break.
- [x] A rule module that requires a Roblox service makes it exit 1 and name
      the module. Revert.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      still succeeds.

## Out of scope
Any game rule. This task builds only the harness and the folder rule. Tests
for real rules arrive with the tasks that write those rules.

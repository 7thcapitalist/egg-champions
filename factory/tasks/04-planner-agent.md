# Factory task 04: Planner agent (agent 3)

## Goal
An agent that reads a game's spec and config and writes the complete, ordered
list of build tasks, so no person writes task briefs.

## Build
1. `.claude/agents/planner.md`. The planner:
   - Reads `spec.md`, `config/`, `tuning/`, the existing `src/`, and the
     `design/` folder when it exists (`design/ui/README.md` and the mockups
     are the approved look and screen layout; UI tasks must follow them).
   - Writes one brief per task to `games/<game>/tasks/NN-short-name.md` in the
     same format as `01-project-skeleton.md`: Goal, Build, Done when, Out of scope.
   - Writes `games/<game>/tasks/index.json`: for each task its `id`, `title`,
     `file`, `depends_on`, and `status` (done, pending, blocked).
   - Covers every feature in the spec. At the end it prints a coverage table:
     each spec section and the tasks that implement it. A spec feature with no
     task is an error.
2. Rules the planner must follow when splitting work:
   - One system per task, small enough for one coder run.
   - The first new task is the test harness: a way to run Luau unit tests
     without a person, and a `factory/tools/run_tests` entry point that exits
     0 or 1. Prefer plain Luau modules under `src/shared` that hold all game
     rules (coins, hatching odds, battle resolution, rebirth) with no Roblox
     services, so they can be tested headless. If tests need the engine, run
     them in the TEST place through Open Cloud Luau Execution using the key in
     `.env`. Never touch the production place.
   - Every later task adds tests for its own rules, and its Done-when list
     contains only checks a machine can run (commands that exit 0 or 1).
     Anything that needs eyes goes in a separate "Needs human or playtester"
     list in the brief.
   - Server authority: clients send requests, the server decides.
   - All numbers come from config. No game numbers in `src/`.
   - Pets are colored placeholder blocks until the asset stage delivers models.
   - Out of scope for the build stage: 3D pet models, final world art,
     publishing to production.
3. Run the planner on `games/egg-champions` and commit the task list.
4. Add the `planned` gate to `gate.py`: `index.json` exists, every file it
   names exists, dependencies form no cycle, and task 01 is marked done.

## Done when
- [x] `games/egg-champions/tasks/index.json` lists the full build, with the
      test harness as the first pending task. 19 tasks, 01 done, 02 the test
      harness and the first pending one.
- [x] The coverage table shows every spec section mapped to at least one task:
      clicking and coins, saving, eggs and hatching with variants, team of 3,
      pet index, rebirth, gym battles with all six specials, worlds and
      unlocking, UI, game passes, analytics events, and every effect listed in
      `design/eggs-and-effects.md`. All 14 build-stage effects are named by a
      brief, checked by matching the design table against the brief text
      rather than by eye.
- [x] `python factory/tools/gate.py games/egg-champions planned` exits 0.
- [x] `python factory/tools/state.py next games/egg-champions` prints `built`.
- [x] Committed and pushed.

## Stop here for review
After this task, stop and tell the owner the task list is ready. He reviews it
once before the orchestrator starts building.

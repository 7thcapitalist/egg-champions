# Factory task 05: Orchestrator

## Goal
One command builds a game from its task list with nobody typing: it starts the
right agent for each step, checks the result, retries, and stops with a clear
report when it cannot continue.

## Build
1. `factory/tools/run_factory.py <game-dir>` (standard library only). Loop:
   - Read `state.json`. For the current stage, run its agent, then its gate.
   - For the `built` stage, walk `tasks/index.json` in dependency order. For
     each pending task: start a fresh headless Claude Code run with the
     `coder` agent and that one brief; then run the brief's Done-when
     commands, the test entry point, `rojo build`, selene, and stylua.
   - Pass: mark the task done, commit, push, go on.
   - Fail: retry up to 2 more times, giving the coder the failing output.
     Still failing: mark the task blocked, write a report, and stop.
   - Write a log line per step to `games/<game>/reports/run-log.md` and a
     short `games/<game>/reports/latest.md` (what was done, what failed, what
     is next) at the end of every run.
   Use `claude --help` and Claude Code's documentation to find the current
   flags for running without prompts and for limiting tools. Do not guess them.
2. Safety limits inside the loop:
   - Never publish to production. Only the test place, and only in a later stage.
   - Never read, print, or commit `.env`.
   - A coder run may only change files under `games/<game>/src`,
     `games/<game>/tasks`, and test files. If a run changes the spec,
     generated config, `factory/`, or `.claude/`, reject it and revert.
   - A maximum number of tasks per run (default 5) and a time limit per task,
     so a bad loop cannot burn the whole usage allowance.
3. `.claude/commands/build-game.md`: a slash command that runs the
   orchestrator for a game folder and then summarizes `reports/latest.md`.
4. Document in `factory/README.md` how to start a run and how to resume after
   a blocked task.

## Done when
- [ ] `python factory/tools/run_factory.py games/egg-champions --max-tasks 2`
      completes the first two pending tasks with no input, each committed and
      pushed, and both pass their checks.
      Not run yet: a Claude Code session's own permission classifier refuses
      to start a nested headless `claude` run, so this first live run has to
      be started by a person from a terminal.
- [x] A deliberately failing check produces a retry, then a blocked task and a
      report, and the loop stops (test this on a scratch branch, then discard it).
      Tested on a scratch branch with `--agent-cmd` standing in for the coder:
      stylua failed, the failure went back into attempts 2 and 3, the task was
      blocked, its work saved as a patch that applies cleanly, the tree was
      reverted, and `latest.md` named the next step. Branch discarded.
- [x] An attempt by a coder run to edit `games/egg-champions/config/` is
      rejected and reverted.
      Same scratch branch: every attempt that touched `config/` was rejected,
      and `config/` and `src/` were left as they were.
- [x] `reports/latest.md` reads clearly to someone who was not watching.
- [x] Committed and pushed.

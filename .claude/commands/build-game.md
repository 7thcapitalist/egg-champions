---
description: Run the factory orchestrator on one game folder, then summarize its report
argument-hint: <game-dir> [--max-tasks N] [--unblock ID]
allowed-tools: Bash(python factory/tools/run_factory.py *), Read
---

Run the factory orchestrator for this game, then report on it.

1. Run, from the repo root:
   `python factory/tools/run_factory.py $ARGUMENTS`
   If no game folder was given, use `games/egg-champions`. The run can take a
   long time: up to `--task-minutes` (default 60) per task. Let it finish.
   Do not edit files, commit, or retry anything yourself while it runs or
   after it stops. The orchestrator owns those steps.
2. Read `<game-dir>/reports/latest.md`.
3. Summarize it in a few lines: the result, each task finished with its
   commit, what failed and why in one sentence each, and the exact next step
   it names. If a task is blocked, name the patch and coder reports to read.

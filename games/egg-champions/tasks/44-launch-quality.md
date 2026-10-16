# Task 44: Launch quality and inventory usability

## Goal

Owner requested a substantial launch polish pass after finding rear-facing
portraits and missing team shortcuts. The task list and remaining release
evidence are in `../LAUNCH-WORK.md`.

## Build

1. Front-facing pet portraits with real bounds, larger cards and variant previews.
2. Server-authoritative best coins, best battle strength and unequip-all actions.
3. Search, useful filters, accessible collection tabs and stable inventory rendering.
4. Save ordering that cannot reopen a released player session.
5. A scrolling pass shop that fits short screens.
6. Safe local Studio QA scenarios, Auto Hatch and real gym opponent models.

## Done when

- [x] `python -B factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.
- [x] Studio evidence checks portraits, inventory actions, hatch flow, gym interaction and responsive screens in the launch report.
- [x] Release blockers are recorded honestly; local QA never claims persistent DataStore or a production release.
- [x] Work is committed locally. No push or publishing as part of this task.

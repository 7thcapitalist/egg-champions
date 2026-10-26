# Task 38: Studio save bug, analytics funnel, and a playtest mode

## Build
1. Profiles: in Studio, treat an UpdateAsync error containing "API access is
   not enabled" (or starting with "403:") as no access: one try, then the
   temporary profile.
2. Analytics: call AnalyticsService:LogOnboardingFunnelStepEvent(player,
   step, stepName) (the method LogOnboardingStepEvent does not exist).
   Update `notes/analytics-events.md` to the "|" separator.
3. Playtest mode: when RunService:IsStudio() and ServerScriptService has the
   attribute PlaytestNoPasses = true, PassService treats every pass as not
   owned, so tests play like a new player. Never active outside Studio; spec
   that the flag is ignored when not in Studio.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

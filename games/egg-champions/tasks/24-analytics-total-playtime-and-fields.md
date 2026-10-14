# Task 24: Analytics measures total playtime and sends its fields

## Goal
The tuner's pacing targets (gym 1 in 20 to 30 min, final gym in 6 to 8 h)
are cumulative play time, but every event reports time since the current
session started. Some documented fields also never reach Roblox.

## Build
1. Persist cumulative playtime in the profile (add a migration). Update it
   on save and on leave from the session time.
2. Send total playtime (plus session time) on first_hatch, gym_attempt,
   gym_result, rebirth and world_unlocked.
3. Make the fields that matter actually reach Roblox: petId on pet_hatched,
   team on pet_equipped, coinsPerClick on session_end, rebirths on
   gym_attempt and gym_result. Where a field cannot fit the custom field
   limits, remove it from notes/analytics-events.md so the doc matches what
   is really sent.
4. Tests: total playtime grows across simulated sessions and survives the
   migration; each event's sent fields match the doc table.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

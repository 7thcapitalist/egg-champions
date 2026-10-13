# Task 19: Analytics events

## Goal
Enough data to tell whether the pacing the economy tuner predicted is what
players actually live, so the spec can be corrected from evidence instead of
guesses.

## Build
1. `src/server/Analytics.luau`: one door for every event, server side only.
   - `Analytics.fire(player, eventName, fields)` with a fixed event list in
     one table. An event not in the table is an error, so names cannot drift.
   - Batches events and flushes on an interval and on leave, each send
     wrapped in `pcall`. Analytics must never break gameplay: a failed send
     is dropped with a log, not retried forever.
   - Use Roblox's own `AnalyticsService` for the funnel and economy events it
     supports, and keep the rest as custom events.
2. The event list, chosen to measure the tuner's own targets so the report
   and reality can be compared directly:
   - `first_hatch` with seconds since join. The tuner targets
     `pacing_first_hatch_minutes`.
   - `gym_attempt` and `gym_result` with world index, rebirths, outcome and
     seconds since join. The tuner targets `pacing_gym1_minutes_min/max` and
     `pacing_final_gym_hours_min/max`, and records target rebirths per gym.
   - `egg_bought` with egg id, price and coins after.
   - `pet_hatched` with pet id, rarity and variant. Lets the real rarity
     distribution be checked against `config/rarities.json`.
   - `pet_equipped` with pet id and the team after.
   - `rebirth` with the new count and seconds since join.
   - `world_unlocked` with world index and seconds since join.
   - `pass_purchased` with pass id.
   - `session_start` and `session_end` with length, coins per click and
     rebirths.
3. Every event carries the player's rebirth count and current world, because
   almost every question starts with "at what stage".
4. No personal data beyond the Roblox user id. No event fires from the
   client: the client cannot be trusted with the numbers that will be used
   to retune the economy.
5. Write `games/egg-champions/notes/analytics-events.md` listing each event,
   its fields, and the tuner target or spec question it answers. The
   playtester and the tuner both read this.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including a test that firing an event not in the table errors, and a
      test that every event in the table has a documented row in
      `notes/analytics-events.md`.
- [x] `grep -rn "Analytics" games/egg-champions/src/client` finds nothing:
      events fire only on the server.
- [x] A test asserts the event list covers every tuner target named in
      `tuning/report.md`, so a pacing target can never go unmeasured.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] After a test session, the events appear in the Roblox analytics
      dashboard with the right fields.

## Out of scope
Dashboards and analysis. This task emits the events; reading them is the
playtester's and the tuner's job.

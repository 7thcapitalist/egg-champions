# Task 07: Player profile and saving

## Goal
A player's progress survives leaving and rejoining, and cannot be lost or
duplicated by two servers at once.

## Build
1. `src/shared/rules/Profile.luau`, pure and testable:
   - `Profile.new()` returns the empty profile: `coins`, `pets` (a list of
     `{uid, petId, variant}`), `team` (a list of uids), `index`, `badges`,
     `rebirths`, `gymsBeaten`, `feesPaid`, and a `version` number.
   - `Profile.migrate(data)` upgrades an older `version` to the current one
     and returns the result. An unknown or newer version is an error, not a
     silent reset: losing a player's save is worse than refusing to load it.
   - `Profile.validate(profile)` returns a list of problems: a team longer
     than `constants.team_size`, a team uid the player does not own, a petId
     that is not in config, negative coins. Used on load, so a corrupt save
     is repaired or rejected rather than trusted.
2. `src/server/Profiles.luau`:
   - One DataStore, one key per user id. Load on join, save on leave, and
     autosave on an interval read from a module constant.
   - Session locking: a profile records the server that holds it and a
     heartbeat. A second server waits for the lock to go stale before
     loading, so two servers never write the same profile.
   - Every write is wrapped in `pcall` with a bounded retry. A failed save is
     logged and retried, never swallowed.
   - On load, run `Profile.migrate` then `Profile.validate`. Repair what is
     repairable (trim an over-long team), refuse what is not, and log either
     way.
   - Nothing else in the codebase touches the DataStore. This module is the
     only door.
3. `src/shared/rules/specs/Profile.spec.luau`, registered in `specs.luau`.
   Cover at least:
   - A new profile passes `validate`.
   - A v1 profile migrates to the current version with its coins and pets
     intact.
   - An unknown version is refused rather than reset.
   - A team holding a uid the player does not own is reported.
   - A team longer than `team_size` is reported.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0 with the
      new specs included.
- [ ] `grep -rn "GetDataStore" games/egg-champions/src` matches only
      `src/server/Profiles.luau`.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] In the test place: earn coins, hatch a pet, equip it, leave, rejoin,
      and find coins, pet and team unchanged.
- [ ] Join from two sessions at once and confirm the second waits for the
      lock rather than overwriting.

## Out of scope
The remotes that change a profile. Task 08 adds those; this task owns the
shape, the migration and the storage.

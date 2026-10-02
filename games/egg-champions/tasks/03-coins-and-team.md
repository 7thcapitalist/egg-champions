# Task 03: Coins, click power, and the team of 3

## Goal
The rules that turn an equipped team into coins per click, and the rules that
say which pets may be equipped. Pure Luau, fully tested, no Roblox services.

## Build
1. `src/shared/rules/Team.luau`:
   - `Team.maxSize()` reads `constants.team_size`. Never the literal 3.
   - `Team.canEquip(team, petUid)` and `Team.equip` / `Team.unequip`, working
     on a plain list of owned pet uids. Rejects a full team, a duplicate uid,
     and a uid the player does not own, each with a distinct reason.
   - Equipping is one list used for both clicking and battling. There is no
     second team.
2. `src/shared/rules/Coins.luau`:
   - `Coins.clickPowerOf(pet)` returns a pet's Click Power including its
     variant multiplier: `pets.click_power` times
     `variants[variant].click_mult` when the pet has a variant.
   - `Coins.perClick(state)` implements the spec formula:
     `(1 + sum of equipped Click Power) x (1 + rebirth_coin_bonus x rebirths)
     x (1 + index_egg_bonus x completed eggs) x passMultiplier`.
     Every factor comes from config. The pass multiplier is an input, not a
     lookup, so task 18 can supply it without this module knowing about
     passes.
   - `Coins.completedEggs(index)` counts eggs where all `pets_per_egg` normal
     pets have been hatched. Shiny and golden do not count toward completion.
3. `src/shared/rules/specs/Team.spec.luau` and `Coins.spec.luau`, registered
   in `src/shared/testing/specs.luau`. Cover at least:
   - An empty team earns 1 coin per click, not 0.
   - Each rebirth adds exactly `rebirth_coin_bonus`, checked at 0, 1 and 5.
   - A completed egg adds exactly `index_egg_bonus`, checked at 0 and 6 eggs.
   - Shiny and golden multiply click power by their config values.
   - Equipping a fourth pet is rejected, and the team is unchanged after the
     rejection.
4. Delete `src/shared/rules/Example.luau` and its spec.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0 with the
      new specs included in the count.
- [ ] `grep -rnE "[^a-zA-Z_][0-9]{2,}" games/egg-champions/src/shared/rules`
      finds no game number: every number comes from config.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Out of scope
Earning coins at runtime, the click remote, and the UI. This task is the
rules only. Task 08 wires them to the server and task 10 to the screen.

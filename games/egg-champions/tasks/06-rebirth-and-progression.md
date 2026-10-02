# Task 06: Rebirth, badges, and world unlocking

## Goal
The rules for long-term progress: which worlds are open, which gyms are
beaten, what a rebirth costs and what it resets. Pure Luau, fully tested.

## Build
1. `src/shared/rules/Progression.luau`:
   - `Progression.worldUnlocked(state, worldIndex)`: world 1 is always open.
     World N is open when the gym of world N-1 is beaten in the current
     rebirth run.
   - `Progression.eggUnlocked(state, eggId)`: an egg is buyable only when its
     world is open. Eggs of locked worlds cannot be bought, as the tuner
     assumes.
   - `Progression.beatGym(state, worldIndex)` records the win, awards the
     badge, and opens the next world. Badges are kept forever and survive
     rebirth; gym wins in the current run do not.
   - `Progression.isFinalGymBeaten(state)` drives the "World 4 coming soon"
     gate.
2. `src/shared/rules/Rebirth.luau`:
   - `Rebirth.cost(rebirths)` is
     `rebirth_first_cost x rebirth_cost_growth ^ rebirths`, from config.
   - `Rebirth.canRebirth(state)` is true when coins are at least the cost.
   - `Rebirth.apply(state)` returns the new state: coins to 0, gym progress
     and paid fees cleared so worlds lock again, `rebirths` plus one. Pets,
     the pet index and badges stay untouched. This split is the whole point
     of the module, so the test names it explicitly.
3. `src/shared/rules/specs/Progression.spec.luau` and `Rebirth.spec.luau`,
   registered in `specs.luau`. Cover at least:
   - Costs for rebirths 0 through 5 against hand-computed values from config.
   - After a rebirth: coins 0, worlds relocked, gyms unbeaten, fees unpaid,
     and pets, index and badges all intact.
   - A world is locked until the previous gym is beaten, and relocks after a
     rebirth.
   - An egg of a locked world is not buyable.
   - A badge already earned is not lost or duplicated by beating the gym
     again after a rebirth.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0 with the
      new specs included.
- [ ] A test asserts the exact set of fields a rebirth clears and the exact
      set it keeps, so a later change to the state shape cannot silently
      start wiping pets.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Out of scope
Saving the state, the rebirth button, and the rebirth effect. Task 07 saves,
task 10 shows it, task 17 animates it.

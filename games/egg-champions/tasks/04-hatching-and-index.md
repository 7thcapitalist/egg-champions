# Task 04: Hatching, variants, and the pet index

## Goal
The rules that pick which pet comes out of an egg, which variant it rolls,
and what the pet index records. Pure Luau, fully tested, no Roblox services.

## Build
1. `src/shared/rules/Hatch.luau`:
   - `Hatch.roll(eggId, rng, options)` returns
     `{petId, variant}` where `variant` is nil, `"shiny"` or `"golden"`.
   - Rarity is rolled from `rarities[].hatch_chance`, then the pet is the one
     pet of that rarity in that egg. The odds table comes from config, and
     the chances must sum to 1 or the module errors loudly at load.
   - Variant is rolled independently of rarity, from
     `variants[].hatch_chance`. Golden is checked before shiny so the rarer
     result wins; a hatch is never both.
   - `options.luckyEggs` doubles the Epic and Legendary chances and takes the
     difference off Common, renormalising so the table still sums to 1.
     Task 18 supplies this flag.
   - `rng` is injected, never `math.random` directly, so tests are
     deterministic. Accept anything with the `Random:NextNumber()` shape and
     provide a pure Luau fallback for headless tests.
   - `Hatch.rollMany(eggId, rng, options, count)` for Triple Hatch. Each roll
     is independent.
2. `src/shared/rules/PetIndex.luau`:
   - `PetIndex.record(index, petId, variant)` marks that pet and variant seen.
     Normal, shiny and golden are tracked separately, as the spec says.
   - `PetIndex.isEggComplete(index, eggId)` is true when all `pets_per_egg`
     normal pets of that egg are seen.
   - `PetIndex.fruitEdition(index)` lists the seen Fruit Edition pets, which
     are the pets whose config `edition` is set. Fruit Edition is a collection
     tag, not a type or a rarity.
3. `src/shared/rules/specs/Hatch.spec.luau` and `PetIndex.spec.luau`,
   registered in `specs.luau`. Cover at least:
   - A seeded rng gives a repeatable sequence of hatches.
   - Over many rolls with a stubbed rng that walks the unit interval, each
     rarity appears at its config rate within a stated tolerance.
   - Lucky Eggs doubles Epic and Legendary and the table still sums to 1.
   - Golden and shiny never both appear on one hatch.
   - An egg becomes complete only after all 5 normal pets, and a shiny pet
     alone does not complete it.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0 with the
      new specs included.
- [x] A test asserts the rarity table sums to 1 and fails if config drifts.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Out of scope
Buying an egg, spending coins, the hatch animation, and the shop screen.
Task 08 wires the server, task 11 the shop, task 15 the animation.

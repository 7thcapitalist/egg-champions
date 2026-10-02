# Task 14: Pet visuals and variant looks

## Goal
One way to show a pet everywhere in the game, as a colored placeholder block,
plus the shiny and golden looks and the elemental idle emitter. The asset
stage swaps the block for a model later without touching any caller.

## Build
1. `src/shared/PetVisual.luau`: the single source of a pet's look.
   - `PetVisual.create(petId, variant)` returns a Model: a block whose color
     comes from the pet's type (orange fire, green grass, yellow electric,
     blue water) with a rarity-colored band, sized by rarity so a Legendary
     reads as larger. Type and rarity come from config.
   - One function, used by the battle arena, the egg stand displays, the
     shop result and the team bar. No caller builds its own pet.
   - The model carries an attachment point named for the elemental feature,
     so the idle emitter and the asset stage's real model agree on where
     effects go.
2. Variant looks, from `design/eggs-and-effects.md`:
   - Shiny: brighter colors and a sparkle particle emitter.
   - Golden: gold material and a soft glow.
   - A pet is never both. The look is driven by the variant the server sent.
3. Elemental idle: a small looping emitter on the attachment point for pets
   whose type has a visible feature (fire, sparks, water). Low particle
   count, short lifetime, and disabled when the model is off screen or more
   than a set distance away. The distance and counts live in one table at
   the top of the module.
4. A swap seam the asset stage will use: `PetVisual` reads an optional model
   id per pet from one table. When the table has no entry, it builds the
   block. The asset stage fills the table and nothing else changes.

## Done when
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including a test that every pet in config resolves to a color and a
      size, so a new pet cannot render as nil.
- [ ] `grep -rln "Instance.new(\"Part\")" games/egg-champions/src` shows pets
      built only in `PetVisual.luau` and the world kit from task 09.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] A shiny pet and a golden pet are clearly different from a normal one at
      a glance, and from each other.
- [ ] With a full team of fire pets in battle, the idle emitters do not hurt
      frame rate on a phone-class device.

## Out of scope
Real pet models, which are the asset stage. This task is the placeholder and
the seam that replaces it.

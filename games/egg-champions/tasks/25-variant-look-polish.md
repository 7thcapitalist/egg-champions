# Task 25: Variant look polish

## Goal
Small fixes to the shiny and golden looks found in review.

## Build
1. The twinkle image uses a .dds particle texture in an ImageLabel, which
   may not load. Use a texture that is known to load in an ImageLabel (a
   built-in rbxasset png, or an id kept in EffectsBudget). Keep the number
   and the id in EffectsBudget.
2. Give the VariantFx frame and stroke the same UICorner as the pet card it
   sits in, so the stroke is not square inside a rounded card.
3. When a battle pet faints, fade the VariantFx overlay along with the model.
4. Test that PetVisual's variant builder only creates classes listed in
   EffectsBudget.VIEW_CLASSES (build it against a fake parent and walk the
   created instances), so a future emitter in the viewport fails a test.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Normal, shiny, and golden versions of one pet are clearly different at a glance.

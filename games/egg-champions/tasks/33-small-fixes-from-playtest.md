# Task 33: Small fixes from the playtest and review

## Build
1. Analytics: strip or replace commas and quotes in every custom field value
   (join lists with "|"); guard LogOnboardingStepEvent with a pcall and fall
   back to a custom event so first_hatch is recorded. Spec: no custom field
   value contains a comma or quote.
2. Profiles: in Studio, when the first UpdateAsync error mentions
   StudioAccessToApisNotAllowed, go straight to the temporary profile
   instead of five retries (sessions start in about 20 s today).
3. World labels: the gym sign is sized in studs and sits above the roof
   (its third line is cut today); the world sign text fits its board; the
   egg stand signs are readable from spawn (larger plate, dark backing,
   LightInfluence 0).
4. Shared constants for the "SpinningEgg" tag and the "Gym_" prefix; the
   sign anchor height uses the egg's configured height; PRICE_GOLD uses
   Theme.
5. Rate limit on all RemoteFunctions in Guard, SkipTutorial included.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

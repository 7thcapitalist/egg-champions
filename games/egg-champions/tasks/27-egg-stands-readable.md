# Task 27: Egg stands you can read

## Goal
In the playtest the two egg stands' signs ("Meadow Egg 50 coins" and
"Forest Egg 5,000 coins") print on top of each other in huge text, and the
eggs on the stands look like small yellow blobs.

## Build
1. Space egg stands so no two signs overlap from the spawn point: at least
   14 studs apart, laid out in an arc facing spawn. Keep positions in the
   world layout data, not hard-coded in builders.
2. Sign billboards: smaller text, not AlwaysOnTop, MaxDistance about 60, so
   only nearby signs show. Name on one line, price below in gold.
3. Each stand shows that egg's real model from ReplicatedStorage.PetModels
   (the asset stage loads egg templates there) at its configured height,
   slowly rotating; the placeholder only if the model is missing.
4. Tests on the layout data: no two stands closer than the minimum distance,
   every egg in a world has a stand.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

# Task 09: Worlds built by code

## Goal
Three small islands generated from the world table, with egg stands, a gym
building and a portal. Nothing placed by hand, so a world table change
rebuilds the world.

## Build
1. `src/server/World/Kit.luau`: about ten prop builders, each a function
   returning a Model made from parts only. Ground, cliff, tree or rock,
   water plane, egg stand, gym building, portal frame, sign, light, and one
   scenery filler. Parts and colors only, no meshes: final art is the world
   stage's job.
2. `src/server/World/Builder.luau`:
   - `Builder.buildAll()` reads `Config.worlds` and builds one island per
     world, spaced on a grid, with each world's `environment` string driving
     its palette. A world's palette lives in a table in this module keyed by
     world id, not in the spec.
   - One egg stand per egg in `worlds[].eggs`, labelled with the egg name and
     price from config.
   - One gym building per world, labelled with the fee and the leader type.
   - A portal per world pointing at the next world, locked until
     `Progression.worldUnlocked` says otherwise.
   - Every generated instance goes under one folder per world in Workspace,
     so a rebuild clears and regenerates without touching anything else.
3. Spawn and teleport: the SpawnLocation sits on world 1. Walking into an
   unlocked portal moves the player to the next world. A locked portal
   refuses and tells the player what is needed. The server decides whether a
   portal is passable.
4. Egg stands are the only place eggs are bought. Touching a stand opens the
   shop screen (task 11) filtered to that egg; until that task lands, it
   fires the `BuyEgg` remote directly so the stand is testable now.
5. Replace the placeholder Baseplate from task 01 with the generated ground,
   and keep the SpawnLocation.

## Done when
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] A test asserts `Builder` creates one egg stand per egg in config and
      one gym per world, by counting what it builds against the config
      counts, so a fourth world needs no code change.
- [ ] `grep -rn "SpecialMesh\|MeshPart\|rbxassetid" games/egg-champions/src/server/World`
      finds nothing: parts only at this stage.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] In the test place: all three islands exist, the world 1 stands and gym
      are labelled with the right numbers, and the portal to world 2 is
      locked until gym 1 is beaten.
- [ ] Frame rate on a phone-class device is acceptable with all three worlds
      loaded.

## Out of scope
Final world art, meshes and terrain. The world stage replaces this kit later.
Pet models are task 14's placeholder blocks.

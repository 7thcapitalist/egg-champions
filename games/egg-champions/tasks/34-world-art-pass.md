# Task 34: Worlds that look good

## Goal
The owner finds the map "not that beautiful and things strange": a grey slab
island, blocky trees, a plain yellow box for a gym, flat baseplate look. Make
each world look like a polished Roblox simulator, built from code at server
start so the build stays file based.

## Build
1. Terrain per world with the Terrain API (FillBlock, FillBall, FillWedge),
   from layout data, replacing the grey slab:
   - Green Meadow: rolling grass hills, a flower field, a small pond with
     water, a dirt path from spawn to the egg stands and on to the gym.
   - Coral Coast: sand beach, shallow turquoise water around the island,
     a few rock outcrops, a path.
   - Ember Volcano: basalt and slate ground, glowing lava streams (CrackedLava
     material plus a soft orange PointLight here and there), ash-grey rock.
2. Lighting per world, applied when the player enters it: Atmosphere
   (density, haze, color), a Sky, ColorCorrection, Bloom kept subtle,
   ClockTime. Meadow bright morning; Coast warm sunny; Volcano dusk with an
   orange haze.
3. Props from parts, done well: trees with a trunk and layered rounded
   foliage (Ball and Cylinder parts, SmoothPlastic, two or three greens),
   rocks as rotated unions of a few wedges and balls, fences along the path,
   palms on the coast, dead trees and boulders on the volcano. Scatter them
   with a seeded random from layout data, keeping a clear radius around
   spawn, stands, gym and portal, and never on the path.
4. Gym building per world: a proper arena: a raised round platform with
   steps, pillars, a banner in the world's type color, the leader's type icon,
   the sign above the entrance. Portal: a stone arch with a glowing swirl.
5. Pure specs on the layout data: props never inside the clear zones, all
   features on the island, deterministic placement for the same seed.
6. Performance: keep part counts per world under a budget constant (for
   example 1,500 parts) and anchor everything; StreamingEnabled friendly.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Screenshots of each world from spawn, from above and at player eye level.

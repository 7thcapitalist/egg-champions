# Task 36: A hatch you can see, and a gym you know about

## Goal
Playtest: the egg shop closes 1.5 s after the first hatch, before the player
sees what they got; after the first equip nothing names the gym or its fee;
the world name sign stands behind spawn.

## Build
1. Hatch reveal: after every hatch a centered reveal shows the pet model,
   name, rarity color, Shiny or Golden badge and "Click +N"; it stays until
   the player taps "Nice!" or 3 s pass. During the tutorial the shop closes
   only after the reveal ends.
2. The goal card shows a second, muted line "Next: Green Meadow Gym (50K)"
   (from config) under the current small goal; tapping it turns on the beam
   and edge arrow to the gym. The beam turns on by itself once the team is
   full.
3. The world name sign stands in front of spawn, facing the player.
4. Specs for the reveal timing logic and the second goal line text.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

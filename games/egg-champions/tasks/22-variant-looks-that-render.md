# Task 22: Shiny and golden looks that actually show

## Goal
The reviewer found that shiny sparkle, golden glow, and elemental idle
effects never appear: every pet is drawn inside a ViewportFrame, and Roblox
does not render particles or lights there. Shiny and golden must be clearly
different from normal at a glance, everywhere a pet appears.

## Build
1. Inside ViewportFrames, use only things that render there: material and
   color changes on the model, a highlighted outline, and UI effects layered
   on the frame itself (a UIGradient shimmer, a UIStroke in the variant
   color, small sparkle ImageLabels animated with tweens).
   Shiny: brighter colors, a pale shimmer, and a few twinkles.
   Golden: gold material look, a warm gold stroke, and a slow glow pulse.
2. Remove the distance-culled emitter loop that watches emitters which never
   exist, or keep emitters only for pets that are really in the 3D world.
3. Keep every number in the effects budget module.
4. Tests on the pure look data: every variant maps to a viewport-safe look,
   and no viewport look depends on a ParticleEmitter or a Light.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Normal, shiny, and golden versions of one pet are clearly different at a glance.

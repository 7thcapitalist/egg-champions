# Task 30: Pets screen fits, and the tutorial guides inside screens

## Goal
Playtest: EQUIP is half cut off at the bottom of the detail panel, the
filter row runs under the detail panel, "3 EQUIPPED" overflows its tile, a
bare "3" has no label, and once a screen is open the tutorial gives no
guidance (the goal card hides, the pointer targets a button behind the modal).

## Build
1. Pets detail: EQUIP sits right under the pet name, always inside the panel
   and on screen at 808 x 432 and 1280 x 720. The rest of the panel scrolls.
2. Filter and sort row wraps or scrolls instead of running under the detail
   panel; 3 columns when content width is under 500 px; tile markers on their
   own line; the number reads "Click +3".
3. Special move text shows real numbers from config/specials.json (for
   example "Heal: restores 25% of max HP").
4. In-screen tutorial bar: while a tutorial step is active and a screen is
   open, a one-line bar in that screen's header says what to do there ("Tap
   HATCH on the Meadow Egg", "Tap your new pet, then EQUIP"). In the equip
   step, point at the first owned pet tile until a pet is selected, then at
   EQUIP. After the first hatch in the hatch step, close the egg shop
   automatically so the pointer never targets a hidden button.
5. Pure layout specs for the detail panel and filter row at both sizes, and
   Tutorial specs for the new in-screen targets.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

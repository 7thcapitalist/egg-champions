# Task 26: A clean main screen

## Goal
The owner played the build and called the screen "super polluted". Playtest
screenshot problems: the four pass buttons sit in the top bar, the world name
overlaps "BADGES" and a stray diamond glyph sits on it, five big menu buttons,
a large next-goal panel, and three "Empty" team slots before the player owns
a pet. Keep the approved style (design/ui/Main.dc.html: dark flat panels,
thin borders, gold accent) but show much less at once.

## Build
1. Top bar: coins and coins per click on the left, world name centered on its
   own (no overlap with anything at 1280 x 720, 1920 x 1080 and a 844 x 390
   phone), rebirths small on the right. Remove the badge text and any stray
   glyph. Remove the four pass buttons from the HUD; passes live only in the
   Shop screen.
2. Left menu: four compact buttons, EGGS, PETS, REBIRTH, SHOP. The Index is a
   tab inside the Pets screen.
3. Next-goal panel: a small card (at most a quarter of the screen height)
   with one line and one button. Hidden while any menu screen is open.
4. Team bar: hidden until the player owns a pet. Then show only owned slots,
   up to the team size.
5. Add a pure layout check: a function that takes the HUD element rectangles
   for a given screen size and returns overlaps. Specs assert no overlaps at
   the three sizes above.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

## Needs human or playtester
- Screenshot of the main screen at 1280 x 720 before and after a first pet.

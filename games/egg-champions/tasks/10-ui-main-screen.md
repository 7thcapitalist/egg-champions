# Task 10: UI, main screen

## Goal
The screen the player sees most: coins, the world, the team, and clicking
anywhere to earn. Built in Roblox to match the approved mockup.

## Build
Read `design/ui/README.md` and `design/ui/Main.dc.html` first. The mockup is
1280 x 720 and carries the exact colors, sizes and type. Match it; do not
redesign it.

1. `src/client/UI/Theme.luau`: the approved palette and type in one module,
   used by every later UI task. Panel `#12161F`, border `#2A3242`, text
   `#F2F4F8`, muted `#9BA6BA`, gold accent `#E8B33A`, and the rarity colors
   from the README: Common grey, Uncommon green, Rare blue, Epic purple,
   Legendary orange. Read the rarity order from config, not a hand-written
   list. Barlow and Barlow Condensed, or the closest Roblox font, with
   uppercase labels, small corner radius and thin borders.
2. `src/client/UI/Main.luau`, a ScreenGui with:
   - A slim top bar, 64px: coin total, coins per click in gold, the world
     name and index centred, rebirth count, and one badge marker per world
     from config, filled when earned.
   - The left menu: the buttons in the mockup, each opening its screen.
   - The next-goal panel on the right: what the player is saving for now
     (the next egg, the gym fee, or the rebirth cost) with a progress bar.
     Pick the goal from profile state, with the rule in one small function
     so it can be tested.
   - The team of 3 at the bottom: one slot per `constants.team_size`, each
     showing the pet, its rarity stripe and its click power.
3. Clicking: there is no click button. A full-screen transparent button
   behind the panels sends `Click` on press, anywhere on the world view.
   Panels and menu buttons must swallow their own clicks so pressing Eggs
   does not also earn a coin.
4. All numbers shown come from the server through `ProfileChanged`. The
   client never computes coins per click for display; it shows what the
   server sent. Abbreviate large numbers (1.2K, 3.4M, 5.6B) in one shared
   formatting helper with its own tests.
5. Scale for phones: anchor and size in scale rather than offset where the
   mockup allows, and keep every tap target at least 44px.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including tests for the number formatter and the next-goal rule.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `grep -rn "0x\|Color3.fromRGB" games/egg-champions/src/client/UI`
      shows colors only in `Theme.luau`.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Side by side with `design/ui/Main.dc.html`, the layout matches: top bar
      contents and order, menu, next-goal panel, team bar.
- [ ] Clicking the world earns coins and the amount pops where the click
      landed. Pressing a menu button does not earn a coin.
- [ ] The screen is usable on a phone-sized viewport.

## Out of scope
The other three screens, and the click pop animation itself, which is task
15. This task fires the click and shows the totals.

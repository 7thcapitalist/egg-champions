# Task 11: UI, egg shop

## Goal
The screen where coins become pets: one card per egg, honest odds, and the
two hatch buttons.

## Build
Read `design/ui/README.md` and `design/ui/EggShop.dc.html` first. Match the
mockup.

1. `src/client/UI/EggShop.luau`, a ScreenGui screen using
   `src/client/UI/Theme.luau` from task 10:
   - One card per egg in `Config.eggs`, in config order, so a new egg needs
     no code change.
   - Each card shows the egg name, its price, and all five pets with their
     rarity and hatch chance. The odds come from `config/rarities.json`, so
     the screen can never advertise odds the server does not roll.
   - A locked egg is visibly locked and says what unlocks it, using
     `Progression.eggUnlocked`.
   - An egg the player cannot afford shows the price in a muted state. The
     button is still pressable and the server still refuses it; the client
     never enforces the rule, it only hints.
2. `Hatch` and `Hatch x3` buttons. `Hatch x3` is only offered when the
   player owns the Triple Hatch pass, which the server reports. Both send
   `BuyEgg` with the egg id and a count; they never send a price.
3. The result: show what hatched, its rarity and its variant, straight from
   the server's reply. Three results from `Hatch x3` show as three.
4. Entering from an egg stand (task 09) opens this screen scrolled to that
   egg's card.
5. Pets shown here are the placeholder blocks from task 14 until the asset
   stage lands. Until task 14 is done, a colored frame with the pet name is
   enough.

## Done when
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] A test asserts the odds the screen would display for every egg equal
      the config hatch chances, so the display cannot drift from the roll.
- [x] `grep -rn "price\s*=\s*[0-9]" games/egg-champions/src/client` finds no
      hard-coded price.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Side by side with `design/ui/EggShop.dc.html`, the card layout, odds
      list and buttons match.
- [ ] Buying an egg spends the right coins and returns a pet; buying with too
      few coins is refused with a readable message.
- [ ] A locked egg cannot be bought and says why.

## Out of scope
The hatch animation and the rarity reveal, which are task 15. This task shows
the result as text and a frame.

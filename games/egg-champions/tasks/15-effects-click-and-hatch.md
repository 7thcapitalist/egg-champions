# Task 15: Effects, clicking and hatching

## Goal
The two moments the player sees most often feel good: every click pays out
visibly, and every hatch is a small reveal.

## Build
Read the effects table in `design/eggs-and-effects.md`. This task builds the
click pop, the hatch sequence and the rarity reveal.

1. `src/client/Effects/Effects.luau`: one module every effect task adds to,
   with a shared budget. Keep a table at the top holding particle counts,
   lifetimes and tween durations, so the whole feel can be tuned in one
   place and the phone budget is visible.
2. Click pop:
   - The coin amount pops up at the click position, rises and fades.
   - A small coin burst on the world at the same point.
   - The amount shown is the value the server credited, not a client guess.
   - Pooled and capped: at 20 clicks per second the effect must reuse
     instances rather than creating new ones, and never queue more than a set
     number of live pops.
3. Hatch sequence, on the shop screen:
   - The egg shakes three times, cracks with a flash in the rarity color,
     and the pet appears with its name and rarity.
   - Longer and brighter for Epic and Legendary. The per-rarity duration
     lives in the budget table, keyed by rarity id from config.
   - `Hatch x3` plays three reveals in sequence, or one grouped reveal, but
     never three overlapping animations.
   - The sequence must be skippable by tapping, because players hatch
     hundreds of eggs.
4. Rarity reveal: colored light rays behind the pet in the rarity color, grey
   through orange, read from the same rarity colors as `Theme.luau` so the
   stripe and the rays never disagree.
5. Nothing in this task changes what the player gets. The result is already
   decided by the server; these are only the visuals for it.

## Done when
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including a test that every rarity id in config has a reveal duration
      and a color.
- [ ] A test asserts the click pop pool never exceeds its cap when fed more
      clicks than the cap.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Clicking fast stays smooth on a phone-class device, with no growing
      instance count in the Explorer.
- [ ] A Legendary hatch is clearly a bigger moment than a Common one.
- [ ] The hatch sequence can be skipped and the result still shows.

## Out of scope
Battle effects (task 16) and progression effects (task 17).

# Task 17: Effects, progression

## Goal
The three moments that mark real progress land as events: winning a gym,
rebirthing, and opening a world.

## Build
Read the effects table in `design/eggs-and-effects.md`. This task builds the
gym win, rebirth and world unlock effects.

1. Gym win, on the battle screen ending in a win:
   - The badge appears with a burst, in the gold accent.
   - Then the portal to the next world lights up. If the player is not
     standing in the world, the lighting still happens, so returning shows it
     already open.
   - The last gym shows the badge and the "World 4 coming soon" gate instead
     of a portal, driven by `Progression.isFinalGymBeaten`.
2. Rebirth:
   - A screen flash and a rising ring around the player.
   - Shown only after the server confirms the rebirth, since the rebirth is
     the server's decision. Never play it optimistically: a refused rebirth
     that still flashed would be a lie about losing every coin.
   - Afterwards the main screen shows the new rebirth count and the relocked
     worlds.
3. World unlock:
   - The portal activates with a swirl in the new world's color, using the
     same per-world palette table as the world builder in task 09 rather
     than a second copy.
   - Walking through an open portal plays the swirl; a locked portal shows
     its locked state and what is needed.
4. All three read their state from `ProfileChanged`, so a player who rejoins
   sees the correct portals and badges with no effect replayed.

## Done when
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including a test that every world in config has an unlock color, taken
      from the shared palette table.
- [ ] A test asserts the rebirth effect is triggered only by a confirmed
      server event, by driving the handler with a refused response and
      asserting nothing plays.
- [ ] `grep -rn "palette" games/egg-champions/src` shows one palette table,
      shared, not two.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Beating gym 1 shows the badge burst and then the lit portal.
- [ ] A rebirth flashes once, and the main screen afterwards shows the new
      count with worlds relocked.
- [ ] Rejoining after a win shows the portal already open with no replayed
      effect.

## Out of scope
Click and hatch effects (task 15) and battle effects (task 16).

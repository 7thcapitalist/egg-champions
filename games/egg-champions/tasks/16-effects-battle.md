# Task 16: Effects, battle

## Goal
A battle that reads at a glance: who hit whom, how hard, with what, and when
something fainted.

## Build
Read the effects table in `design/eggs-and-effects.md`. This task builds the
type attack burst, attack motion, damage number, faint, and the five special
move visuals. Each one is driven by an event in the list the server sends,
so the visuals can never claim something the rules did not do.

1. Attack motion: the attacker hops forward and back; the target flashes
   white and shakes. One animation, every pet, no rigs, as the spec says.
2. Type attack burst: a particle burst in the move's type color on hit.
   Orange fire, green leaves, yellow sparks, blue droplets. The color table
   is keyed by type id from config, so a fifth type needs one row, not new
   code.
3. Damage number: pops above the target, larger and gold for a strong hit.
   "Strong" means the event carried the `type_bonus_strong` multiplier; read
   it from the event, do not recompute the matchup on the client.
4. Faint: the pet shrinks and fades out, then the next pet comes in.
5. Special moves, one visual per special, matched to the config ids:
   - `guard`: a shield ring that holds until the hit it absorbs.
   - `heal`: rising green crosses.
   - `rush`: speed lines.
   - `drain`: a stream from the target to the user.
   - `smash` and `off_type`: the type burst at greater scale, with
     `off_type` using its own type's color rather than the pet's.
6. Timing: each event plays in sequence from the queue task 13 built. No two
   events overlap. Every duration comes from the budget table in
   `Effects.luau`, and the total for a typical turn is stated in a comment so
   a two minute battle stays a two minute battle.
7. Keep it cheap: short lifetimes, low counts, nothing running when the
   battle screen is closed.

## Done when
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [x] A test asserts every special id in `config/specials.json` has a visual
      registered, and every type id has a burst color, so a new special or
      type fails the suite rather than silently showing nothing.
- [x] A test feeds a recorded battle event list from the task 05 specs
      through the effect dispatcher and asserts no event kind is unhandled.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] A full gym battle is readable without the log: the bursts, numbers and
      faints tell the story.
- [ ] All six specials are visually distinct from each other.
- [ ] Battle stays smooth on a phone-class device.

## Out of scope
Click and hatch effects (task 15) and progression effects (task 17).

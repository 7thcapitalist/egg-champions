# Task 13: UI, gym battle screen

## Goal
The battle the player actually plays: two HP panels, two move buttons, and a
log that explains what happened. The screen renders what the server decided
and decides nothing itself.

## Build
Read `design/ui/README.md` and `design/ui/Battle.dc.html` first. Match the
mockup.

1. `src/client/UI/Battle.luau`, using `Theme.luau`:
   - HP panels for both active pets, each with the pet name, its type marker,
     its HP bar and number, and team markers showing how many pets each side
     has left.
   - The arena between them, with both active pets as the placeholder blocks
     from task 14.
   - The battle log: one readable line per event from the server's event
     list, newest last, scrolled to the bottom.
   - Two move buttons: move 1 is the type's basic attack, move 2 is the pet's
     special with its name from config. Move 2 shows its remaining cooldown
     and is unpressable while cooling down.
   - `Give up` ends the battle.
2. The whole screen is driven by the event list from `BattleMove`. The client
   holds no HP, no cooldown and no turn order of its own: it applies events
   in order and animates them. If the server and the screen ever disagree,
   the server is right and the screen resyncs from the state it sent.
3. Entering a battle: the gym building (task 09) asks to pay `Gym.fee` if
   unpaid, then sends `StartBattle`. The fee prompt shows the fee from config
   and says that attempts are free until the next rebirth.
4. Losing shows the `gym_retry_seconds` wait as a countdown before the gym
   can be entered again. Winning shows the badge and that the next world is
   open.
5. One event at a time: queue the server's events and play them in sequence
   so two hits never overlap. Keep the per-event duration in one constant
   so the whole battle can be sped up later.

## Done when
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including a test that feeds a recorded event list from the task 05
      specs through the log formatter and asserts one readable line per
      event, with no event kind unhandled.
- [x] A test asserts every event kind the battle rules can emit has a log
      line, by comparing against the kinds listed in `Battle.luau`.
- [x] `grep -rn "takeTurn\|Battle.damage" games/egg-champions/src/client`
      finds nothing: the client never resolves a turn.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Side by side with `design/ui/Battle.dc.html`, the HP panels, arena,
      log and buttons match, including the cooldown state.
- [ ] A full gym battle is readable: it is clear who acted, what it did, and
      how much damage it dealt.
- [ ] Beating gym 1 awards the badge and opens world 2.

## Out of scope
Battle particles and motion, which are task 16. This task moves HP bars and
writes log lines.

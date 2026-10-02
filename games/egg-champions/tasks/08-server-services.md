# Task 08: Server services and remotes

## Goal
The server owns every decision that matters. The client sends requests and
gets results. This task is where the rule modules meet real players.

## Build
1. `src/shared/Remotes.luau`: one module naming every remote, so client and
   server cannot disagree about a string. Remotes needed:
   `Click`, `BuyEgg`, `Equip`, `Unequip`, `PayGymFee`, `StartBattle`,
   `BattleMove`, `GiveUp`, `Rebirth`, and a `ProfileChanged` event the server
   fires to push state down.
2. `src/server/Services/` one module per service, each using the task 03 to
   06 rule modules and the task 07 profile. No service recomputes a rule.
   - `ClickService`: on `Click`, add `Coins.perClick(profile)`. Rate limit per
     player to a plausible human maximum read from a module constant, and
     drop anything over it rather than crediting it. The client never sends
     an amount, only that a click happened.
   - `ShopService`: on `BuyEgg`, check the egg is unlocked
     (`Progression.eggUnlocked`) and affordable, charge the price from
     config, roll with `Hatch.roll`, add the pet, record it in the index, and
     return the result. Triple Hatch charges three times and rolls three
     times.
   - `TeamService`: on `Equip` and `Unequip`, apply `Team` and reject with
     the rule module's reason.
   - `GymService`: on `PayGymFee`, charge `Gym.fee` once per rebirth run. On
     `StartBattle`, build the leader team and open a battle session held
     server side. On `BattleMove`, resolve exactly one turn with
     `Battle.takeTurn` and return the event list. On a win, call
     `Progression.beatGym`. On a loss, start the `gym_retry_seconds` wait.
     `GiveUp` ends the session as a loss.
   - `RebirthService`: on `Rebirth`, apply `Rebirth.apply` when affordable.
3. Validation rules that apply to every remote, in one shared helper so none
   is forgotten:
   - Reject a request for a player with no loaded profile.
   - Reject a move for a battle session the player does not own, or a session
     that has ended, or a move index that is not 1 or 2, or a move 2 that is
     on cooldown.
   - Never trust a number from the client. The only client input is a choice:
     which egg, which pet uid, which move.
   - Every rejection is logged with the player and the reason.
4. The battle session lives on the server. The client holds no HP and no
   cooldown of its own; it renders the event list the server sends.
5. `src/server/init.server.luau` starts the services in order and keeps its
   existing config line.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `grep -rn "RemoteEvent\|RemoteFunction" games/egg-champions/src/client`
      finds no remote created on the client: the server creates them all.
- [ ] `grep -rn "OnServerEvent\|OnServerInvoke" games/egg-champions/src`
      matches only files under `src/server`.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.

## Needs human or playtester
- [ ] In the test place: click for coins, buy an egg, hatch, equip, pay a gym
      fee, win a battle, and rebirth, all with no error in the Output.
- [ ] A client that fires `Click` as fast as it can is rate limited rather
      than credited.

## Out of scope
UI, worlds and effects. This task may be tested through the Explorer and the
command bar with no screen at all.

# Task 05: Battle rules and all six specials

## Goal
The whole turn-based battle as a pure function of state and a move choice, so
a battle can be replayed and tested without the engine. This is the largest
rule module; it gets the most tests.

## Build
1. `src/shared/rules/Battle.luau`:
   - `Battle.start(playerTeam, leaderTeam, rebirths, rng)` returns a battle
     state: both teams with current HP, the active index per side, cooldowns,
     and a turn counter.
   - Battle stats scale by rebirths at start:
     `stat x (1 + rebirth_battle_bonus x rebirths)`, applied to the player's
     pets only. Variant battle multipliers apply too.
   - `Battle.damage(attacker, defender, power, moveType, rng)` is the spec
     formula: `Attack x (power / basic_move_power) x TypeBonus x Random`,
     with `TypeBonus` from `type_bonus_strong`, `type_bonus_weak` or 1, and
     `Random` drawn between `damage_random_min` and `damage_random_max`.
     There is no defense stat.
   - `Battle.takeTurn(state, moveChoice)` resolves one full turn and returns
     the new state plus a list of events (see below). Move 1 is the basic
     attack of the pet's type at `basic_move_power`, usable every turn. Move
     2 is the pet's special, then unusable for `special_cooldown_turns`.
   - The faster pet acts first; ties go to the player. `Rush` changes Speed
     for the rest of the battle and so can change who acts first on later
     turns.
   - All six specials, each from its config row, never a literal:
     `smash` attack at its power; `drain` attack that heals the user for
     `value` of the damage dealt; `heal` restores `value` of max HP; `guard`
     multiplies the next hit taken by `value`, then expires; `rush` raises
     own Speed by `value` for the rest of the battle; `off_type` attacks at
     its power using the pet's `special_off_type`.
   - The leader uses its special when ready, otherwise the basic attack. That
     is the whole leader policy.
   - When a pet faints the next one in the team comes in automatically. A
     side with no pets left loses. `Battle.isOver(state)` returns the winner
     or nil.
   - Return an event list per turn (`attack`, `damage`, `heal`, `guard`,
     `rush`, `faint`, `switch`, `win`, `lose`) with the numbers already
     resolved. The client replays these events and computes nothing itself.
2. `src/shared/rules/Gym.luau`:
   - `Gym.leaderTeam(worldId, rebirths)` builds the leader team from
     `tuning/gyms.json`: the stats are already tuned, so read them, do not
     recompute. Leader pets do not get the player's rebirth bonus.
   - `Gym.fee(worldId)` and `Gym.retrySeconds()` from config.
3. `src/shared/rules/specs/Battle.spec.luau` and `Gym.spec.luau`, registered
   in `specs.luau`. Cover at least:
   - The damage formula at a fixed rng against hand-computed numbers.
   - Strong, weak and neutral type matchups, each checked against the config
     multiplier.
   - Every one of the six specials, one test each, asserting its exact
     effect.
   - Cooldown: the special is unusable for exactly
     `special_cooldown_turns` turns, then usable again.
   - Guard expires after absorbing one hit, not two.
   - Drain never heals the user above max HP.
   - Speed ties go to the player, and Rush can flip the order mid-battle.
   - A full battle from start to a winner, seeded, with a stable event list.
   - The reference team in `tuning/gyms.json` beats each gym at its
     `target_rebirths` at roughly the recorded win rate over many seeded
     battles. This is the check that the rules and the tuner agree.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0 with the
      new specs included.
- [x] A test covers each of the six specials by name, and a test asserts the
      specials covered equal the ids in `config/specials.json`, so a new
      special cannot be added without a test.
- [x] The win-rate test agrees with `tuning/gyms.json` within a stated
      tolerance.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Out of scope
Paying the gym fee, the battle session on the server, animation, and the
battle screen. Task 08 wires the server, task 13 the screen, task 16 the
effects.

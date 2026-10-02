# Agent 1: Spec parser

## Job
Turn a game spec into config files the rest of the factory reads. This agent
never invents game design. If the spec is missing something, it reports the
gap and stops.

## Input
`<game-dir>/spec.md`, a game spec in the canonical format below. `<game-dir>` is
the game folder under `games/`.

## Output
`<game-dir>/config/*.json` (constants, rarities, roles, variants, types,
specials, passes, eggs, worlds, pets) and `<game-dir>/config/manifest.json`.
Config files are generated. Never edit them by hand. Change the spec and rerun.

## Steps
1. If the spec is loosely written (numbers in prose, missing tables), rewrite
   it into the canonical format first. Move every fixed number into the
   Constants table. Do not change any design decision while doing this.
2. Run `python factory/tools/parse_spec.py <game-dir>/spec.md <game-dir>/config`.
   A `SPEC ERROR` means the spec's format is wrong. Fix the spec, not the tool.
3. Run `python factory/tools/validate_config.py <game-dir>/config`.
   Each failure is a design gap or contradiction in the spec. Fix it in the
   spec only if the fix is unambiguous. Otherwise list it for the human.
4. Report: counts per file, anything you normalized, and open gaps.

## Done when
Both commands exit with code 0 and no gaps are left unreported.

## Canonical spec format
The parser finds tables by their column names, so section order and prose
are free. These tables are required, with exactly these columns:

| Table | Columns |
| --- | --- |
| Constants | Key, Value, Meaning |
| Rarities | Rarity, Hatch chance, Click Power budget, Battle stat multiplier |
| Roles | Role, Click Power, HP and Attack |
| Variants | Variant, Hatch chance, Click Power, Battle HP and Attack, Look |
| Types | Type, Strong against, Weak against |
| Specials | Special, Kind, Power, Value, Effect |
| Worlds | World, Environment, Eggs (price in coins), Gym fee, Leader team, Counter, Target rebirths |
| Egg stats | Egg, Base Click Power, Base HP, Base Attack |
| Passes | Pass, Effect |
| Roster | Pet, Looks like, Egg, Rarity, Type, Role, Special, Speed |

Cell formats:
- World: `1. Green Meadow`
- Eggs: `Meadow Egg 50, Forest Egg 500`
- Leader team: `3 Grass pets, Rare strength`
- Special edition pet: `Abacatudo (Fruit Edition)`
- Off-type special: `Off-type (Grass)`
- Numbers may use `5,000`, `1.5x`, or `50%`.

## What the validator checks
- Required constants exist.
- Rarity hatch chances add up to 100%.
- The type circle is consistent in both directions.
- Every pet points at a real egg, rarity, role, type, and special, and its
  Speed is inside the allowed range.
- Every egg has one pet of each rarity.
- Egg prices and gym fees only go up, world by world.
- Each gym's counter type beats the leader's type, and a pet of that type can
  be hatched before reaching that gym.

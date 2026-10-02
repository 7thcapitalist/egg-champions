# Egg Champions: Game Spec v1

## Overview

A click simulator where you hatch cute original creatures, use them to earn coins, and battle a gym with them to open each new world. Name on Roblox: Egg Champions: Pet Clicker Simulator.

Pets do two jobs. They multiply your coins per click, and they are your team in turn-based gym battles. A pet that is great at earning can be weak in battle, so players need more than one good pet.

Version one ships 3 worlds, 3 gyms, 6 eggs, 30 pets, 4 types, 5 rarities, rebirths, shiny and golden variants, and a pet index. All characters are original designs. Most are elemental creatures, and 3 of the 30 belong to the Fruit Edition, a special line of fruit characters, one per world, that each have a normal type. Meme characters arrive later as limited event eggs.

## Core loop

1. Click to earn coins.
2. Buy eggs with coins. Each egg hatches one pet.
3. Equip 3 pets. The same 3 pets boost your clicks and form your battle team.
4. Pay the gym fee to unlock the world's gym.
5. Beat the gym leader in a 3 versus 3 battle. Winning opens the next world and gives a badge.
6. Repeat in the next world with stronger eggs and a harder gym.
7. Rebirth to reset coins and gym progress for a permanent bonus to coins and battle strength. Later gyms are tuned around a few rebirths, but a team of rarer pets can win with fewer.

The pet index tracks every pet hatched and pays a small coin bonus per completed egg.

## Constants

Every fixed number in the game lives in this table. The parser reads values from here, never from prose.

| Key | Value | Meaning |
| --- | --- | --- |
| game_name | Egg Champions | Brand name |
| roblox_title | Egg Champions: Pet Clicker Simulator | Title shown on Roblox |
| team_size | 3 | Pets equipped, used for both clicking and battling |
| pets_per_egg | 5 | One pet per rarity in each egg |
| basic_move_power | 40 | Power of move 1 |
| special_cooldown_turns | 2 | Turns before move 2 can be used again |
| type_bonus_strong | 1.5 | Damage multiplier when the move's type is strong against the target |
| type_bonus_weak | 0.67 | Damage multiplier when the move's type is weak against the target |
| damage_random_min | 0.9 | Lower bound of the damage roll |
| damage_random_max | 1.1 | Upper bound of the damage roll |
| gym_retry_seconds | 30 | Wait after losing a gym battle |
| rebirth_first_cost | 2,000,000 | Coins for the first rebirth |
| rebirth_cost_growth | 2x | Each next rebirth costs this many times more |
| rebirth_coin_bonus | 50% | Added to coins per click per rebirth |
| rebirth_battle_bonus | 15% | Added to battle HP and Attack per rebirth |
| index_egg_bonus | 10% | Added to coins per click per completed egg in the pet index |
| speed_min | 8 | Lowest allowed pet Speed |
| speed_max | 14 | Highest allowed pet Speed |
| pacing_first_hatch_minutes | 1 | First hatch should happen within this time |
| pacing_gym1_minutes_min | 20 | Earliest target for beating gym 1 |
| pacing_gym1_minutes_max | 30 | Latest target for beating gym 1 |
| pacing_final_gym_hours_min | 6 | Earliest target for beating the last gym |
| pacing_final_gym_hours_max | 8 | Latest target for beating the last gym |

## Pets

Every pet has fixed stats, one type, one rarity, and two moves. Pets never level up or evolve. The only way to get stronger is to hatch better pets.

| Stat | What it does |
| --- | --- |
| Click Power | Added to your coins per click while equipped |
| HP | Damage the pet can take in battle |
| Attack | Scales the damage of its moves |
| Speed | Decides who moves first each turn |

Rarity sets the stat budget. Click Power scales steeply with rarity, battle stats scale gently, so a smart type pick can beat a rarer team.

| Rarity | Hatch chance | Click Power budget | Battle stat multiplier |
| --- | --- | --- | --- |
| Common | 50% | 1x | 1x |
| Uncommon | 30% | 2x | 1.2x |
| Rare | 15% | 4x | 1.5x |
| Epic | 4.5% | 10x | 2x |
| Legendary | 0.5% | 30x | 3x |

Each pet has a role that shifts its budget.

| Role | Click Power | HP and Attack |
| --- | --- | --- |
| Worker | 1.5x | 0.7x |
| Balanced | 1x | 1x |
| Fighter | 0.5x | 1.3x |

Any hatch can also roll a variant, on top of its rarity. Variants reuse the same model.

| Variant | Hatch chance | Click Power | Battle HP and Attack | Look |
| --- | --- | --- | --- | --- |
| Shiny | 4% | 2x | 1.2x | Brighter colors and sparkle particles |
| Golden | 0.5% | 5x | 1.5x | Gold material and a glow |

The pet index tracks normal, shiny, and golden versions separately.

There are 4 types in one circle. Each type is strong against one and weak against one.

| Type | Strong against | Weak against |
| --- | --- | --- |
| Fire | Grass | Water |
| Grass | Electric | Fire |
| Electric | Water | Grass |
| Water | Fire | Electric |

The Fruit Edition is a collection tag, not a type or a rarity. Fruit pets get their own page in the pet index.

Move 1 is the basic attack of the pet's type, usable every turn. Move 2 is a special with a cooldown, picked from this pool.

| Special | Kind | Power | Value | Effect |
| --- | --- | --- | --- | --- |
| Smash | attack | 80 | 0 | Strong attack of the pet's type |
| Drain | drain | 50 | 0.5 | Attack that heals the user for this fraction of the damage |
| Heal | heal | 0 | 0.3 | Restores this fraction of max HP |
| Guard | guard | 0 | 0.5 | Multiplies the next hit taken by this fraction |
| Rush | speed | 0 | 0.5 | Raises own Speed by this fraction for the rest of the battle |
| Off-type | offtype | 60 | 0 | Attack of a different type, listed per pet |

## Gym battles

A gym battle is a turn-based fight between your equipped pets and the gym leader's team. One pet per side is active at a time.

1. The player pays the gym fee once. After that, attempts are free until the next rebirth.
2. Each turn the player picks one of the active pet's two moves. The leader uses the special when it is ready, otherwise the basic attack.
3. The faster pet acts first. Ties go to the player.
4. When a pet faints, the next one in the team comes in automatically.
5. The side that loses all its pets loses. A loss allows a retry after a short wait.
6. A win awards the badge and opens the next world. Badges are kept forever as achievements.

```latex
damage = Attack \times \frac{Power}{basic\_move\_power} \times TypeBonus \times Random
```

There is no defense stat. A pet has about 5 times its Attack in HP, so a full battle takes about 2 minutes.

Gym strength is a progression gate, not tied to any rarity. Each leader's stats are set by the economy tuner to the power a player must reach to earn the next world. The target assumes a team of Rare pets from that world at the target rebirth count. Rebirths are never a hard requirement: a team with rarer, shiny, or golden pets can win with fewer.

The animation is the same for every pet, with no rigs. The attacker hops forward and back, the target flashes and shakes, a damage number pops up, and the HP bar drops. A fainted pet shrinks and fades. Each type has one particle color.

The server resolves every turn. The client only sends the move choice and plays the animation.

## Worlds, eggs, and gyms

Each world has its own environment, its eggs, and one gym. Every gym leader uses a single type that players can counter with pets already available to them.

| World | Environment | Eggs (price in coins) | Gym fee | Leader team | Counter | Target rebirths |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Green Meadow | Grass fields and forest edge | Meadow Egg 50, Forest Egg 5,000 | 50,000 | 3 Grass pets, Rare strength | Fire | 0 |
| 2. Coral Coast | Beach, reef, and storm clouds | Shell Egg 50,000, Storm Egg 500,000 | 5,000,000 | 3 Water pets, Rare strength | Electric | 2 |
| 3. Ember Volcano | Lava rivers and ash cliffs | Ember Egg 20,000,000, Magma Egg 500,000,000 | 10,000,000,000 | 3 Fire pets, Epic strength | Water | 5 |

Beating the last gym gives the last badge and a "World 4 coming soon" gate.

Worlds are small islands built by code from a kit of about 10 props each: an egg stand per egg, a gym building, a portal, and scenery. Nothing is placed by hand.

## Economy numbers

Prices, gym fees, and rebirth cost were tuned by the economy tuner against the pacing targets in the Constants table. See tuning/report.md.

```latex
coins\ per\ click = (1 + \sum ClickPower) \times (1 + rebirth\_coin\_bonus \times rebirths)
```

```latex
battle\ HP\ and\ Attack = pet\ stat \times (1 + rebirth\_battle\_bonus \times rebirths)
```

Each egg sets the base stats of a Common, Balanced pet. Rarity and role multiply from there.

| Egg | Base Click Power | Base HP | Base Attack |
| --- | --- | --- | --- |
| Meadow | 1 | 50 | 10 |
| Forest | 5 | 75 | 15 |
| Shell | 40 | 125 | 25 |
| Storm | 300 | 200 | 40 |
| Ember | 3,000 | 325 | 65 |
| Magma | 25,000 | 500 | 100 |

Rebirth resets coins and gym progress, so worlds lock again and gyms must be beaten again. Pets and badges stay.

| Pass | Effect |
| --- | --- |
| 2x Coins | Doubles coins per click |
| Auto Click | Clicks automatically |
| Lucky Eggs | Doubles Epic and Legendary odds |
| Triple Hatch | Hatches three eggs at once |

No game pass affects battle stats.

## Pet roster

One pet per rarity in each egg. Names are placeholders to check for conflicts before launch.

| Pet | Looks like | Egg | Rarity | Type | Role | Special | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Leafpup | Leaf puppy | Meadow | Common | Grass | Balanced | Guard | 10 |
| Puddlet | Puddle tadpole | Meadow | Uncommon | Water | Worker | Heal | 9 |
| Emberkit | Ember fox kit | Meadow | Rare | Fire | Fighter | Smash | 12 |
| Abacatudo (Fruit Edition) | Tough bodybuilder with an avocado head and green avocado skin | Meadow | Epic | Grass | Fighter | Guard | 8 |
| Voltibun | Thunder rabbit | Meadow | Legendary | Electric | Balanced | Rush | 14 |
| Zapmoth | Static moth | Forest | Common | Electric | Worker | Rush | 13 |
| Mossnail | Moss snail | Forest | Uncommon | Grass | Balanced | Heal | 8 |
| Sparkit | Spark kitten | Forest | Rare | Electric | Fighter | Smash | 13 |
| Cinderhog | Fire hedgehog | Forest | Epic | Fire | Fighter | Drain | 11 |
| Brookdeer | Stream deer | Forest | Legendary | Water | Balanced | Off-type (Grass) | 12 |
| Bubblecrab | Bubble crab | Shell | Common | Water | Balanced | Guard | 9 |
| Kelpony | Seaweed seahorse | Shell | Uncommon | Grass | Worker | Heal | 10 |
| Zapeel | Electric eel | Shell | Rare | Electric | Fighter | Smash | 13 |
| Pearlotter | Pearl otter | Shell | Epic | Water | Worker | Guard | 11 |
| Tidewhale | Wave whale | Shell | Legendary | Water | Fighter | Drain | 8 |
| Driftgull | Sea breeze gull | Storm | Common | Water | Worker | Rush | 13 |
| Fuzzbolt | Static sheep | Storm | Uncommon | Electric | Balanced | Guard | 10 |
| Bananão (Fruit Edition) | Stylish banana man in sunglasses with yellow banana skin | Storm | Rare | Electric | Fighter | Smash | 12 |
| Reefwyrm | Coral serpent | Storm | Epic | Water | Fighter | Smash | 11 |
| Thundrake | Storm dragon | Storm | Legendary | Electric | Fighter | Off-type (Water) | 13 |
| Coalmole | Coal mole | Ember | Common | Fire | Balanced | Guard | 9 |
| Steamtoad | Steam toad | Ember | Uncommon | Water | Worker | Heal | 9 |
| Moranguete (Fruit Edition) | Beautiful strawberry woman, a flame mage, with red seeded skin | Ember | Rare | Fire | Fighter | Smash | 11 |
| Ashwolf | Ash wolf | Ember | Epic | Fire | Fighter | Rush | 14 |
| Thornback | Cactus tortoise | Ember | Legendary | Grass | Balanced | Drain | 8 |
| Sootbat | Soot bat | Magma | Common | Fire | Worker | Rush | 13 |
| Geyserpup | Geyser otter pup | Magma | Uncommon | Water | Balanced | Guard | 11 |
| Voltscorp | Lightning scorpion | Magma | Rare | Electric | Fighter | Smash | 12 |
| Lavalynx | Lava lynx | Magma | Epic | Fire | Balanced | Drain | 13 |
| Magmaroc | Lava bird | Magma | Legendary | Fire | Fighter | Off-type (Electric) | 12 |

Art direction for the asset line: round chunky bodies, big eyes, flat bright colors, under 2,000 triangles each, and no moving parts.

## Out of scope

- World 4 and beyond
- Limited event eggs with meme-style characters
- Trading between players
- Player versus player battles

# Egg Champions: Game Spec v1

## Overview

A pet training simulator where you hatch original creatures, train together at themed targets to earn coins, and battle gyms to open each new world. The existing Roblox listing title remains unchanged until a separate presentation update.

Pets do two jobs. They multiply your coins per click, and they are your team in turn-based gym battles. A pet that is great at earning can be weak in battle, so players need more than one good pet.

Version one ships 3 worlds, 3 gyms, 6 eggs, 30 pets, 4 types, 5 rarities, rebirths, shiny and golden variants, and a pet index. All characters are original designs. Most are elemental creatures, and 3 of the 30 belong to the Fruit Edition, a special line of fruit characters, one per world, that each have a normal type. Meme characters arrive later as limited event eggs.

## Core loop

1. Walk into a world's training ring. While you stand there, your character and equipped pets train automatically to earn coins. World taps never award currency.
2. Buy eggs with coins. Each egg hatches one pet.
3. Equip 3 pets. The same 3 pets boost training rewards and form your battle team.
4. Pay the gym fee to unlock the world's gym.
5. Beat the gym leader in a 3 versus 3 battle. Winning opens the next world and gives a badge.
6. Repeat in the next world with stronger eggs and a harder gym.
7. Rebirth to reset coins and gym progress for a permanent bonus to coins and battle strength. Later gyms are tuned around a few rebirths, but a team of rarer pets can win with fewer.

The pet index tracks hatched and captured pets. Completed normal egg sets give permanent training bonuses, with extra bonuses for a complete world and the complete normal index.

## Constants

Every fixed number in the game lives in this table. The parser reads values from here, never from prose.

| Key | Value | Meaning |
| --- | --- | --- |
| game_name | Egg Champions | Brand name |
| roblox_title | Egg Champions: Pet Clicker Simulator | Title shown on Roblox |
| team_size | 3 | Pets equipped, used for both clicking and battling |
| pets_per_egg | 5 | One pet per rarity in each egg |
| character_walk_speed | 22 | Comfortable traversal speed in studs per second |
| offline_max_seconds | 7200 | Maximum offline earning time (2 hours) |
| offline_rate_fraction | 25% | Fraction of saved active training rate earned offline |
| training_tick_seconds | 0.25 | Seconds of continuous eligible training before each reward |
| training_hits_per_tick | 4 | Base training hits per reward; four rewards per second makes active income 4x faster |
| training_auto_bonus_hits | 1 | Extra hit per reward for the existing Auto Click pass |
| training_radius | 12 | Horizontal radius in studs of a training ring |
| training_max_vertical | 8 | Maximum vertical separation from the training floor in studs |
| training_hatch_pause_seconds | 0 | Hatching and auto hatch never pause training income |
| legacy_epic_floor | 0 | Retired inventory scaling; Epic power is fixed |
| legacy_legendary_floor | 0 | Retired inventory scaling; Legendary power is fixed |
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
| wild_spawn_seconds | 20 | Continuous training time before a private wild encounter |
| wild_encounter_seconds | 120 | Encounter lifetime including the capture opportunity |
| wild_reward_seconds | 5 | Victory pays this many base active income seconds times monster strength |
| wild_uncommon_strength | 2 | Uncommon wild health and victory reward multiplier |
| wild_rare_strength | 3 | Rare wild health and victory reward multiplier |
| wild_hp | 100 | Wild focus challenge health |
| wild_focus_period | 1.6 | Seconds per timing bar cycle |
| wild_focus_window | 0.16 | Half width of the good timing region as a cycle fraction |
| wild_strike_cooldown | 0.55 | Minimum seconds between server accepted strikes |
| wild_focus_damage | 25 | Damage for striking in the good timing region |
| wild_damage | 5 | Damage outside the timing region |
| wild_max_misses | 3 | Counters before the monster escapes |
| wild_capture_chance | 75% | Basic prism chance for a first-area Common; rarity table overrides it |
| wild_visitor_chance | 8% | Chance to draw a species from an adjacent world |
| wild_prism_drop_chance | 8% | Chance of one prism dropping on a wild victory |
| wild_capture_cap | 90% | Highest possible capture success chance |
| wild_origin_penalty | 35% | Extra capture difficulty per origin world above the first |
| wild_origin_strength | 20% | Extra health and reward strength per origin world above the first |
| wild_second_egg_factor | 1.25 | Extra capture difficulty and strength for the second egg |
| wild_training_bonus | 50% | Temporary active training increase after a wild victory |
| wild_boost_seconds | 60 | Active-only boost duration; refreshes without stacking |
| index_world_bonus | 10% | Extra permanent collection factor per completed world |
| index_full_bonus | 20% | Extra permanent collection factor for the full normal index |
| speed_min | 8 | Lowest allowed pet Speed |
| speed_max | 14 | Highest allowed pet Speed |
| pacing_first_hatch_minutes | 1 | First hatch should happen within this time |
| pacing_gym1_minutes_min | 20 | Earliest target for beating gym 1 |
| pacing_gym1_minutes_max | 30 | Latest target for beating gym 1 |
| pacing_final_gym_hours_min | 6 | Earliest target for beating the last gym |
| pacing_final_gym_hours_max | 8 | Latest target for beating the last gym |

## Pets

Every pet has fixed base stats, one type, one rarity, and two moves. Training Power equals the configured pet power times its own variant multiplier. It never scales with the strongest owned pet, new acquisitions, equipped team or world. Epic and Legendary rarity budgets are fixed too. The former Legacy floor mechanic is retired. Rebirth, collection, pass and temporary wild bonuses change total earnings, never the stored or displayed pet power. Existing pets and saves are preserved; inventory, HUD and Best Coins all use the same fixed values.

| Stat | What it does |
| --- | --- |
| Click Power | Added to your coins per click while equipped |
| HP | Damage the pet can take in battle |
| Attack | Scales the damage of its moves |
| Speed | Decides who moves first each turn |

At the same variant, every Epic beats the following egg's Common and Uncommon
in fixed Training Power, HP and Attack. Every Legendary also beats the following
egg's Epic in those stats. This applies across the whole configured egg order,
including world boundaries; speed and type matchups remain separate tactical
choices. No comparison reads owned inventory. The rarity budgets below are fixed.

Rarity sets the stat budget. Click Power scales steeply with rarity, battle stats scale gently, so a smart type pick can beat a rarer team.

| Rarity | Hatch chance | Click Power budget | Battle stat multiplier |
| --- | --- | --- | --- |
| Common | 50% | 1x | 1x |
| Uncommon | 30% | 2x | 1.2x |
| Rare | 15% | 4x | 1.5x |
| Epic | 4.5% | 80x | 4x |
| Legendary | 0.5% | 1,000x | 10x |

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

| World | Environment | Eggs (price in coins) | Gym fee | Leader team | Counter | Target rebirths | Cohort power |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1. Green Meadow | Grass fields and forest edge | Meadow Egg 50, Forest Egg 5,000 | 50,000 | 3 Grass pets, Rare strength | Fire | 0 | 100% |
| 2. Coral Coast | Beach, reef, and storm clouds | Shell Egg 50,000, Storm Egg 500,000 | 5,000,000 | 3 Water pets, Rare strength | Electric | 2 | 100% |
| 3. Ember Volcano | Lava rivers and ash cliffs | Ember Egg 20,000,000, Magma Egg 500,000,000 | 10,000,000,000 | 3 Fire pets, Epic strength | Water | 5 | 80% |

Cohort power multiplies the tuner's reference-calibrated leader power before
rounding leader HP and Attack. Reference calibration still targets an 80% win
rate at the listed rebirth count; the report must show the adjusted team's
actual reference win rate separately. The final world uses a progression
margin because the ideal reference inventory overstates the simulated cohort's
battle readiness. Both the full-cohort pacing and rebirth targets must still
pass; this margin does not change those targets, prices, pet stats or saves.

Beating the last gym gives the last badge and a "World 4 coming soon" gate.

Worlds are small islands built by code from a kit of about 10 props each: an egg stand per egg, a gym building, a portal, and scenery. Nothing is placed by hand.

## Economy numbers

### Training grounds

Every world has one visible training ring near its arrival, connected by a clear
walkway. Green Meadow uses a wooden practice dummy in a forest clearing; Coral
Coast uses a coral and shell totem on a beach deck; Ember Volcano uses an
obsidian training guardian on a basalt platform. All targets are original props.
There is no destructible HP, target kill reward, or world reward multiplier.

The server checks the loaded profile, living character, world unlock, distance,
height and active gym battle before awarding anything. Entering or
changing a ring starts a new full tick; leaving cancels it. No active-training lag catch-up, client-supplied amounts or synthetic click requests are accepted.
Training works before the first pet, using the formula's base power of 1. The
player punches the target and equipped pets move into a formation, lunge, and
return to following when training stops. Nobody is anchored or loses camera or
movement controls. Rewards, target recoil and bounded impact effects are visible.

One training hit uses the existing coins-per-click formula below. The stored
pet stat remains Click Power for compatibility, displayed as Training Power.
A free player earns training_hits_per_tick hits every training_tick_seconds
while eligible, with no scheduler drift at normal frame rates. Hatching, hatch
reveals and auto hatch continue earning throughout: no reset of a partial tick.
Battles pause for their full duration. Inventory menus can be used while standing
in the ring. Four payments per second retain the previous reward size, giving
four times the prior active income. Offline income remains the configured
fraction of the updated active rate. Prices and pacing targets are unchanged;
the economy report must expose any pacing targets that the faster rate misses.
The economy simulation must read the configured training rate as its main cohort
and state that travel/idle time reduces actual earnings. Saves need no new fields.

### Offline training

Equipped pets continue training while the player is away. The server saves the
team's current training rate, including owned passes and progression bonuses.
On rejoin, award floor(elapsed seconds capped at offline_max_seconds times the
saved active rate times offline_rate_fraction). No equipped pets means no offline
income. Only the last successful save determines the rate; old saves without
metadata receive no retroactive reward. The reward and its consumed timestamp
are committed atomically with the session claim, so retries cannot pay twice.
Future or invalid timestamps and invalid rates award nothing. A normal departure
starts the clock immediately; a crashed server starts after its next expected
autosave to avoid counting the last active minute twice. A compact welcome card
shows the coins already credited; no claim button or client amount is trusted.
Bookkeeping is stored beside the profile, preserving its existing schema.
Active progression forecasts exclude offline income and travel/idle time.

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
| 2x Coins | Doubles coins per training hit |
| Auto Click | Adds one extra training hit per reward while inside a training ring |
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
| BananÃ£o (Fruit Edition) | Stylish banana man in sunglasses with yellow banana skin | Storm | Rare | Electric | Fighter | Smash | 12 |
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

Art direction: original stylized segmented creatures, readable faces, exaggerated elemental silhouettes, broad clean color regions, up to 4,000 triangles per pet and at most eight imported pieces. Animate legs, tails and wings locally. Epic and Legendary creatures have restrained elemental accents that work in both portraits and the world. Maps need distinct landmark silhouettes, open foregrounds and readable paths. Environmental motion and action effects stay bounded and never obscure controls. Use the factory visual quality checklist for review in the actual game.

## Out of scope

- World 4 and beyond
- Limited event eggs with meme-style characters
- Trading between players
- Player versus player battles

## Wild training encounters and collection rewards

While training, an optional private wild monster appears after wild_spawn_seconds
continuous eligible seconds. Each area's rarity distribution is configured below.
Choose an adjacent origin world with wild_visitor_chance, otherwise the training
world. Choose rarity using the training area's weights, then choose uniformly
between that origin world's two species of that rarity. Higher rings have better
rarity odds; rare visitors can include an adjacent locked world's species.
Visitors never unlock worlds. Only the current training ring must be unlocked.

A private focus battle lets players strike in the gold window. Server time
decides cooldowns, counters, health and expiry. Three counters cause escape.
Training, hatching, movement and camera controls continue. Leaving, dying,
changing training worlds or starting a gym cancels the encounter.
Strength is rarity strength times (1 + wild_origin_strength times origin index
minus one), times wild_second_egg_factor for a second-egg species. HP is the
ceiling of wild_hp times strength. Victory pays floor(base active income per
second times wild_reward_seconds times strength), excluding temporary boosts.
It refreshes the nonstacking active-only wild boost and rolls one low-rate
prism drop. Never pay rewards twice or include the boost in offline income.

Prisms are saved consumable inventory. One Basic is granted once on profile
creation or version-5 migration. Earn drops from wild victories, buy Basic
with coins, or buy deterministic packs with Robux. Drop quality depends on the
encounter origin's area. At most one capture attempt follows a victory.
The server consumes one chosen prism before rolling. No stock means no attempt
is consumed. Success adds a normal pet with a fresh UID and updates the index.
Chance = min(wild_capture_cap, rarity capture chance times prism multiplier /
((1 + wild_origin_penalty times (origin index - 1)) times second-egg factor)).
Show this exact chance before spending. No prism guarantees a capture.

Earned and paid balances are separate. Spend earned first; paid prisms are
usable only after PolicyService confirms paid random items are allowed.
Unknown/restricted policy disables Robux pack purchase and paid prism use.
The shop discloses numeric odds for all species for each tier before purchase.
Developer product IDs below belong only to TEST universe 10769019206; paid
sales are disabled in other universes. Product prices shown in game come from
Roblox, never the advisory base price. ProcessReceipt commits the grant and
purchase ID together before acknowledging; retries and rejoin cannot duplicate.
No grants from purchase-finished signals. Temporary profiles never acknowledge
paid receipts. Schema version 6 preserves all prior progress and saves balances
and receipts. Rebirth preserves these fields.

| Prism | Multiplier | Coin price | Starter | Pack | TEST product | Base Robux |
| --- | --- | --- | --- | --- | --- | --- |
| Basic | 1 | 500 | 1 | 10 | 3721209790 | 19 |
| Refined | 3 | 0 | 0 | 5 | 3721210003 | 49 |
| Aurora | 8 | 0 | 0 | 3 | 3721210181 | 99 |

| Wild rarity | Strength | Capture chance |
| --- | --- | --- |
| Common | 1 | 75% |
| Uncommon | 2 | 45% |
| Rare | 3 | 20% |
| Epic | 4 | 5% |
| Legendary | 5 | 1% |

| Wild area | Common | Uncommon | Rare | Epic | Legendary | Basic drop | Refined drop | Aurora drop |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Green Meadow | 65% | 25% | 9% | 0.9% | 0.1% | 95% | 5% | 0% |
| Coral Coast | 50% | 30% | 17% | 2.7% | 0.3% | 70% | 28% | 2% |
| Ember Volcano | 35% | 35% | 24% | 5% | 1% | 40% | 50% | 10% |

Existing egg bonuses remain. Every fully completed normal world index adds
index_world_bonus; completing the whole normal index adds index_full_bonus.
Multiply the existing egg factor by (1 + world bonus total + full bonus). These
are recomputed from the saved index, survive rebirth and require no claim or
save schema migration. Collection UI shows total bonus and celebrates actual
completion transitions, not initial profile loading.

The optional BOOSTS callout highlights the game pass shop during training after
a first pet. It never opens a Roblox payment prompt automatically. Only show
unowned configured passes; let the player dismiss it for the session. Show the
actual Roblox price when available and disable buying until price/ownership is
known. Do not label unavailable prices as free or use urgency/countdowns.

Visual plan: reuse biome training clearings without adding collision or changing
arrival sightlines. Use existing pet assets in a focus card, with anticipation,
strike/recoil and recovery, a bounded cyan prism throw/shrink and a result label.
Retain 44px touch targets, reserve joystick and jump regions, and hide the card
behind menus and hatch reveals. Animate the shop callout briefly on appearance,
without continuous screen flashing. A complete world grants a visible permanent
bonus; duplicates keep ordinary inventory value. In-engine mobile, art contact
sheets and reduced-motion review remain required before visual approval.

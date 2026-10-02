# Egg Champions: eggs and effects

Requested by the owner on 2026-10-02. Eggs are 3D models made by the asset
stage. Effects are built in code by the coder (particles, tweens, highlights),
not generated meshes.

## Eggs (asset stage)
One model per egg, about 4 studs tall, 3,000 triangles, a single clean mesh.
Each egg should be recognizable by silhouette and color from a distance.

| Egg | World | Look |
| --- | --- | --- |
| Meadow | Green Meadow | Pale green egg with darker grass-blade markings rising from the base and a small sprout on top |
| Forest | Green Meadow | Deep green egg wrapped in bark and vines, with patches of moss and one small mushroom |
| Shell | Coral Coast | Sandy cream egg with a spiral seashell ridge and a ring of small barnacles |
| Storm | Coral Coast | Dark blue-grey egg with raised yellow lightning cracks and a swirl of cloud at the top |
| Ember | Ember Volcano | Black rock egg with glowing orange cracks and a ring of small embers at the base |
| Magma | Ember Volcano | Dark red egg with flowing lava veins, obsidian plates, and a crown of flame |

## Effects (build stage, in code)
| Effect | Where | What it does |
| --- | --- | --- |
| Click pop | Main screen | The coin amount pops up at the click position, rises, and fades. A small coin burst on the world |
| Hatch sequence | Egg shop | The egg shakes three times, cracks with a flash in the rarity color, and the pet appears with its name and rarity. Longer and brighter for Epic and Legendary |
| Rarity reveal | Hatch | Colored light rays behind the pet: grey, green, blue, purple, orange |
| Shiny | Any pet | Brighter colors and sparkle particles around the pet |
| Golden | Any pet | Gold material and a soft glow |
| Type attack burst | Battle | Particle burst in the type color on hit: orange fire, green leaves, yellow sparks, blue droplets |
| Attack motion | Battle | The attacker hops forward and back; the target flashes white and shakes |
| Damage number | Battle | The number pops above the target, larger and gold for a strong hit |
| Faint | Battle | The pet shrinks and fades out |
| Special moves | Battle | Guard shows a shield ring, Heal shows rising green crosses, Rush shows speed lines, Drain shows a stream from target to user |
| Elemental idle | Pets with fire, sparks, or water | A small looping emitter on the feature, for example the flame on Emberkit's tail |
| Gym win | Battle end | Badge appears with a burst, then the portal to the next world lights up |
| Rebirth | Rebirth | Screen flash and a rising ring around the player |
| World unlock | Worlds | The portal activates with a swirl in the new world's color |

All effects must be cheap enough for phones: short lifetimes, low particle
counts, nothing that runs when off screen.

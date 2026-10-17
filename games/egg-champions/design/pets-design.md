# Egg Champions: pet design sheet

Visual direction updated by the owner on 2026-10-16: keep the original pet
concepts and use Steal An Egg as a reference for faceted Roblox collector art.
Reference: https://www.roblox.com/games/107778070777162/Steal-An-Egg

## Style rules
- Original elemental animal silhouettes with broad heads and expressive eyes.
- Low-poly beveled volumes, saturated flat colors, clean readable faces.
- The defining elemental feature is modeled: leaf ears, flame tails, water
  fins, lightning horns. Preserve the species and concept in the roster below.
- Quadrupeds stand on four legs; tadpoles keep their two front legs.
- Around 4,000 triangles per pet, with automatically segmented movable limbs,
  tails and wings. Use procedural local poses, without external animation IDs.
- Common pets are simple; Legendary pets have larger distinctive silhouettes.
- Fruit Edition preserves the avocado strongman, banana man and strawberry mage.
- All models are original assets; no extracted meshes or textures from the reference.

## Generation and integration
- Generate asynchronously, at most two jobs at once. Record permanent mesh and
  texture IDs plus each segment's size and local CFrame in the manifest.
- Zero the model rotation and verify visually that its face points toward -Z.
- Inspect the assembled model before replacing its prior approved asset.
- Use automatic segmentation unless the user explicitly specifies a schema.
- Remove authoring displays from the publishing DataModel after recording assets.

## World 1: Green Meadow
| Pet | Egg | Rarity | Type | Look | Model |
| --- | --- | --- | --- | --- | --- |
| Leafpup | Meadow | Common | Grass | Young wolf with blade-shaped leaf ears, a mane of layered leaves, and one large leaf as a tail. Braced on four legs. | Leafpup_pick |
| Puddlet | Meadow | Uncommon | Water | Stocky blue tadpole monster with two short front legs, a wide finned tail, and a ring of water droplets around its neck. | |
| Emberkit | Meadow | Rare | Fire | Lean fox with sharp ears, ember markings, dark clawed paws, and a real flame burning at the tail tip. | Emberkit_pick |
| Abacatudo (Fruit Edition) | Meadow | Epic | Grass | Green avocado strongman, 8 studs tall, flexing both arms, tough smirk, dark shorts. | Abacatudo_S2 |
| Voltibun | Meadow | Legendary | Electric | Large yellow hare with very long ears shaped like lightning bolts, crackling sparks along its back, and powerful hind legs. Crouched to leap. | |
| Zapmoth | Forest | Common | Electric | Moth with wide yellow and black wings, feathery antennae that spark at the tips, and a fuzzy body. Wings spread, hovering. | |
| Mossnail | Forest | Uncommon | Grass | Snail with a heavy spiral shell covered in moss and small mushrooms, a thick green body, and two eye stalks. | |
| Sparkit | Forest | Rare | Electric | Wiry yellow wildcat with black lightning stripes, spiked fur along the spine, and a tail that forks into a lightning bolt. Low stalking stance. | |
| Cinderhog | Forest | Epic | Fire | Hedgehog monster whose back spines are burning coals with small flames, dark soot-colored body, and glowing orange eyes. Braced on four legs. | |
| Brookdeer | Forest | Legendary | Water | Tall stag with antlers made of flowing water, a blue and white coat, and a stream of water trailing from its hooves. Standing proud, head high. | |

## World 2: Coral Coast
| Pet | Egg | Rarity | Type | Look | Model |
| --- | --- | --- | --- | --- | --- |
| Bubblecrab | Shell | Common | Water | Blue crab with one oversized claw, a rounded shell, and a cluster of bubbles on its back. Claws raised. | |
| Kelpony | Shell | Uncommon | Grass | Seahorse with a green body, a long mane and tail made of kelp fronds, and a curled tail. Upright, hovering. | |
| Zapeel | Shell | Rare | Electric | Long dark blue eel with glowing yellow stripes along its sides, a wide jaw with small fangs, and sparks at the tail. Coiled, head raised to strike. | |
| Pearlotter | Shell | Epic | Water | Sleek otter with cream and teal fur, a necklace of large pearls, and a glowing pearl held in its front paws. Standing on hind legs. | |
| Tidewhale | Shell | Legendary | Water | Massive deep blue whale monster with a wave-shaped crest on its head, barnacle armor on its back, and wide fins. Rearing up out of a splash. | |
| Driftgull | Storm | Common | Water | Grey and white seabird with a sharp beak, wind-swept feathers, and wingtips that end in spray. Wings spread, gliding. | |
| Fuzzbolt | Storm | Uncommon | Electric | Ram with thick wool standing on end from static, curled yellow horns, and small sparks jumping across its fleece. Head lowered to charge. | |
| Bananão (Fruit Edition) | Storm | Rare | Electric | Tall slim banana man with yellow skin, sunglasses, a light suit, and a lightning bolt on his shirt. | Bananao_pick |
| Reefwyrm | Storm | Epic | Water | Sea serpent with scales like colored coral, a frilled fin collar, and coral spikes along its back. Coiled with head raised. | |
| Thundrake | Storm | Legendary | Electric | Storm dragon with dark grey scales, wings like thunderclouds, glowing yellow eyes, and lightning running along its horns and tail. On four legs, wings half open. | |

## World 3: Ember Volcano
| Pet | Egg | Rarity | Type | Look | Model |
| --- | --- | --- | --- | --- | --- |
| Coalmole | Ember | Common | Fire | Stout mole with black coal-like skin, large digging claws, and cracks in its back that glow orange. On four legs. | |
| Steamtoad | Ember | Uncommon | Water | Wide grey-blue toad with vents on its back releasing jets of steam, heavy brows, and a broad mouth. Squatting, ready to jump. | |
| Moranguete (Fruit Edition) | Ember | Rare | Fire | Strawberry flame mage: a woman with a strawberry head, leaf hair, red skin, a red and black robe with flame patterns, and a fireball in her hand. | Moranguete_R4_repaint_newface (texture not yet permanent) |
| Ashwolf | Ember | Epic | Fire | Large grey wolf with a mane of drifting ash and embers, glowing orange eyes, and smoldering paws. Low stalking stance, teeth showing. | |
| Thornback | Ember | Legendary | Grass | Giant tortoise with a shell like desert rock covered in tall cactus spines and one red cactus flower, thick scaled legs. Standing firm on four legs. | |
| Sootbat | Magma | Common | Fire | Black bat with ragged wings edged in glowing embers, large pointed ears, and small fangs. Wings spread, hovering. | |
| Geyserpup | Magma | Uncommon | Water | Young otter monster with slick dark blue fur and a small geyser of water spouting from a vent on its back. On four legs, alert. | |
| Voltscorp | Magma | Rare | Electric | Scorpion with black armored plates, yellow glowing joints, raised pincers, and a tail stinger shaped like a lightning bolt. | |
| Lavalynx | Magma | Epic | Fire | Muscular lynx with dark rock-like fur split by glowing lava cracks, tufted ears tipped with flame, and molten paws. Crouched to pounce. | |
| Magmaroc | Magma | Legendary | Fire | Huge bird of prey with wings of flowing lava and black rock feathers, a crest of flame, and talons that glow white-hot. Wings spread wide. | |

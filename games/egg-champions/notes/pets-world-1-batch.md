# Pets, World 1 batch (2026-10-02)

EGG CHAMPIONS, WORLD 1 PET PILOT BATCH

All seven pets have a kept model, but only three pass outright; four are usable with flaws and none failed outright. All work was additive, in "Egg Champions Test" (placeId 101737317546942, studio id 62c5babd-2611-4a18-8be0-b683993a3436), inside the new Workspace folder `Pets_World1`. Nothing existing was changed, and the place was not saved or published. Screenshots worked normally, so every verdict is visually verified.

## Manifest (best attempt per pet)

| Pet | Best | Verdict | Height | Bounding size (x, y, z) | Triangles | Mesh asset id | Texture asset id | Published asset id | Flaws |
|---|---|---|---|---|---|---|---|---|---|
| Puddlet | Puddlet_2 | usable with flaws | 4.0 | 3.20 x 4.00 x 5.18 | 5812 | 97362739098055 | 78869701978561 | 99555815318592 | No water droplet ring. Face is friendly rather than fierce. Height is measured to the raised tail tip, so the body is only about 2 studs tall. |
| Voltibun | Voltibun_3 | usable with flaws | 6.0 | 4.34 x 6.00 x 4.95 | 5740 | 82220365452549 | 103615852726557 | 105796472827415 | Lightning-bolt ears and quadruped crouch are right. Body is plump and pale yellow, eyes are plain dots, spine spikes are black fins instead of sparks. Does not read as Legendary. |
| Zapmoth | Zapmoth_1 | pass | 4.0 | 4.63 x 4.00 x 0.87 | 5570 | 138035237314725 | 104790447521164 | 138437766305989 | Antennae are bolt-tipped stalks, not feathery. Wings are vertical like a pinned specimen. Yellow is pale. |
| Mossnail | Mossnail_2 | pass | 4.0 | 3.04 x 4.00 x 4.30 | 5970 | 86261195839042 | 93713682169389 | 139839350505199 | Shell is a round dome with one stripe, the spiral is weak. Mushrooms account for about a third of the height. |
| Sparkit | Sparkit_2 | pass | 4.5 | 2.57 x 4.50 x 5.75 | 5766 | 129085619828782 | 133529017905068 | 137775978925986 | Tail ends in a spear tip, not a forked bolt. Color is orange-yellow. |
| Cinderhog | Cinderhog_1 | usable with flaws | 5.0 | 4.33 x 5.00 x 5.37 | 5978 | 95352394279780 | 110855870374565 | 78501467181801 | Body is light gray, not soot-dark. Flames are few and salmon-colored, not bright orange. Coals are blocky chunks rather than spines. |
| Brookdeer | Brookdeer_1 | usable with flaws | 6.5 | 2.39 x 6.50 x 4.39 | 5650 | 77380287345600 | 94438306868801 | 85487034372575 | Antlers read as solid light-blue antlers, not flowing water. Hoof splashes are present but there is no trailing stream. Head is turned slightly to the side. |

Every model is a Model containing one MeshPart (`body_geom`). Mesh and texture ids are the MeshPart's `MeshId` and `TextureID` (`rbxassetid://<id>`).

## All attempts (row at z = 420, y bottom = 0, anchored, rotation zeroed)

| x | Name | Result | Triangles | Mesh id | Texture id | generationId |
|---|---|---|---|---|---|---|
| 0 | Puddlet_1 | fail: upright biped with four limbs; has droplet collar and scowl | 5932 | 71328908144353 | 89477736540544 | fa90c490-47dd-42c0-a6fb-1200a467452e |
| 14 | Zapmoth_1 | BEST | 5570 | 138035237314725 | 104790447521164 | 4b8102a2-071e-4f0a-ad8c-418af56e69aa |
| 28 | Voltibun_1 | fail: realistic hare, normal ears, faces about 45 degrees off; best stance and attitude of the three | 5966 | 100825574092993 | 78665436153449 | d270424b-930e-4477-8f3f-3069cc6eba18 |
| 42 | Mossnail_1 | usable: teal body, cute eyes, mushrooms barely visible | 5986 | 71631742671932 | 114228897598166 | 0f8a77f7-e751-40c3-b55c-55b89f49ed38 |
| 56 | Cinderhog_1 | BEST | 5978 | 95352394279780 | 110855870374565 | 6422e2ad-ce7d-4dc4-9ab7-15c14f4e60d6 |
| 70 | Puddlet_2 | BEST | 5812 | 97362739098055 | 78869701978561 | 74d54cda-c59d-42c9-b69a-ff714b269fab |
| 84 | Brookdeer_1 | BEST | 5650 | 77380287345600 | 94438306868801 | 128b6ef5-47ae-49d7-9980-9a27e9e2234b |
| 98 | Sparkit_1 | fail: cute house cat, standing upright on four legs, big round eyes | 5748 | 140650123276950 | 139856967667764 | 9414e9d1-24af-4747-a77d-4f455b204423 |
| 112 | Voltibun_2 | fail: bipedal crouch, normal ears | 5866 | 97641049189553 | 136545599853697 | b34027cf-a6c8-4918-9bd3-b77ce7d6e598 |
| 126 | Mossnail_2 | BEST | 5970 | 86261195839042 | 93713682169389 | 8b5f705f-135a-4154-881d-582eba1d5815 |
| 140 | Sparkit_2 | BEST (strongest model of the batch) | 5766 | 129085619828782 | 133529017905068 | 0e294662-7aa6-4481-8859-4d49b57e4952 |
| 154 | Cinderhog_2 | usable: best hedgehog shape and darkest body, but almost no fire, pink eyes | 5984 | 99544391766109 | 111586732385517 | 7ee33178-93a9-40dd-b63c-23c34eede4dc |
| 168 | Voltibun_3 | BEST | 5740 | 82220365452549 | 103615852726557 | 6b89104b-88f5-4550-a5e8-a50f2dc7ce40 |
| 182 | Puddlet_3 | fail: upright round blob; has the bubble necklace | 5954 | 93511400187979 | 121909993604529 | 09c7540f-30c8-431d-8fe0-2be7e0a65ba5 |
| 196 | Brookdeer_2 | usable: antlers became curled tubes, no hoof water, faces about 45 degrees off | 5844 | 104783532155990 | 89108907860550 | c6d67db9-aabe-49a9-9a74-c2f0281ffdd2 |
| 210 | Cinderhog_3 | usable: glowing coals are good, but the face is a boar with a tusk | 5978 | 85637278058601 | 115704318441076 | dff2bd2d-233e-4244-86cb-da11e14f7b9f |

Row order is completion order, not pet order: slot x = 14 x (number of models already in the folder).

## Final prompt of each best attempt

All used maxTriangles 6000, segmentation "none", async true.

**Puddlet_2** (size 4 x 3 x 7)
```
Puddlet 2, a giant blue tadpole battle monster shaped like a mudskipper. Horizontal body lying low along the ground, never upright, no arms, no hind legs. Only two short stubby front legs under the chest. The rear tapers into a long wide tail with a tall fin. A ring of separate round 3D water droplets circles its neck. Narrow sharp glaring eyes, wide scowling mouth. Deep blue skin, pale belly. Stylized game monster, bold colors. Not cute, not a plush toy, not humanoid.
```

**Voltibun_3** (size 4 x 6 x 8)
```
Voltibun 3, a large electric hare battle monster, quadruped, horizontal body crouched to leap, front paws on the ground, never upright, not humanoid. Huge muscular hind legs. Instead of ears it has two giant yellow lightning bolts on its head: tall flat zigzag bolt shapes with three sharp bends each. A row of jagged lightning bolt spikes along its spine. Lean body, small head, narrow fierce eyes. Saturated yellow, black bolt tips. Stylized game monster. Not cute, not a plush toy.
```

**Zapmoth_1** (size 8 x 4 x 5)
```
Zapmoth 1, a moth battle monster. Four wide wings spread flat to the sides, hovering, yellow with bold black jagged bands. Slim fuzzy yellow body. Two large feathery antennae, each tip ending in a small jagged 3D spark of electricity. Small head, sharp angular glaring eyes. Stylized game monster, clean shapes, bold colors. Not cute, not chibi, not a plush toy, not humanoid.
```

**Mossnail_2** (size 4 x 4 x 6)
```
Mossnail 2, a snail battle monster. Huge heavy spiral shell overgrown with thick shaggy green moss, with five big red-capped 3D mushrooms sprouting from the top of the shell. Thick muscular forest green slug body, head raised and braced. Exactly two tall eye stalks, small eyes with heavy angry brows and a hard stern glare, mouth set in a frown. Small head, massive shell. Stylized game monster, clean shapes, bold colors. Not cute, not chibi, not a plush toy, no smile.
```

**Sparkit_2** (size 4 x 4 x 9)
```
Sparkit 2, a fierce electric lynx battle monster, not a house cat. Quadruped prowling in a low stalking crouch, belly near the ground, head lowered below the shoulders, one front paw forward. Wiry lean body, bright yellow fur covered in many bold black zigzag lightning stripes. Tall jagged spikes of fur along the whole spine. Long tail ending in a large forked zigzag lightning bolt. Small head, narrow slit eyes, snarling mouth with bared fangs. Stylized game monster, bold colors. Not cute, not a plush toy.
```

**Cinderhog_1** (size 5 x 5 x 6)
```
Cinderhog 1, a hedgehog battle monster, quadruped braced on four short strong legs, horizontal body, never upright, not humanoid. Its back is covered in large spines made of black burning coals with glowing orange cracks, and small separate tongues of real flame rise from the spine tips. Dark soot-gray body, pointed snout, small head, glowing orange eyes with a fierce glare, legs planted wide. Stylized game monster, clean shapes, bold colors. Not cute, not chibi, not a plush toy, no armor, no clothes.
```

**Brookdeer_1** (size 4 x 6.5 x 6)
```
Brookdeer 1, a tall majestic stag battle monster, quadruped on four long legs, not humanoid. Standing proud, head held high. Large branching antlers made of flowing blue water, curling streams and splashes instead of bone. Blue and white coat, white chest. Swirls of splashing water wrap around each hoof and trail behind. Lean body, small head, sharp commanding eyes. Stylized game monster, clean shapes, bold colors. Not cute, not chibi, not a plush toy, no armor.
```

## Usage, time, and limits

- **Generations:** 27 `generate_mesh` calls, 16 completed (the 16 models above), 11 failed.
- **Time:** about 16 minutes wall clock from the first launch to the final wide screenshot. A successful generation took roughly 60 to 90 seconds.
- **Character limit (7 failures):** the job fails with "Mesh generation failed with error: Character limit exceeded". A 506-character prompt passed and a 514-character one failed, so the limit is probably 512. The failure arrives quickly and produces no model.
- **Rate limit (4 failures):** the job fails with "Failed to publish assets with error: Operation failed: Too Many Requests". It hit when 3 or more jobs were launched or overlapping within about a minute, and once with only 2 running. It surfaces at the end of the job, after the full generation time, and leaves no model. Resubmitting the same prompt worked every time, though Sparkit 1 needed three submissions.
- **Tool timeout (1):** `wait_job_finished` returned "Device did not respond within 60s" once while the job was still running. Calling it again with timeout 50 returned the result.
- **Studio:** it never dropped from the list. No classifier rejections.

## Procedure notes for the asset agent

- **Result payload:** the job result returns `generationId`, `generationName` (the full prompt) and `publishedAssetId`. The model lands at the workspace root named with the full prompt, so matching on the prefix "<Name> <attempt>," found every model.
- **Placement, per model:**
  1. Parent to `Pets_World1` and rename.
  2. Anchor all BaseParts.
  3. `PivotTo(CFrame.new(pivot.Position))` to zero rotation.
  4. `GetBoundingBox`, then `ScaleTo(GetScale() * targetHeight / size.Y)`.
  5. `GetBoundingBox` again and shift so the box center is at (slot x 14, size.Y / 2, 420). The baseplate top is y = 0.
- **Triangle count:** `#AssetService:CreateEditableMeshAsync(meshPart.MeshContent):GetFaces()` worked in the Edit datamodel. All results were 5570 to 5986 against the 6000 cap.
- **Size parameter:** the generator fits the box mainly on Y. Raw output height matched the requested y almost exactly, while x and z came out well under the box.
- **Facing:** with rotation zeroed, the front faces -Z, so the camera goes at z < 420. This is not exact: Voltibun_1 and Brookdeer_2 came out about 45 degrees off, and I did not correct their yaw.
- **Screenshots:** front view from (x, 3 to 4, 408 to 410) looking at the model center; three-quarter from (x + 10, 4 to 5, 413). `screen_capture` rendered correctly every time.

## Rule changes I would make

1. **Hard cap prompts at 500 characters** and count them in code before submitting. The current style rules plus lessons do not fit if pasted in full, so each prompt has to be budgeted.
2. **Limit concurrency to 2 jobs**, with the next pair launched only after the previous pair finishes. Treat "Too Many Requests" as retry-the-same-prompt, up to 3 times.
3. **Order the prompt by priority:** name and attempt, then body plan and stance, then signature features, then face, then colors, then a short negative list. When trimming, cut "clean shapes, defined details", "no armor, no clothes" and "not chibi" first.
4. **Anchor unusual body plans to a real animal with that silhouette.** "Tadpole with two front legs" gave an upright biped; "shaped like a mudskipper" fixed it. "Wildcat" gave a house cat; "lynx, not a house cat" fixed it.
5. **Replace the generic quadruped line with concrete pose geometry.** "Belly near the ground, head lowered below the shoulders, one front paw forward" produced the best stance. "Quadruped, never upright" alone still gave an upright hare and a standing cat.
6. **For a shape-swapped body part, say "instead of X it has Y".** "Ears shaped like lightning bolts" failed twice; "instead of ears it has two giant yellow lightning bolts on its head" worked the first time.
7. **Budget one hard feature per prompt.** Every time a prompt pushed one feature hard, another degraded (Puddlet 3 gained the necklace and lost the tadpole body; Voltibun 3 gained the ears and lost the lean, fierce look). Small floating accessories such as the droplet ring are better added as a separate attached mesh.
8. **Describe the face with brows, eye shape and mouth**, not just "glaring". "Heavy angry brows, narrow slit eyes, snarling mouth with bared fangs" worked; "sharp glaring eyes" often gave round friendly eyes.
9. **Do not write "stylized cartoon, not realistic".** It pushed Voltibun 2 toward a mascot look. "Stylized game monster, bold colors" is enough.
10. **Water and fire come out as opaque solid shapes.** Ask for many large, saturated flame or splash shapes and name the color, and do not expect translucency. Dark body colors come out mid-gray, so ask for "jet black".
11. **Flyers generate in an upright, wings-vertical pose** regardless of a wide flat box. Either accept it or rotate after generation; "wings spread flat, hovering" did not change it.
12. **Add a yaw check after zeroing rotation.** Zero rotation does not guarantee a common facing, so the agent should confirm facing from the front screenshot and apply a yaw correction where needed.
13. **Rarity needs explicit feature counts.** "Legendary, larger" did nothing beyond the scale I applied; name a second and third elemental feature and its size.

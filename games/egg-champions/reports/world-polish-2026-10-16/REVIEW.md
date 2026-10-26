# World, pet value and onboarding review

Date: 2026-10-16 local, verification completed 2026-10-17 UTC.
Environment: Roblox Studio, temporary profile for user 11750959877. No production write.

## Delivered

- Rounded island silhouettes and open coastlines; ancient tree and windmill in Meadow, lighthouse and working harbor layout in Coast, sloping caldera and forge in Volcano. Access routes stay clear.
- Local windmill rotation, wave motion, proximity-limited ambient particles, elemental rare-pet motes, visible effect textures, first-equip and badge celebrations.
- Three original generated hero replacements: Tidewhale, Thundrake, Magmaroc. Front direction -Z, verified in engine; separate flippers/tail, limbs/tail, and wings/legs respectively. Nine normal/shiny/golden appearances inspected. Thundrake's wings are part of its head mesh and do not flap independently.
- Character speed 22; smoother follower gait/turns and individual idle phase.
- Epic coin floor 65%, Legendary 85% of the strongest raw owned pet, applied once. Battle stats unchanged. Equip Best, server clicks and UI share this rule. Ownership and variants survive without schema migration.
- Badge Journey explains permanent badges, current-run gym access, counters, next world, collection/rebirth bonuses and Legacy Power.
- Tutorial has reachable OPEN EGGS/OPEN PETS actions, an unobstructed egg-shop guide row, visible first-equip celebration and next goal. Portrait inventory stacks grid above detail instead of squeezing both side by side.

## Executed evidence

- 859 Luau tests, zero failures; six runner self-tests. Selene zero errors/warnings; StyLua check; binary and XML Rojo builds.
- 13 factory Python tests. Gates spec_parsed, economy_tuned, planned and assets passed. The economy gate checks time targets, not rebirth targets.
- All 36 model entries loaded via Roblox; each mesh and texture verified. Bare texture URI checks in Edit gave false failures; verification through actual textured MeshParts succeeded. Runtime ModelLibrary: 36/36, zero placeholders.
- Actual desktop UI: OPEN EGGS -> HATCH acquired Puddlet UID 5b3276db-5010-48b9-ae17-52391903b884 for 50 -> reveal closed shop -> OPEN PETS -> EQUIP. Tutorial advanced 2 -> 3 -> 4; coins/click 2 -> 8; next goal Hatch 2 more pets. Milestone toast and burst observed (equip-milestone.jpg).
- Final portrait layout checks at 320x639 and 390x763 safe viewports, derived from 320x720 and 390x844 emulated devices. Inventory, EQUIP, tabs, action toolbar, egg guidance, Journey and scrolling inspected. Screens were opened directly for layout review because MCP mouse targeting was inconsistent in portrait emulation. This is not physical-device touch validation.
- Final portrait profile acquired Leafpup UID 6599e861-c8a7-4ebd-824e-426cd228fdc3 through the normal BuyEgg remote; no seeded inventory or currency. Profile is temporary and not saved.
- Movement test: Humanoid speed 22, 17.197 studs traveled toward an 18-stud destination. Windmill pivot changed over 0.3 seconds. World part counts: Meadow 464, Coast 416, Volcano 312, below 1500 each. Counts are not a frame-time benchmark.
- Map screenshots use overview cameras and the matching biome lighting in a temporary play session. Hero contact sheet is a temporary client-only visual fixture. Neither is in the shipping Edit DataModel.
- Studio output includes expected API-access 403 and Roblox CorePackages warnings. Two inspection commands failed while probing an uninitialized module cache and an invalid normal variant string; those were QA-command errors, corrected before evidence capture, not game startup errors.

## Pacing and remaining launch validation

Simulation of 300 players: first hatch 16 s, first gym 25.7 min, final gym 7.70 h. Final gym median is 7 rebirths versus the unchanged design target of 5. This deviation remains open; the target was not silently relaxed. The legacy collection benefit preserves time targets but does not prove a full human playthrough.

Published save/rejoin evidence from the previous cycle confirms the user's equipped team and world access only. This update has no new published-client comparison of exact balance, all UIDs, index, gym fees or rebirth state. Studio API access remains disabled. Existing pass entitlements work, but TEST's configured passes belong to the production universe, so a new purchase in TEST is still unvalidated. No Robux spent.

Composition and locomotion still deserve another art pass: low-poly vegetation/shore details, distinct traversable loops and more species-specific movement. This TEST delivery is not a claim that every visual category meets the new factory's final-release standard. PvP and additional worlds remain follow-on specifications, not implemented features.

Reference research and reusable production requirements are in factory/VISUAL-QUALITY.md. Research used current Roblox Charts and official pages/promotional art, not a claim of live competitor playtesting.

## Publication verification

Studio Output confirmed TEST v84 at 2026-10-16 23:56:12 local. After restarting Studio to resolve stale home rendering, reopened the cloud TEST: universe 10769019206, place 101737317546942, PlaceVersion 84. All 137 source hashes match the shipping build; no missing or additional scripts, no fixture attributes. See cloud-reopened.json and publish-output.txt.

The reusable visual check correctly rejects final-release approval for composition and animation scores of 3.5/5. This does not override the user's requested TEST publication.

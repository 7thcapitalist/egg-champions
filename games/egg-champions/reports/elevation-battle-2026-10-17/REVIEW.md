# Elevation and responsive battle review

Reviewed 2026-10-17 in Studio. Publication confirmation is recorded separately.

## Changes observed

- Two scenic destinations per biome now sit on layered raised ground, with continuous ramps from the existing paths. Meadow has a raised pergola and spring; Coast has a pavilion and tidal coral terrace; Volcano has a crystal garden and mineral pool. Scenery and the builder share footprint and access geometry.
- All six ramps were traversed up and down through character navigation. Each target was reached within one stud; the character returned to ground height. See runtime-qa.json. The first spring approach capture was blocked by the nearby arch and was replaced with a camera at the ramp entrance.
- Actual generated parts: Meadow 573, Coast 508, Volcano 388, below the 1500-per-world budget. No physical-device FPS claim.
- Battle now uses effective pixel dimensions. HP panels, move controls and creatures adapt to the viewport. Transparent creature stages replace square portrait cards. Player portraits measured 200x200 at desktop 958x540, 179x179 at 390x844, 144x144 at 320x720 and 63x63 at extremely short 720x239.333. Short screens prioritize 44-pixel controls; they still have visibly small creatures.
- A real gym UI flow paid the fee, started combat, selected Water Strike, then Drain. Turn 3 showed a healed Tidewhale and the opponent's replacement Abacatudo. The temporary hero team existed only during Play on the confirmed offline Studio profile.
- During the first turn, resolution changed from portrait to desktop. A 692-frame recorder measured recoil, pitch, breach and exact model recovery; effect anchors settled at the new layout and scale returned to one. Animation dispatch survived reflow. See runtime-qa.json.

## Evidence and checks

Original screenshots are saved without image modification. Desktop was requested 960x540 and measured 958x540. Actual-resolution portrait measured 390x844 and 320x720; short landscape measured 720x239.333. These are custom Studio resolutions, not phone hardware or touch tests.

876 Luau tests and six runner self-tests passed. Selene reported zero errors/warnings, StyLua check passed, and Rojo produced the distribution build. All 36 models loaded without placeholders. Two inspection-command errors (a mistaken service name and reading Text from a ScrollingFrame) were corrected and are not game-script errors. Roblox CorePackages FoundationProvider warnings and Studio API denial remain.

Stop removed the temporary profile/QA scripts. The clean Edit model contained 143 matching shipping sources, no attributes and only Terrain, SpawnLocation and Camera in Workspace before publication.

## Judgment and remaining work

Composition 3.75/5: elevation and usable destinations improve depth, but broad simple ground and the repeated island outline remain visible. This pass does not claim the map is finished to the user's desired standard.

Models 4/5: the two battle creatures remain readable across normal desktop and portrait sizes. Primitive scenic construction is still apparent. Animation 4/5 for the exercised turn: movement, recoil, recovery and resize behaved correctly; shared families and very short screens limit presentation.

Feedback 4/5 for battle: HP, turn changes, healing, cooldown and opponent replacement were visible. Onboarding 4/5 is carried forward from the v95 fresh-profile hatch/equip review, not a new walkthrough in this pass. Its source files were unchanged. Full first-gym onboarding still needs a natural playthrough.

Visual approval remains failed because composition is below four. The economy gate remains failed at median seven final-gym rebirths against the target five. Current-version published save/rejoin, new pass purchases, physical-phone performance and natural multi-hour progression are not newly validated. No production publication or purchase.

## Reusable prevention

Share scenic footprints between scatter and construction. Walk actual slopes in both directions, not just inspect their angles. Use viewport-specific combat layout with minimum control sizes instead of scaling a desktop canvas. When resizing, cancel old screen-space effects, replace anchors and preserve the event dispatcher; measure model recovery after a real turn.

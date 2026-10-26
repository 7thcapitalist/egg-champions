# Authored scenes and creature motion

Reviewed 2026-10-17 in Studio, before publishing TEST v95. This is a visual and interaction review, not complete launch approval.

## Visible changes

- Meadow: flowering pergola on the return loop and terraced spring opposite the ancient tree. The ancient crown, vines and stones now preserve ellipsoid silhouettes.
- Coast: striped sun pavilion, tidal stepping stones and branching coral. The first review caught disconnected spherical coral pieces; a sphere mesh now preserves their elongated sizes and visible contact.
- Volcano: steaming mineral pool backed by cooling columns and an open crystal garden.
- Reserved footprints keep random scenery out of the new structures. Two access paths connect them to the existing loop. Actual world part counts: Meadow 561, Coast 496, Volcano 376; budget 1500 each. This is not a physical-phone FPS measurement.
- Creature attacks now move and rotate the model, articulate available limbs and return to rest. Thirty species use eight shared families; whale breach, dragon coil and phoenix dive have distinct curves. Existing server event durations and battle strength are unchanged.

## Observed QA

Desktop requested 960x540; actual camera viewport 958x540. Overview and approach captures are attached. Native screenshot scaling differs from the logical game viewport.

A temporary Studio-only hero team paid the Meadow gym fee through the real UI and used WATER STRIKE. A render-step recorder observed Tidewhale recoil, anticipation, breach and exact root restoration over 877 samples. Position ranged from -0.908 to +0.692 on Z, and +0.011 to +1.122 on Y. Pitch ranged from -0.257 to +0.078 radians. See motion-runtime.json. The initial fixture used an invalid normal variant string; it was corrected to nil before the successful battle. Those fixture errors are not shipping-code errors.

The hero contact sheet shows sampled poses 0, 0.24, 0.52 and 1 in the actual renderer; it is a posed sheet, not a live battle screenshot. Separate runtime checks restored the model after cancellation and hiding, and accepted replacement during an active reaction. All QA scripts and profiles existed only during Play and were removed by Stop.

Fresh-profile portrait walkthrough used custom Studio resolution, actual camera and Main content 390x844. Real UI input opened eggs, hatched Shiny Puddlet, opened Pets, equipped it and closed the panel. FollowerTeam became puddlet:shiny, and the HUD changed from +2 to +14 per click. The owned passes were active; this was not a no-pass pacing test. Screenshots show the reachable HATCH, EQUIP and CLOSE actions. Prior 320x720 and 720x239 evidence remains in short-viewport-2026-10-17; those sizes were not rerun visually in this pass.

871 Luau tests and six runner self-tests passed. Selene: zero errors/warnings. StyLua check and both binary/XML builds passed. 36/36 model templates loaded with zero placeholders. Final clean play had no game-script errors; Studio API denial and Roblox CorePackages FoundationProvider warnings remain.

## Review judgment and limitations

Composition 3.75/5: better distribution of destinations and biome identity, but the common flat island/hub structure and broad ground surfaces still need stronger terrain composition.

Models 4/5: readable hero silhouettes and corrected landmark proportions. Smaller scenery remains visibly primitive.

Animation 3.75/5: real battle movement, distinct hero curves and reliable recovery; the arena still presents small isolated portraits and most species share motion families.

Feedback 4/5: tutorial action highlights and visible click gain were observed. Recoil/attack root motion measured through a real server turn. No new claim about every special effect.

Onboarding 4/5 for the observed first hatch/equip flow: the action is reachable in portrait and the next goal advances. The entire first gym journey and physical touch input are not covered.

The visual checker must still reject approval for the two categories below four. Save/rejoin in the current published version, new pass purchases, physical-phone performance and natural multi-hour progression remain unverified. Studio API access is disabled, so its temporary profiles cannot prove persistence. No production publication.

## Prevention carried into the factory

factory/VISUAL-QUALITY.md now requires reserved scene footprints, player-height contact checks, actual geometry counts, renderer verification of primitive dimensions, model-space battle phases and interruption cleanup. BattleMotion has species coverage, endpoints, framing bounds and hero-distinction regression checks; Scenery verifies the new routes and reserved areas.

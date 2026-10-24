# Visual review gap: composition below 4/5 (ROB-6)

Source: review notes on branch `codex/egg-champions-visual-rework`, under
`games/egg-champions/reports/` (not yet on main). Latest per-category scores
(elevation-battle-2026-10-17, TEST v95, Studio):

| Category | Score | Trend |
|---|---|---|
| Composition | 3.75 | 3.5 (v88) -> 3.75 (v95 scenes) -> 3.75 |
| Animation | 4.0 | 3.5 (v88) -> 3.75 (scenes) -> 4.0 (battle turn only) |
| Models | 4.0 | 4 |
| Feedback | 4.0 | 4 |
| Onboarding | 4.0 | 3.5 -> 4 (carried forward, not rerun) |

The visual check rejects approval while any category is under 4. Today only
composition is under 4. Animation reached 4 only for the exercised Tidewhale turn.

## Items pulling the score down (quoted from the reviews)

Composition (blocks launch):
1. Broad flat ground surfaces in all three worlds.
2. Repeated island/hub outline across worlds (same structure each biome).
3. Primitive small scenery (low-poly vegetation, shore details).

Animation (at 4 but fragile):
4. 30 species share 8 motion families; only whale, dragon and phoenix have distinct curves.
5. Arena shows small isolated portraits; creatures are small on very short viewports (63x63 at 720x239).

Not scored but caps the final grade:
6. Onboarding 4 is carried over from v95 hatch/equip; full first-gym journey never played.
7. No physical phone or frame-time evidence.

## Proposed fixes (one brief each, no economy or battle-strength change)

A. Terrain relief (composition, items 1-2). Per world, add 2 to 3 elevation bands
   across the broad ground (rolling mounds, a sunken basin or river bed) and break
   the island outline with 2 headlands/coves, different per biome. Reuse the
   shared footprint rule in `Scenery.luau`/`SceneLayout.luau` so scatter avoids them.
   Budget: stay under 1500 parts per world (now 573 / 508 / 388, so Coast and Volcano have room).
B. Ground detail (composition, items 1,3). Patch the flat ground with 3 to 4 palette
   variants per biome plus low clutter (rocks, grass tufts, shells, ember rocks) on
   the empty zones; target no empty area wider than a set radius in the overview camera.
C. Species motion (animation, item 4). Split the 8 families so each of the 30 species
   differs in at least curve or timing; start with the most-hatched Common/Rare pets.
   Extend `BattleMotion.spec` with a "no two species share the same signature" check.
D. Arena framing (animation, item 5). Larger creature stage on short landscape and
   a camera push on attack, minimum creature size target for 720x239.

Order by impact on the failing category: A, then B (both move composition), then C, D.

## Needs Studio (cannot be done or scored headless)

The new score requires a Studio review: overview and player-height captures per
world, a real battle turn, then `visual-review.json` with evidence hashes. Nothing
here claims a new score. Done when composition is 4 or higher with captures, and
animation stays at 4 or higher.

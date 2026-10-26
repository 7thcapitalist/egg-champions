# 50. Elevation and battle readability

## Done when

- [x] Add layered raised scenic areas and continuous ramps from the existing paths; share footprints between scenery planning and construction.
- [x] Check player traversal up and down the new ramps in Studio and retain clear gameplay corridors.
- [x] Replace the uniformly scaled battle mockup with a responsive layout: larger creatures, readable HP and reachable move controls in desktop, portrait and short landscape.
- [x] Preserve battle effects and reset their anchors when the viewport changes; test layout bounds and observe an actual turn.
- [x] Capture player-height and overview map evidence plus battle evidence, record honest review scores and reusable factory prevention rules.
- [x] Pass tests/lint/build: 876 Luau tests and six self-tests; zero Selene findings; StyLua and Rojo passed.
- [ ] Revalidate the 2026-10-20 short-landscape side panels, readable names/HP, attack and viewport resize in Studio; capture new evidence before visual approval.
- [ ] Confirm TEST publication, reopen and compare all 143 shipping sources, complete the brief and push.

Geometry and presentation only. No battle-strength, economy or profile changes.

Publication requested 2026-10-17 01:35:38 America/New_York. Studio had disconnected
from its editing server at 01:34:44, then reported Publishing in progress. No new
version is confirmed yet. v95 is the last verified publication. Full recovery
checkpoint and tested distribution build are preserved under build/.

Resumed locally 2026-10-20. Short-landscape battle now places status beside
creatures: at 720x239 with a 58px top inset, the computed creature square grows
from 63px to 117px while move controls remain 44px high. Portrait and desktop
sizes are unchanged in the compared cases. The revised game has 882 tests and
six runner self-tests passing; Selene, StyLua and a separate Rojo build passed.
A separate local Studio session verified attacks, replacements, healing,
short-landscape and portrait resize, and six uphill/downhill ramp walks.
Screenshots were displayed in the conversation; local image archival was
blocked by the tool's automatic-review size limit. Visual approval and the
publication/reopen check therefore remain open. No publication or factory
executor run. See [resume review](../reports/task50-resume-2026-10-20/REVIEW.md).

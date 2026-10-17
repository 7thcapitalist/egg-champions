# 48. Reachable actions in short viewports

## Done when

- [x] EGGS, PETS and the tutorial action fit a 720x239 viewport; the full menu also fits.
- [x] Switching screens preserves the short layout and does not restore the optional team strip over the menu.
- [x] Regression coverage checks bounds, chat, touch corners and overlap at short landscape sizes.
- [x] Record actual Studio viewport and screenshots at short landscape and attempt 320x720 and 390x844 portrait. Explicitly record any emulator limitation.
- [x] Luau tests, lint, formatting and binary build pass.
- [x] Publish only TEST and reopen the cloud version to compare shipping source hashes.
- [x] Fix short egg-shop and inventory clipping found during the end-to-end check; auto-reveal EQUIP while preserving a fixed Close button.
- [x] Add effective-resolution and actionable-scroll review requirements to factory/VISUAL-QUALITY.md.

The team summary strip is omitted only below 360 px height in landscape. The Pets screen remains accessible and still shows the complete team. No gameplay or saved profile changes.

Evidence: reports/short-viewport-2026-10-17/. TEST v92, 137 matching source hashes. Portrait captured at actual 320x720 and 390x844 using custom Studio resolution, not physical-phone validation. 866 Luau tests and six self-tests pass. Final art approval and the median-five rebirth gap remain open.

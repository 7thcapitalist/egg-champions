# Short viewport and tutorial action repair

2026-10-17, America/New_York. TEST only, version 92.

## Changes

- Below 360 px height in landscape, the menu becomes a centered horizontal row with 40 px buttons. EGGS and PETS remain visible; the complete four-action menu also fits the tested rectangles. The optional team summary is hidden there, with the full team still available in PETS.
- Opening and closing screens reapplies the layout, so the hidden summary does not reappear over the short toolbar.
- The short egg shop uses a smaller egg/title row and omits the separate tutorial sentence. The HATCH pointer remains, and HATCH is fully visible without scrolling.
- Short inventory keeps tabs and Close fixed while its body scrolls. Selecting a pet automatically centers EQUIP within the visible body. Best Coins, Best Battle, filters and stats remain accessible by scrolling.
- The factory visual contract now requires effective viewport dimensions, portrait captures and real action checks, including scroll reachability.

## Verification

866 Luau tests plus six runner self-tests pass. Selene: zero errors/warnings. StyLua and Rojo binary/XML builds pass. Regression cases cover short landscape menu counts 2-4, empty/equipped teams, chat on/off, several top bars, primary-action bounds, inventory canvas reachability and automatic EQUIP reveal.

Studio actual viewport was 720x239.333328 (DPI rounding); GUI area matched. Native MCP mouse input opened EGGS, PETS and tutorial OPEN EGGS. HATCH produced a pet; in the final run the selected Leafpup EQUIP was auto-revealed at scroll 96.3333 and clicked, increasing the HUD from +2 to +4 per click. An earlier run hatched/equipped Abacatudo and increased +2 to +12. Closing PETS kept the horizontal menu visible and team summary hidden. Ordinary UI scroll input also moved the inventory body. No persistent profile was edited; Studio reports API access disabled and uses a temporary profile. Existing owned passes were active, so these are UI flow tests, not a no-pass economy run.

The iPhone preset continued to render dimensions different from its requested resolution. To obtain honest portrait layout evidence, the custom-resolution HD preset was used at actual camera/GUI 320x720 and 390x844. Both HUD and inventory were captured in portrait and inspected. These are portrait layout checks using mouse input, not phone touch, rotation behavior or physical-device performance approval. Runtime dimensions are in runtime.json. Screenshot output is DPI-scaled; its aspect ratio matches the measured viewport.

## Evidence

- short-landscape-hud.jpg: EGGS, PETS and OPEN EGGS fully visible after equip.
- short-landscape-eggs.jpg: HATCH visible on the short egg shop.
- short-landscape-equip.jpg: automatic reveal of the selected pet's EQUIP action.
- portrait-320x720-hud.jpg and portrait-320x720-pets.jpg.
- portrait-390x844-hud.jpg and portrait-390x844-pets.jpg.
- publish-output.txt: native Studio confirmation, v92 at 00:41:34 local.
- cloud-reopened.json: reopened TEST place 101737317546942, universe 10769019206, version 92, all 137 shipping source hashes match. Workspace has no QA fixture and no test attributes.

## Remaining release work

This closes the short toolbar clipping defect from the v88 review and supplies actual portrait layout captures. It does not upgrade the overall visual score: composition and animation remain 3.5/5 pending further art review. The median-seven versus target-five rebirth gap is unchanged. Full published save/rejoin field comparison, new pass purchase flow and physical phone performance still need independent evidence. No production publish or paid purchase occurred.

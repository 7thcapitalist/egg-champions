# Task 29: Egg shop you can use without scrolling

## Goal
Playtest at 808 x 432: HATCH sits below the visible area of the shop (the
tutorial points at nothing), all 6 eggs of all worlds are listed, the eggs are
flat ovals, and the modal hides the top bar.

## Build
1. Card layout: egg view, name, price, HATCH and HATCH X3 in the top part of
   each card; the odds list collapses behind "Show odds".
2. List only eggs of unlocked worlds, plus the next locked egg as one teaser
   card.
3. The hatch result overlays the card instead of pushing it down; scroll
   position is kept.
4. Each card shows the egg's real model in a ViewportFrame from
   ReplicatedStorage.PetModels (placeholder only if missing).
5. The modal starts below the top bar (respect GuiService:GetGuiInset).
6. A pure layout spec: at 808 x 432 and 1280 x 720 the first card's HATCH
   rectangle lies inside the visible list area with scroll 0, before and
   after a hatch.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.

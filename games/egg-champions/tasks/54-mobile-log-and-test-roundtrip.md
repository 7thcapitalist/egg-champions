# 54. Mobile log and TEST roundtrip

## Goal

Keep complete battle messages readable on small screens, observe the simulator
action matrix, and validate real TEST saves and re-entry on the reviewed version.
The owner's 2026-10-20 continuation authorizes TEST validation. Production and
spending remain separate actions. Do not publish seeded QA fixtures.

Scope: src/client/UI/{Battle,EggShop,Main,Journey,Theme}.luau and
src/shared/ui/{BattleLayout,EggShopLayout,HudLayout,PetsLayout}.luau and their specs,
reports/mobile-roundtrip-2026-10-20/,
release/ evidence bindings, this brief and tasks/index.json.

## Done when

- [x] Measure wrapped log lines with the actual font/width; reflow on resize
  and discard measurements for deleted or superseded lines.
- [x] Observe long battle messages and an attack/heal after viewport changes.
- [ ] Exercise hatch, equip, Journey target, attack, heal and resize in the
  required desktop, small portrait, phone portrait and short landscape cases.
- [ ] Record original captures, effective dimensions and observed actions.
- [ ] Obtain actual physical-touch and impaired-network evidence; never infer
  these from simulator results.
- [x] Pass Luau, lint, formatting and a separate normal Rojo build.
- [x] Publish only the reviewed normal TEST candidate, reopen and compare sources.
- [ ] Observe same-version real DataStore save/release/re-entry and compare every
  field required by beta_checks.py. No temporary profiles or mocks count.
- [x] Run release gates; record only their actual results.

Keep incomplete observations pending and preserve existing local/user changes.

## Owner feedback, 2026-10-21

The owner found mobile buttons too large and visually heavy. Their physical
device is iPhone 17; landscape is the primary acceptance orientation. Compact
menu width is now 84px; battle controls are capped in width, mobile moves use
48px height (44px on very short screens), and portrait surrender uses a compact
100px control. Shared button treatment uses an 8px radius, a 1px border and a
subtle tonal fill. Recheck the complete matrix against this revised build;
earlier screenshots do not certify the revised source.

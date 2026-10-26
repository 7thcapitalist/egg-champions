# Collection trail using existing egg bonuses

Feature: `collection-trail`

## Goal

Show normal-pet sets and missing species in Journey; suggest an unlocked incomplete egg and open its existing shop. Existing server index and bonus remain authoritative.

## Build

- Pure read-only goal selector using Config and existing unlock rules.
- Journey set rows and target egg button; no claims, new rewards or save fields.

Scope: `src/client/UI/Journey.luau`, `src/shared/ui/CollectionGoals.luau`, `src/shared/ui/specs/CollectionGoals.spec.luau`, `src/shared/testing/specs.luau`

## Done when

- [x] Deterministic normal/variant, completion, unlock and no-mutation tests pass.
- [x] Luau suite, Selene, StyLua and separate Rojo build pass.

## Needs human or playtester

- [ ] Inspect Journey scrolling and target shop on mobile and desktop with a temporary profile.

## Out of scope

No automatic publication, executor launch or budget authorization. Do not copy reference branding, pets or assets. Changes outside the declared scope need a new design review. A drafted brief is not evidence of implementation.

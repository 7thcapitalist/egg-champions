# 52. Beta economy and validation

## Goal

Remove excess third-gym rebirths while preserving the pacing targets. Prepare
separate save, mobile and multiplayer checks without publication or factory runs.

## Build

- Explicit spec cohort-power factor, generated config and auditable tuning.
- Separate local QA project with guarded two-client RPC fixtures.
- Read-only snapshots, optional save-result evidence and fail-closed validators.
- Preserve existing Studio sessions and keep the shipping project fixture-free.

## Done when

- [x] Canonical 300-player-per-rate simulation meets all six unchanged targets.
- [x] Report extra-seed sensitivity, including any failures outside gym 3.
- [x] Deterministic mock save/rejoin, failure and isolation checks pass.
- [x] Source tests, lint, formatting, regular build and isolated QA build pass.
- [x] Prepare evidence templates that block on missing live observations.
- [ ] Observe two-client fixture results and disconnect/rejoin on the reviewed build.
- [ ] Review simulator matrix and real touch; bind captures and action evidence.
- [ ] Validate real TEST save/rejoin on one version after separate authorization.

Local continuation 2026-10-20: two real Studio clients passed nine RPC cases
after correcting fixture ordering; disconnect/rejoin remains unknown. Small
portrait 320x624 effective viewport observed prompt and a gym 3 attack with
temporary seeded team only. Full matrix, visual evidence binding, physical
touch, slow network and persistent TEST saves remain pending. See
reports/launch-readiness-2026-10-20/README.md. New read-only release gates block
on missing evidence; no publication, factory or stage approval occurred.

## Out of scope

No publication, factory launch, Dot executor/control changes, credentials,
permission changes, purchases or global settings. A mock or local temporary
profile does not satisfy the live-beta checks. Task remains pending.

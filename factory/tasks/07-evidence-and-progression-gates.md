# 07. Evidence and progression gates

The existing time-only economy gate can accept a report whose rebirth targets
are missed. A visual review can reference an image that has since been replaced,
or call a landscape capture portrait without recording the effective viewport.

## Done when

- [x] Require every configured gym's rebirth verdict as well as the existing time targets; report the current game's missed target as a failure.
- [x] Bind visual evidence to file hashes and record requested/effective viewport dimensions; reject a mislabeled portrait capture.
- [x] Add regression cases for missing/failed progression targets, altered evidence and incorrect viewport orientation.
- [x] Document a generic published persistence protocol that distinguishes temporary Studio profiles and partial screenshots from save validation.
- [x] Update the current review manifest and stage record honestly; do not implement a fake passed playtest/publish gate.
- [x] Run the affected Python tests, commit and push.

Verification: all 18 Python tests passed. Egg Champions economy_tuned correctly
fails on final-gym median seven versus target five; the current visual review
fails only composition and animation scores below four. Evidence hashes and
actual desktop/portrait dimensions validate. TEST remains v95; these factory
and report changes do not change shipping game sources.

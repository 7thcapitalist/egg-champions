# Published test persistence protocol

Publication, a successful build and a successful persistence test are separate
facts. A Studio temporary profile cannot validate a published save. Record
blocked and untested cases explicitly. Never approve a stage from a partial
screenshot or an unimplemented gate.

## Evidence for one round trip

1. Record the authorized TEST universe/place, the actual running version, UTC
   time and session/server identity. Use a pseudonymous test-profile identifier;
   omit credentials and personal account details from reports.
2. Perform free, distinguishable actions: earn currency, obtain an item, change
   the equipped team, advance onboarding or collection progress. Do not buy a
   pass or reset progression merely to create a test case.
3. Capture a structured read-only snapshot immediately before leaving. Record
   which fields are unavailable. Exit the session normally; record save
   confirmation if the runtime exposes it.
4. Rejoin the same TEST version with the same profile in a new session. Capture
   the state before new actions, and record expected passive accrual separately.
5. Compare currency, item IDs and variants, ordered equipped IDs, collection,
   permanent achievements, reset count, current-run unlocks, paid entry fees,
   retry deadlines and onboarding state. Derive the exact list from the game's
   saved-profile schema. Play time should be monotonic. Never normalize away
   identity, team order or missing inventory.

If versions differ, rerun on one version or mark the comparison blocked. Report
passed/failed/blocked/untested per field, with before/after evidence. A visible
world and team surviving rejoin is useful partial evidence, but does not prove
exact balances, item identities or retry deadlines. Without structured access,
state that limitation rather than adding an unauthenticated debug endpoint.

## Pass and progression checks

Existing ownership, free-user restrictions and purchase completion are different
cases. Record exactly which were exercised; never count an owned pass as a new
purchase test. Spending requires explicit authorization.

For natural progression, record actual input rate, owned passes, hatches,
equipped teams, failures and resets. A simulator run is a prediction. Its
reference combat team and cohort selection policy must both be documented.
Changing only a leader to satisfy one median can break other progression targets.

Future playtested/published_test gates must require these artifacts for the same
shipping version. They remain unimplemented until there is an actual validator;
this document does not mark those stages passed.

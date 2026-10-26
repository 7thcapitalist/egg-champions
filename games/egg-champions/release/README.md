# Release evidence contract

The manifest is intentionally incomplete. Null means unknown and blocks release.
It binds the normal local candidate and current source/config/tuning hash. Never
substitute the QA place for the shipping place. Rebuild and rebind after source
changes; old evidence must be reviewed again. Do not fabricate missing evidence.

Read-only status, no AI or Studio calls:

```
python -B factory/tools/release_readiness.py games/egg-champions
```

Exit 1 means blocked, 0 means these evidence checks pass, 2 means invalid CLI
usage. This is not authority to publish or proof of compliance with every task.
Task checklists, economy and the owner's publication instruction still apply.

Each reference is an object with file (relative to the game) and sha256. JSON
evidence other than visual must carry build_sha256 matching the normal candidate.
Visual uses the separate quality_review source hash and its own image bindings.
See factory/tools/release_readiness.py, beta_checks.py and quality_review.py for
the exact fields. Reports cannot certify their own observations by hashes alone.

- worlds: visual review in all five categories >=4, desktop/mobile captures,
  all configured world arrivals and traversal reviewed.
- playtested: worlds plus the complete mobile and multiplayer matrices, physical
  slow network, and unseeded free-player natural progression through gyms 2+.
- published_test: playtested plus real DataStore save/rejoin/release, actual
  pass completion/effects, publication version and reopened source comparison.
  Gameplay, saves and passes must identify the same configured TEST version.

slow_network requires published-client, physical_device=true, a named observed
impairment_method, finite positive added_latency_ms and bandwidth_kbps, plus
hatch/battle/reconnect="passed". These are measured test conditions, not invented
acceptance thresholds. No network quality SLA or elapsed-time ceiling is asserted.
Record the actual setup and observations in the referenced report.

Local temporary saves, seeded teams, simulated purchases and code-level mocks
cannot replace the real TEST cases. Current publication remains prohibited.

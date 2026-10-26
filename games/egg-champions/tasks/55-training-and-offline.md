# 55: Training grounds and offline pet income

Owner-directed change on 2026-10-21. Scope: spec/config/tuning, training rules,
world kit/builder/scenery, server reward/pass/shop/profile services, follower and
avatar effects, tutorial/guide/HUD, offline card, factory evidence tools/tests,
and reports/training-offline-2026-10-21. Preserve the schema and existing saves.
Only normal builds may be published to TEST. Production is outside this task.

- [x] Replace click rewards with server-observed training zones in each world.
- [x] Keep joystick and camera input native; remove the invisible click layer.
- [x] Show pet lunges, target recoil and compatible avatar punches.
- [x] Award capped offline income atomically and display a compact welcome card.
- [x] Test dwell, exits, unlock/death/battle eligibility and offline storage retries.
- [x] Regenerate config and rerun economy using the configured training rate.
- [x] Observe simulated landscape movement, camera drag, training and exit.
- [ ] Complete required mobile matrix, physical iPhone and impaired-network checks.
- [x] Publish normal candidate to TEST, reopen and verify the uploaded sources.
- [ ] Observe real persistent offline income and save/release/re-entry on TEST.
- [ ] Pass release gates with current evidence; no mocked or temporary save proof.

See the report for exact observations and limits. Task remains running.

Owner follow-up: faster 4 Hz training and concurrent hatching implemented and tested. New candidate source verified in TEST Studio Edit; publication pending after owner requested stopping native control. Historical publication checkbox above refers to v103. See reports/training-fast-hatch-2026-10-21.

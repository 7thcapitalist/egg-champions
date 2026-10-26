# Training and offline income, 2026-10-21

The owner requested training targets instead of click farming and income while
away. The spec now defines four training hits each second, one extra hit for the
existing auto-click pass, and offline income at 25% of the saved active rate for
up to two hours with equipped pets. Profile schema remains version 5.

Offline awards and consumed clocks are committed atomically during session claim.
Unit/runtime tests cover the cap, invalid dates/rates, legacy records, repeated
claim, replayed UpdateAsync callbacks, lost acknowledgement and failed release.
These mocked storage tests do not certify real TEST persistence.

Local Studio observations are in observations.json. The first preview used the
same gameplay before the AnimationConstraint compatibility correction; avatar
motion and the offline card were rechecked after synchronizing final runtime
sources. Offline card used a temporary display fixture, never a real award.
No fixture or test helper remains after stopping Play. The simulator was reset.

Local checks: 891 Luau tests, Selene zero errors/warnings, StyLua, normal Rojo
build. Final Python suite: 132 tests passed, including configured-rate isolation,
pass-cache departure, atomic offline rewards and bound save receipts.
Economy rerun with configured active rate: first hatch 16 seconds, gym 1 25.4
minutes, final gym 6.83 hours, rebirth medians 0/2/5; all targets met. Forecast
excludes travel/idle and offline income. Physical touch, impaired network, full
mobile action matrix and persistent TEST rejoin remain pending.

The beta save comparator accepts a coin increase only with matching successful
release metadata and the exact server receipt, timestamp, saved rate and cap.
Inventory and every other profile field still require their previous checks.

Publication attempt selected the existing public Egg Champions Test destination.
Studio remained on Upload in progress without a confirmed version. The dialog
was dismissed with Escape and the edit DataModel still reported PlaceId/Version
0. Do not infer a successful upload or recommend phone rejoin as a verified fix.
The final candidate additionally retains known pass ownership with weak keys
while a final save yields, so PlayerRemoving cannot erase offline bonuses.
A dedicated runtime test confirms entitlement retention and player isolation.

Release manifest now binds the current normal candidate, with all external
review/evidence references still null. Previously stale reviews are not reused.
Spec and economy gates pass; planned gate sees 55 tasks. Built still fails at
unfinished task 50; publication and complete release evidence remain pending.

## Confirmed publication, version 103

Opened the public TEST directly in Studio: its published v100 still had the
ClickLayer and lacked TrainingService and Offline. Applied the tested candidate
source tree to that TEST and used direct Publish to Roblox. Studio confirmed
v103. Closed and reopened TEST from Roblox: PlaceVersion=103, 153 source/config
modules passed SHA-256 comparison and all 172 mapped instances matched classes.
Training and offline modules are present; ClickLayer is absent. Source tree
matches the normal candidate bound in the release manifest. The short-lived
compressed transfer object was removed before publishing. HTTP requests remained
disabled in the published candidate.

Reopened v103 was tested in iPhone 17 Pro landscape simulation (750x381 viewport).
A simulated stick drag moved the avatar from [1.6305,2.9980,-0.4921] to
[8.2875,2.9980,21.9795]. A separate world drag changed the camera look vector
without changing that position. The training target and compact menu were seen.
Play was stopped and the simulator reset. These are simulator observations, not
physical iPhone evidence. Studio API access is disabled, so this play session
used a temporary profile and does not certify a persistent offline reward.
See publication-v103.json for the exact measurements and version binding.

Only the publication checklist items are now checked. Physical touch, slow
network, full action matrix, live persistence and the remaining factory gates
are still pending. Production was not opened or published.

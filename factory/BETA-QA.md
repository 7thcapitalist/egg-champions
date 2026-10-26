# Beta validation without publishing or starting the executor

All commands below are deterministic scripts. None calls a model. Keep the
executor paused. A QA fixture place must never be published. Do not change
Studio API permissions or credentials to make a local test pass.

## Separate local multiplayer build

```
python -B factory/tools/build_beta.py <game> <game>/build/new-beta-review
```

The directory must be new; retries refuse overwrites. Open beta-local.rbxl in
a separate Studio session, preserving existing unsaved windows. Use Studio's
Server & Clients mode with two fresh clients. This revision prepares the file;
it does not automatically open Studio or start those clients.

The server fixture waits up to 60 seconds for two loaded client drivers. It
requires IsStudio, PlaceId zero, BetaQA, passes disabled and fresh temporary
profiles before seeding. If real storage is reachable, it refuses to seed.
Do not click or earn coins while the fixture is waiting: nonempty profiles
are refused instead of overwritten.

The QA-only client drivers use real InvokeServer requests. Tests cover profile
isolation, charging a fee once, concurrent battles, duplicate starts, foreign
session/pet refusals, separate retry waits and per-player rate limits. Each
client-driver call has an eight-second deadline. The runtime cannot cancel an
already outstanding InvokeClient coroutine; after timeout the fixture reports
blocked and stops scheduling requests. Stop this local QA session to clean up.

Read `[Beta multiplayer]` in server Output. No fixture result has been observed
in the engine in this revision. A built fixture is not a passed test. The
disconnect/rejoin case remains unknown even if its other assertions pass.
Local two-client transport does not prove internet latency, load capacity or
cross-server locking. QA remotes/scripts are absent from default.project.json.

## Mobile matrix

Review requested sizes 1280x720, 320x720, 390x844 and 568x239, plus an actual
phone using its real dimensions. Record effective camera dimensions, GUI size,
insets, simulator/device identity and input method separately. Do not report
the requested size as the effective result.

BetaMobile is disabled in the QA project. To collect measurements, open the
screen, set the LocalScript attributes Screen, BuildSha256, RequestedWidth
and RequestedHeight, then explicitly enable it. It prints `[Beta mobile]` with
visible controls, sizes, positions and text fitting. At most 300 entries are
included; truncated output is incomplete evidence. Scroll clipping and physical
reachability need visual inspection; rectangle/text-fit values alone do not
approve them. The recorder never clicks, equips, buys or changes a profile.

For every case, exercise hatch, equip, Journey's target egg, battle attack,
healing and resize during/after an effect. Verify no blocked controls, clipped
text or stuck creature pose. Record screenshots and action logs. Simulator
input may cover the fixed viewport cases; physical-phone requires real touch.
The validator checks recorded coverage and evidence hashes, not visual truth.

## Save/rejoin evidence, prepared for a separately authorized TEST session

No published session or live DataStore roundtrip is run by these commands.
Follow PUBLISHED-QA.md on the same reviewed TEST version when that work is
authorized. Do not publish the local fixture place to perform this test.

`beta_snapshot.server.luau` is a disabled read-only server capture template.
Set its BuildSha256 and give each tester a stable private BetaSubject player
attribute. Published captures use game.JobId; local captures require a separate
SessionId attribute and still cannot count as persistence. It exports the
server-owned profile and persistence mode, with release_confirmed=false.
There is no client snapshot endpoint and no write or forced save in this script.

The reviewed game now exposes Profiles.persistenceMode and opt-in save logs.
For the authorized TEST session only, set ServerScriptService attributes
BetaSaveEvidence=true and BetaBuildSha256 to the tested build hash. Without
these QA attributes no extra logging is enabled. No global setting is needed.
`[Beta save]` records the actual save result and whether a session was released;
temporary Studio saves always say saved=false for persistence purposes.
Optional encoding failure cannot break the save/release, and leaves evidence
unavailable. It never changes the DataStore key, locking, credentials or retry
policy. No QA attributes were enabled on a published place in this revision.

Before leaving, capture distinguishable free progress. Leave normally, save
the JSON payload of the matching successful release log as release.json,
and bind it by relative path and SHA-256 in before.release_evidence. Mark
release_confirmed=true only after observing that event. Capture after rejoin
before taking new actions. The CLI reads the bound release file itself.

Compare all Profile schema-v5 fields: currency, pet identities/variants,
ordered team, index, achievements, rebirths, unlocks, paid fees, retry deadlines,
tutorial and monotonic play time. Missing fields, temporary profiles, different
versions/builds/subjects, same-session captures or absent release proof block.
No offline earnings are assumed by the current game. Keep aliases private;
do not put account IDs, credentials or unrelated logs in review artifacts.

## Read-only evidence validators

```
python -B factory/tools/beta_checks.py saves before.json after.json
python -B factory/tools/beta_checks.py mobile mobile.json
python -B factory/tools/beta_checks.py multiplayer multiplayer.json
```

Unknown/pending/failed evidence returns exit 1. Matrix case evidence is a
relative file path and matching SHA-256 inside the report directory. Fill the
prepared game templates with observations; never turn unknown into passed
because a fixture compiled or a mock succeeded. These validators are explicit
tools, not automatically wired to playtested/published_test stage gates.
They cannot prove that supplied logs or human attestations are truthful.

Official engine references:
- https://create.roblox.com/docs/studio/testing-modes
- https://create.roblox.com/docs/reference/engine/classes/RemoteFunction/InvokeClient
- https://create.roblox.com/docs/reference/engine/datatypes/DateTime

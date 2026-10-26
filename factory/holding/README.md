# Holding bridge and admission

Versioned sources of the HQ guard/quota scripts live here. Their current copies
are installed in holding-hq/scripts (mini PC: ~/dev/holding-hq/scripts; Windows:
C:/Users/joaov/dev/holding-hq/scripts) with explicit scoped filesystem authorization. Tests copy these sources only into temporary fixtures,
never over the live executor or its authorization/ledger.

## Budget guard

`node scripts/guard.mjs check roblox [codex|claude]` inside holding-hq reads local
measurements and weekly accounting. Default checks both providers; the bridge
checks Codex alone because it delegates exclusively to codex exec. It cannot
silently fall back to Claude. Only verdict OK exits 0; STOP and UNKNOWN exit 3.
Invalid commands/files can exit another nonzero code, also a block.

- Measurements must have explicit timestamps, be <=300 seconds old, not future,
  identify a reset, and report a finite percentage within 0..100.
- Codex requires an explicit seven-day window; no short-window fallback. Paid
  credit state must explicitly be false. No prices/dollars are calculated.
- A reported exhausted five-hour window also blocks. Missing short-window data
  remains unknown; the mandatory weekly measurement does not guarantee runtime
  availability in a short window the runtime did not report.
- Claude requires an unambiguous single account and fetched timestamp; file
  modification time does not count as a measurement.
- Weekly ledger missing, empty, corrupt, unfinished, duplicated, regressive or
  crossing an unaccounted reset blocks. Missing usage remains null, never zero.
- Existing budget.json shares/reserves are unchanged. The guard no longer
  rounds consumption downward before comparing it to the share.

`record` remains append-only accounting, not permission to generate. A baseline
was installed after explicit terminal approval. An absent ledger needs an operator-reviewed
accounting baseline; do not invent zero, delete history or bootstrap by running AI.

## Worker bridge

`factory/tools/holding_worker.py` inspects by default, without model calls:

```
python -B factory/tools/holding_worker.py --hq HQ --workspaces WORKSPACES --game ISOLATED_GAME --task ID
```

Replace the four uppercase placeholders with reviewed paths/task. Paperclip's
process adapter supports command/args/cwd/timeoutSec, verified against local
server source. All four Roblox agents now use process adapters pinned to
paperclip_agent.py: director/research/analyst perform deterministic checks;
engineer delegates eligible code work exclusively to holding_worker.py.
On 2026-10-21 director/analyst/research were resumed and completed one actual
Paperclip script check each. Engineer remains paused; no real model job has been
scheduled. All automatic heartbeats remain disabled.

Requirements: isolated clean hq/ worktree below the declared workspace root,
shared Git common directory with this worker's canonical repository, built stage,
exact next eligible task, policy authorization and fresh quota, intact executor
ledger and no lock, then holding admission. Independent clones are refused so
they cannot reset task attempts. The active user checkout is refused.

`--execute` is a separate explicit action. It takes the holding-wide Roblox
lock, rechecks admission, records before/after quota around the existing factory,
and delegates at most one task with two attempts. The existing factory owns
the model/effort, deadlines, repository lock, CLI usage journal and verification.
No policy rewrite, automatic unpause/unblock, alternate runtime, push or publish.
There is no retry loop in the bridge and the final measurement is attempted even
on failure. Unknown final usage blocks later work; neither lock is auto-cleared
when it existed before the current process.

The holding requires studios/roblox/executor-runtime.json; missing authorization
never falls back to the legacy project policy. Fresh Codex quota is read before
admission and every model call without rewriting authorization. ProtectedRun
reuses the original executor but refuses reset/clean rollback or unexpected
commits, preserving partial work. The legacy executor source and policy remain
untouched. The model child receives no Paperclip bearer or paid API/publish keys.

## Explicit forward accounting window

The user authorized up to two CLI calls, 20,000 reported tokens and one percentage
point from a new baseline, retaining the 15% account reserve. Historical studio
use remains null. This is a separate authorized forward window, not a claim that
the old weekly share has never been used. Other account activity is charged
conservatively against its percentage envelope. No automatic renewal/reset.

holding_authorization.py prepares one baseline plus its authorization file
under an exclusive lock. It refuses existing files, unknown/stale quota, paid
credits, exhausted quota and an unexpected central economic model. The guard
binds the baseline's exact hash, authorization, provider, reset and limits. It
reports used_pct_of_plan=null and a separate used_pct_of_window, never a fake
historical zero. Incomplete/changed records block.

First installation was denied by Windows at HQ/runtime (WinError5), after scoped
filesystem permission was granted; Git also failed to create its reference.
Later the user explicitly authorized terminal approval for both operations;
both succeeded. A further approved read verified the clean hq/ worktree and
shared Git ledger. The original denial evidence remains historical in
reports/holding-integration-2026-10-20/.

Current evidence is in reports/holding-activation-2026-10-21/. Baseline account
usage was 67%, current usage 75%, an observed eight percentage point delta
against the one-point window. The account delta includes other work; it is not
attributed to this factory. The local guard also refuses a changed weekly reset
timestamp (15:31:45Z versus 15:31:46Z). Inside Paperclip the director reported no
required quota measurement. No baseline was reset or new budget installed.

This is currently a built-stage bridge, not a complete autonomous manager,
planner, art maker or published playtester. The source/current game has local
uncommitted work; no copying/synchronization to other checkouts was performed.

## Enforced boundaries and limits

Repository-shared ledger enforces two total executor launches per task, measured
usage accounting, model mismatch and lock protection. Cache is a subset of input,
not an extra charge. Existing executor tests cover timeout/kill-tree, unknown
tokens and retries; the bridge neither estimates nor substitutes missing tokens.

Holding accounting measures subscription percentages, not token or money prices.
It is not signed and is not an atomic reservation against user chats, external
tools or unbridged Paperclip adapters. Subscription percentage deltas may include
other account activity. Admission thresholds cannot cap usage inside an already
admitted model call. Internal provider retries/effective model requests may be
unreported by the CLI. See factory/README.md for the executor's full limits.

Four Roblox Paperclip agents were initially paused while direct model adapters
were replaced by process adapters, heartbeats disabled and concurrency set to
one. Three script roles are now idle/available; engineer remains paused. The
game's running tasks are preserved and prevent duplicate generation.
Other companies, credentials, global settings, billing, Dot controls and
factory/executor.json were not changed. The holding quota ledger contains only
the explicitly authorized baseline; the executor call journal has no launches.

## Mini PC (Linux)

The Roblox agents run on the mini PC; Roblox Studio stays on the Windows PC.

- Control checkout (agent `cwd`, `--game`): `~/dev/_workspaces/roblox-factory`.
- Protected worker (`--worker-game`): a clean worktree of that clone at
  `~/dev/_workspaces/roblox-protected` on branch `hq/roblox-protected`, so both share
  the same Git common dir (the executor ledger) as the code requires.
- Python: `/usr/bin/python3` (3.12+). Tests: `python3 -m pytest factory` in a local `.venv/`.
- Toolchain: `rokit install` (luau, rojo, selene, StyLua from `rokit.toml`).
- `codex` comes from PATH and its quota from `~/.codex/sessions` via `quota.mjs`.
- Steps that need Roblox Studio go through the "[Windows]" gate in
  holding-hq (`scripts/windows-gate.mjs`, see `studios/roblox/playbook.md`).

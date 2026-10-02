#!/usr/bin/env python3
"""Factory tool: run one stage's check for one game.

Usage: python factory/tools/gate.py <game-dir> <stage>

Prints one short reason, then exits 0 if the stage passes and 1 if it does
not. A gate only reads what is already in the repo: it never regenerates
config or tuning, so a stale generated file fails the gate instead of being
quietly fixed. That is the point of a gate.

Stages with no machine check yet print "no gate yet" and exit 1, so an
orchestrator cannot mistake "not implemented" for "passed".
Standard library only.
"""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_config  # noqa: E402  lives next to this file

STAGES = [
    "spec_parsed",
    "economy_tuned",
    "planned",
    "built",
    "assets",
    "worlds",
    "playtested",
    "published_test",
]

# The pacing targets that are about time. The report also scores rebirths per
# gym, but that is a design question rather than a pacing one, so a miss
# there does not hold up the build. See the economy_tuned gate in the brief.
TIME_TARGETS = ("First hatch", "Gym 1 beaten", "Final gym beaten")


def fail(reason):
    print("FAIL: %s" % reason)
    return 1


def ok(reason):
    print("OK: %s" % reason)
    return 0


def read_json(path):
    """Return (data, error_message). Exactly one of the two is None."""
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except OSError as err:
        return None, "cannot read %s: %s" % (path.as_posix(), err)
    except ValueError as err:
        return None, "%s is not valid JSON: %s" % (path.as_posix(), err)


# ---------------------------------------------------------------- spec_parsed


def gate_spec_parsed(game):
    spec = game / "spec.md"
    config = game / "config"
    manifest_path = config / "manifest.json"
    if not spec.is_file():
        return fail("no spec at %s" % spec.as_posix())
    if not manifest_path.is_file():
        return fail("no manifest at %s. Run agent 1." % manifest_path.as_posix())

    manifest, err = read_json(manifest_path)
    if err:
        return fail(err)

    current = hashlib.sha256(spec.read_bytes()).hexdigest()
    recorded = manifest.get("spec_sha256")
    if recorded != current:
        return fail(
            "%s has changed since agent 1 last ran (spec %s, manifest %s). Rerun agent 1."
            % (spec.as_posix(), current[:12], str(recorded)[:12])
        )

    try:
        errors = validate_config.validate(config)
    except (OSError, ValueError, KeyError) as err:
        return fail("the validator could not read %s: %s" % (config.as_posix(), err))
    if errors:
        return fail("the validator found %d problem(s), first: %s" % (len(errors), errors[0]))

    return ok("config matches the spec's current hash and passes the validator")


# -------------------------------------------------------------- economy_tuned


def report_targets(text):
    """Map target name to verdict, from the report's results table.

    Reads the first markdown table under the results heading and stops at the
    blank line after it, so the tables that follow cannot shadow a target.
    """
    rows = {}
    started = False
    in_table = False
    for raw in text.splitlines():
        line = raw.strip()
        if not started:
            if line.startswith("## Current numbers against the targets"):
                started = True
            continue
        if line.startswith("|"):
            in_table = True
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) >= 2 and cells[0] not in ("Target", "---", ""):
                rows[cells[0]] = cells[-1]
        elif in_table:
            break
    return rows


def gate_economy_tuned(game):
    report = game / "tuning" / "report.md"
    if not report.is_file():
        return fail("no report at %s. Run agent 2." % report.as_posix())
    try:
        targets = report_targets(report.read_text(encoding="utf-8"))
    except OSError as err:
        return fail("cannot read %s: %s" % (report.as_posix(), err))

    if not targets:
        return fail("%s has no results table. Rerun agent 2." % report.as_posix())

    unscored = [t for t in TIME_TARGETS if t not in targets]
    if unscored:
        return fail(
            "%s does not score: %s. The report format changed; update this gate."
            % (report.as_posix(), ", ".join(unscored))
        )

    missed = [
        "%s is %s" % (t, targets[t]) for t in TIME_TARGETS if not targets[t].startswith("MET")
    ]
    if missed:
        return fail("time pacing missed: " + "; ".join(missed))

    return ok("all %d time pacing targets met" % len(TIME_TARGETS))


# --------------------------------------------------------------------- built


def unticked(path):
    """Line numbers of checklist items still left unticked in a task brief."""
    return [
        n
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if line.strip().startswith("- [ ]")
    ]


def index_briefs(game, index):
    """Return (brief paths, error_message) for the briefs a task index names.

    The planner owns this file, so read it loosely: either a list of entries
    or an object with a `tasks` list. An entry is a brief's file name, or an
    object with a `file` key. Whether a brief is done is not taken from the
    index: it is read from the brief's own Done-when checklist, which is how
    briefs are ticked today, so the index cannot claim work that did not
    happen.
    """
    entries = index.get("tasks") if isinstance(index, dict) else index
    if not isinstance(entries, list):
        return None, "expected a list of tasks, or an object with a 'tasks' list"
    if not entries:
        return None, "the task index is empty"
    paths = []
    for entry in entries:
        name = entry if isinstance(entry, str) else (entry or {}).get("file")
        if not isinstance(name, str) or not name:
            return None, "every task needs a 'file' naming its brief"
        paths.append(game / "tasks" / name)
    return paths, None


def gate_built(game):
    index_path = game / "tasks" / "index.json"
    if not index_path.is_file():
        return fail("no task index at %s. Run the planner." % index_path.as_posix())

    index, err = read_json(index_path)
    if err:
        return fail(err)

    briefs, err = index_briefs(game, index)
    if err:
        return fail("%s: %s" % (index_path.as_posix(), err))

    for brief in briefs:
        if not brief.is_file():
            return fail("the task index names %s, which does not exist" % brief.as_posix())
        try:
            left = unticked(brief)
        except OSError as read_err:
            return fail("cannot read %s: %s" % (brief.as_posix(), read_err))
        if left:
            return fail(
                "%s has %d unticked check(s), the first on line %d"
                % (brief.as_posix(), len(left), left[0])
            )

    out = game / "build"
    try:
        out.mkdir(parents=True, exist_ok=True)
    except OSError as mk_err:
        return fail("cannot create %s: %s" % (out.as_posix(), mk_err))

    checks = [
        ["rojo", "build", game.as_posix(), "-o", (out / "game.rbxl").as_posix()],
        ["selene", (game / "src").as_posix()],
        ["stylua", "--check", (game / "src").as_posix()],
    ]
    for cmd in checks:
        exe = shutil.which(cmd[0])
        if exe is None:
            return fail("%s is not on PATH" % cmd[0])
        done = subprocess.run([exe] + cmd[1:], capture_output=True, text=True)
        if done.returncode != 0:
            lines = (done.stderr or done.stdout or "").strip().splitlines()
            return fail(
                "%s failed: %s"
                % (cmd[0], lines[0] if lines else "exit code %d" % done.returncode)
            )

    return ok("%d task(s) done, and rojo, selene and stylua all pass" % len(briefs))


# ---------------------------------------------------------------------- main

GATES = {
    "spec_parsed": gate_spec_parsed,
    "economy_tuned": gate_economy_tuned,
    "built": gate_built,
}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        sys.exit(__doc__)
    game, stage = Path(argv[0]), argv[1]
    if not game.is_dir():
        return fail("no game folder at %s" % game.as_posix())
    if stage not in STAGES:
        return fail("unknown stage '%s'. Known: %s" % (stage, ", ".join(STAGES)))
    gate = GATES.get(stage)
    if gate is None:
        print("no gate yet for %s" % stage)
        return 1
    return gate(game)


if __name__ == "__main__":
    sys.exit(main())

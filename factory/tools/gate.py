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


DONE_WHEN = "## Done when"


def unticked(path):
    """Line numbers of unticked checks in a brief's Done-when section.

    Only that section counts. A brief's "Needs human or playtester" list holds
    checks no machine can run, so counting those would leave this gate unable
    to pass however much work was finished. A brief with no Done-when section
    has nothing to prove and so nothing unticked.
    """
    left = []
    inside = False
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("## "):
            inside = stripped == DONE_WHEN
            continue
        if inside and stripped.startswith("- [ ]"):
            left.append(n)
    return left


def load_tasks(game):
    """Return (tasks, error_message) from a game's task index.

    A task is {id, title, file, depends_on, status, path}. The planner owns
    the file, so read it loosely: either a list of entries or an object with
    a `tasks` list, and an entry may be just a brief's file name.
    """
    index_path = game / "tasks" / "index.json"
    if not index_path.is_file():
        return None, "no task index at %s. Run the planner." % index_path.as_posix()

    index, err = read_json(index_path)
    if err:
        return None, err

    entries = index.get("tasks") if isinstance(index, dict) else index
    if not isinstance(entries, list):
        return None, "%s: expected a list of tasks, or an object with a 'tasks' list" % (
            index_path.as_posix()
        )
    if not entries:
        return None, "%s: the task index is empty" % index_path.as_posix()

    tasks = []
    for position, entry in enumerate(entries, 1):
        if isinstance(entry, str):
            entry = {"file": entry}
        if not isinstance(entry, dict):
            return None, "%s: task %d is neither a file name nor an object" % (
                index_path.as_posix(),
                position,
            )
        name = entry.get("file")
        if not isinstance(name, str) or not name:
            return None, "%s: task %d needs a 'file' naming its brief" % (
                index_path.as_posix(),
                position,
            )
        depends = entry.get("depends_on") or []
        if not isinstance(depends, list):
            return None, "%s: task %s has a 'depends_on' that is not a list" % (
                index_path.as_posix(),
                entry.get("id", name),
            )
        tasks.append(
            {
                "id": str(entry.get("id") or name),
                "title": entry.get("title") or name,
                "file": name,
                "depends_on": [str(d) for d in depends],
                "status": entry.get("status") or "pending",
                "path": game / "tasks" / name,
            }
        )
    return tasks, None


def first_cycle(tasks):
    """Name a dependency cycle as 'a -> b -> a', or return None if acyclic."""
    by_id = {t["id"]: t for t in tasks}
    state = {}  # id -> 1 while on the stack, 2 once finished

    def walk(task_id, trail):
        if state.get(task_id) == 1:
            start = trail.index(task_id)
            return " -> ".join(trail[start:] + [task_id])
        if state.get(task_id) == 2:
            return None
        state[task_id] = 1
        for dep in by_id[task_id]["depends_on"]:
            if dep in by_id:
                found = walk(dep, trail + [task_id])
                if found:
                    return found
        state[task_id] = 2
        return None

    for task in tasks:
        found = walk(task["id"], [])
        if found:
            return found
    return None


def gate_planned(game):
    tasks, err = load_tasks(game)
    if err:
        return fail(err)

    missing = [t["path"].as_posix() for t in tasks if not t["path"].is_file()]
    if missing:
        return fail("the task index names %d missing brief(s): %s" % (len(missing), missing[0]))

    ids = [t["id"] for t in tasks]
    repeated = sorted({i for i in ids if ids.count(i) > 1})
    if repeated:
        return fail("the task index reuses id(s): %s" % ", ".join(repeated))

    known = set(ids)
    for task in tasks:
        unknown = [d for d in task["depends_on"] if d not in known]
        if unknown:
            return fail(
                "task %s depends on unknown id(s): %s" % (task["id"], ", ".join(unknown))
            )

    cycle = first_cycle(tasks)
    if cycle:
        return fail("the task dependencies form a cycle: %s" % cycle)

    first = tasks[0]
    if first["status"] != "done":
        return fail("task %s is '%s', expected 'done'" % (first["id"], first["status"]))

    return ok("%d task(s) planned, task %s done, no dependency cycle" % (len(tasks), first["id"]))


def gate_built(game):
    tasks, err = load_tasks(game)
    if err:
        return fail(err)

    for task in tasks:
        brief = task["path"]
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

    return ok("%d task(s) done, and rojo, selene and stylua all pass" % len(tasks))


# ---------------------------------------------------------------------- main

GATES = {
    "spec_parsed": gate_spec_parsed,
    "economy_tuned": gate_economy_tuned,
    "planned": gate_planned,
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

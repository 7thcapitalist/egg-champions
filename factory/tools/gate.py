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

# Time and configured gym rebirth targets both count toward economy readiness.
# A successful build does not waive a progression miss.
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

    worlds, error = read_json(game / "config" / "worlds.json")
    if error:
        return fail(error)
    if (not isinstance(worlds, list) or not worlds or
            any(not isinstance(w, dict) or type(w.get("index")) is not int
                or w["index"] < 1 for w in worlds)):
        return fail("world config must contain positive integer gym indexes")
    indexes = [w["index"] for w in worlds]
    if len(set(indexes)) != len(indexes):
        return fail("world config contains duplicate gym indexes")
    required = TIME_TARGETS + tuple("Rebirths at gym %d" % i for i in sorted(indexes))
    unscored = [t for t in required if t not in targets]
    if unscored:
        return fail(
            "%s does not score: %s. The report format changed; update this gate."
            % (report.as_posix(), ", ".join(unscored))
        )

    missed = [
        "%s is %s" % (t, targets[t]) for t in required if targets[t] != "MET"
    ]
    if missed:
        return fail("economy targets missed: " + "; ".join(missed))

    return ok("all %d time and rebirth targets met" % len(required))


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

    research_path = game / "design/feature-research.json"
    if research_path.exists():
        import feature_research
        research, err = read_json(research_path)
        if err:
            return fail(err)
        errors = feature_research.check(game, research)
        if errors:
            return fail("feature research: " + errors[0])

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
        ("run_tests", [sys.executable, "-B", str(Path(__file__).with_name("run_tests.py")), game.as_posix()]),
        ("rojo", ["rojo", "build", game.as_posix(), "-o", (out / "game.rbxl").as_posix()]),
        ("selene", ["selene", (game / "src").as_posix()]),
        ("stylua", ["stylua", "--check", (game / "src").as_posix()]),
    ]
    for name, cmd in checks:
        exe = cmd[0] if name == "run_tests" else shutil.which(cmd[0])
        if exe is None:
            return fail("%s is not on PATH" % name)
        done = subprocess.run([exe] + cmd[1:], capture_output=True, text=True)
        if done.returncode != 0:
            lines = (done.stdout + "\n" + done.stderr).strip().splitlines()
            reason = next((line for line in lines if line.startswith("FAIL")), None)
            if reason is None:
                reason = next((line for line in lines if line.startswith("run_tests:")), None)
            return fail(
                "%s failed: %s"
                % (name, reason or (lines[-1] if lines else "exit code %d" % done.returncode))
            )

    return ok("%d task(s) done, and run_tests, rojo, selene and stylua all pass" % len(tasks))


# --------------------------------------------------------------------- assets


def maps_path(node, target):
    """True when a Rojo project tree maps `target` somewhere."""
    if not isinstance(node, dict):
        return False
    if node.get("$path") == target:
        return True
    return any(maps_path(v, target) for k, v in node.items() if not k.startswith("$"))


def positive_size(size):
    return (
        isinstance(size, list)
        and len(size) == 3
        and all(isinstance(n, (int, float)) and not isinstance(n, bool) and n > 0 for n in size)
    )


def verified_model(result, model):
    if not result.get("ok"):
        return False
    if "parts" not in result:
        return "parts" not in model and positive_size(result.get("mesh_size"))
    expected = model.get("parts", [{"name": "Mesh", "mesh_id": model["mesh_id"],
                                    "texture_id": model["texture_id"]}])
    actual = result["parts"]
    return (isinstance(actual, list) and len(actual) == len(expected) and len(actual) > 0
            and all(isinstance(got, dict) and got.get("ok") and got.get("mesh_ok")
                    and positive_size(got.get("mesh_size"))
                    and got.get("texture_status") == "Success"
                    and got.get("name") == want["name"]
                    and str(got.get("mesh_id")) == str(want["mesh_id"])
                    and str(got.get("texture_id")) == str(want["texture_id"])
                    for got, want in zip(actual, expected)))


def gate_assets(game):
    assets = game / "assets"
    manifest_path = assets / "manifest.json"
    models_path = assets / "models.json"
    verify_path = assets / "verify.json"
    for path, hint in (
        (manifest_path, "the asset manifest"),
        (models_path, "Run factory/tools/build_models.py."),
        (verify_path, "Run factory/tools/verify_assets.py."),
    ):
        if not path.is_file():
            return fail("no %s. %s" % (path.as_posix(), hint))

    models_bytes = models_path.read_bytes()
    models, err = read_json(models_path)
    if err:
        return fail(err)
    entries = models.get("entries") if isinstance(models, dict) else None
    if not isinstance(entries, list):
        return fail("%s has no 'entries' list" % models_path.as_posix())
    by_id = {e.get("id"): e for e in entries if isinstance(e, dict)}

    pets, err = read_json(game / "config" / "pets.json")
    if err:
        return fail(err)
    eggs, err = read_json(game / "config" / "eggs.json")
    if err:
        return fail(err)
    wanted = [(p["id"], "pet") for p in pets] + [(e["id"], "egg") for e in eggs]
    for item_id, kind in wanted:
        entry = by_id.get(item_id)
        if entry is None or entry.get("kind") != kind:
            return fail("%s %s has no entry in %s" % (kind, item_id, models_path.as_posix()))

    current = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    if models.get("manifest_sha256") != current:
        return fail(
            "%s is stale: the manifest changed since it was built. Rerun build_models.py."
            % models_path.as_posix()
        )

    project, err = read_json(game / "default.project.json")
    if err:
        return fail(err)
    if not maps_path(project.get("tree"), "assets/models.json"):
        return fail("default.project.json does not map assets/models.json")

    verify, err = read_json(verify_path)
    if err:
        return fail(err)
    if verify.get("models_sha256") != hashlib.sha256(models_bytes).hexdigest():
        return fail(
            "%s checked a different models.json. Rerun verify_assets.py." % verify_path.as_posix()
        )
    results = {r.get("id"): r for r in verify.get("entries") or [] if isinstance(r, dict)}
    for item_id, _kind in wanted:
        result = results.get(item_id)
        if result is None:
            return fail("%s has no result for %s" % (verify_path.as_posix(), item_id))
        model = next(e for e in models["entries"] if e["id"] == item_id)
        if not verified_model(result, model):
            return fail(
                "%s: %s is not ok (%s)"
                % (verify_path.as_posix(), item_id, result.get("error") or result.get("texture_status"))
            )

    out = game / "build"
    exe = shutil.which("rojo")
    if exe is None:
        return fail("rojo is not on PATH")
    out.mkdir(parents=True, exist_ok=True)
    done = subprocess.run(
        [exe, "build", game.as_posix(), "-o", (out / "game.rbxl").as_posix()],
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        lines = (done.stderr or done.stdout or "").strip().splitlines()
        return fail("rojo failed: %s" % (lines[0] if lines else "exit code %d" % done.returncode))

    return ok("%d models current, mapped, built and verified on Roblox" % len(wanted))


# ---------------------------------------------------------------------- main

GATES = {
    "spec_parsed": gate_spec_parsed,
    "economy_tuned": gate_economy_tuned,
    "planned": gate_planned,
    "built": gate_built,
    "assets": gate_assets,
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

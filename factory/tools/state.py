#!/usr/bin/env python3
"""Factory tool: read and write one game's state file.

Usage:
    python factory/tools/state.py show <game-dir>
    python factory/tools/state.py set <game-dir> <stage> <status> [--note TEXT]
    python factory/tools/state.py next <game-dir>
    python factory/tools/state.py task <game-dir> <task-id> awaiting_windows

`task ... awaiting_windows` records, in `<game-dir>/tasks/index.json`, that a
running or blocked task has its code done and waits only on Windows checks
(Studio, TEST place, physical phone). It is never used to send a task back
to pending; run_factory.py owns every other task status.

`<game-dir>/state.json` is the single record of progress for one game.
`gate.py` decides whether a stage passes; this tool only records the answer,
so a stage is never marked passed by the same code that wants it passed.

`next` prints the first stage that is not passed, and nothing at all once
every stage has passed, so callers can read one stage id off stdout.
Standard library only.
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

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

STATUSES = ["pending", "running", "passed", "failed", "blocked"]


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def path_for(game_dir):
    return Path(game_dir) / "state.json"


def load(game_dir):
    path = path_for(game_dir)
    if not path.is_file():
        sys.exit("no state file at %s" % path.as_posix())
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as err:
        sys.exit("%s is not valid JSON: %s" % (path.as_posix(), err))
    if not isinstance(data, dict) or not isinstance(data.get("stages"), list):
        sys.exit("%s needs an object with a 'stages' list" % path.as_posix())
    ids = [s.get("id") for s in data["stages"] if isinstance(s, dict)]
    missing = [s for s in STAGES if s not in ids]
    if missing:
        sys.exit("%s is missing stages: %s" % (path.as_posix(), ", ".join(missing)))
    unknown = [str(i) for i in ids if i not in STAGES]
    if unknown:
        sys.exit("%s has unknown stages: %s" % (path.as_posix(), ", ".join(unknown)))
    return data


def save(game_dir, data):
    path_for(game_dir).write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def find(data, stage):
    for s in data["stages"]:
        if s.get("id") == stage:
            return s
    sys.exit("no stage '%s' in the state file" % stage)


def game_name(data, game_dir):
    return data.get("game") or Path(game_dir).name


def cmd_show(a):
    data = load(a.game_dir)
    print(game_name(data, a.game_dir))
    head = ("stage", "status", "attempts", "updated", "note")
    rows = [
        (
            s["id"],
            str(s.get("status") or "pending"),
            str(s.get("attempts") or 0),
            str(s.get("updated") or "never"),
            str(s.get("note") or ""),
        )
        for s in sorted(data["stages"], key=lambda s: STAGES.index(s["id"]))
    ]
    table = (head,) + tuple(rows)
    width = [max(len(r[i]) for r in table) for i in range(len(head))]
    for r in table:
        print("  " + "  ".join(c.ljust(width[i]) for i, c in enumerate(r)).rstrip())
    return 0


def cmd_set(a):
    data = load(a.game_dir)
    stage = find(data, a.stage)
    stage["status"] = a.status
    # attempts counts runs, so it rises when a stage starts, not when it ends.
    if a.status == "running":
        stage["attempts"] = int(stage.get("attempts") or 0) + 1
    if a.note is not None:
        stage["note"] = a.note
    stage["updated"] = now()
    save(a.game_dir, data)
    print("%s %s -> %s" % (game_name(data, a.game_dir), a.stage, a.status))
    return 0


def cmd_next(a):
    data = load(a.game_dir)
    for stage_id in STAGES:
        if find(data, stage_id).get("status") != "passed":
            print(stage_id)
            return 0
    print("all stages passed", file=sys.stderr)
    return 0


TASK_FROM = ("running", "blocked")


def cmd_task(a):
    path = Path(a.game_dir) / "tasks" / "index.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data["tasks"] if isinstance(data, dict) else data
    entry = next((e for e in entries if isinstance(e, dict) and str(e.get("id")) == a.task_id), None)
    if entry is None:
        print("task %s is not in %s" % (a.task_id, path.as_posix()), file=sys.stderr)
        return 2
    current = entry.get("status") or "pending"
    if current == a.status:
        print("task %s already %s" % (a.task_id, a.status))
        return 0
    if current not in TASK_FROM:
        print("task %s is %s; only %s can become %s" % (a.task_id, current, "/".join(TASK_FROM), a.status),
              file=sys.stderr)
        return 2
    entry["status"] = a.status
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("task %s %s -> %s" % (a.task_id, current, a.status))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Read and write one game's state file")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("show", help="print every stage")
    p.add_argument("game_dir")
    p.set_defaults(fn=cmd_show)

    p = sub.add_parser("set", help="record a stage's status")
    p.add_argument("game_dir")
    p.add_argument("stage", choices=STAGES)
    p.add_argument("status", choices=STATUSES)
    p.add_argument("--note", default=None, help="why it is in this status")
    p.set_defaults(fn=cmd_set)

    p = sub.add_parser("task", help="mark a task's code done, waiting on Windows checks")
    p.add_argument("game_dir")
    p.add_argument("task_id")
    p.add_argument("status", choices=["awaiting_windows"])
    p.set_defaults(fn=cmd_task)

    p = sub.add_parser("next", help="print the first stage that is not passed")
    p.add_argument("game_dir")
    p.set_defaults(fn=cmd_next)

    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())

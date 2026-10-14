"""Shared helpers for the factory's Roblox Open Cloud tools.

Luau Execution (create.roblox.com/docs/cloud/reference/features/luau-execution):
- create a task: POST /cloud/v2/universes/{u}/places/{p}/luau-execution-session-tasks
  with {"script", "timeout"}; scope universe.place.luau-execution-session:write
- read it back: GET /cloud/v2/{task path}; scope ...:read or ...:write
- limits: 5 minute run time, 4 MB script, 4 MB of returned JSON, 5 task
  creations per minute per key owner, 10 unfinished tasks per place, task
  kept 24 hours.

Place publishing (create.roblox.com/docs/cloud/guides/usage-place-publishing):
- POST https://apis.roblox.com/universes/v1/{u}/places/{p}/versions?versionType=Published
  with the .rbxl as application/octet-stream; scope universe-places:write;
  30 requests per minute per key owner.

The API key comes only from the environment variable that roblox.json names
in `api_key_secret`. Nothing here reads a file for it, and nothing here
prints it. Every call targets the test place; the production ids in
roblox.json are only read to refuse them.

Long waits are split across runs: a task's path is saved to a pending file,
so a caller cut short (a 45 second shell) runs the tool again and it picks up
the same task instead of starting another. Standard library only.
"""
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://apis.roblox.com/cloud/v2/"
TASK_TIMEOUT = "300s"  # the documented maximum run time
POLL_SECONDS = 3
DONE_STATES = ("COMPLETE", "FAILED", "CANCELLED")


class CloudError(Exception):
    pass


def test_place(game):
    """Return (universe_id, place_id, secret_name) for the game's test place."""
    data = json.loads((Path(game) / "roblox.json").read_text(encoding="utf-8"))
    test, prod = data["test"], data.get("production") or {}
    universe, place = int(test["universe_id"]), int(test["place_id"])
    if universe == int(prod.get("universe_id") or 0) or place == int(prod.get("place_id") or 0):
        raise CloudError("roblox.json's test ids match production; refusing to run")
    return universe, place, data["api_key_secret"]


def api_key(secret_name):
    key = os.environ.get(secret_name)
    if not key:
        raise CloudError(
            "the environment variable %s is not set. Load the gitignored .env into "
            "the environment first (for example `set -a; . ./.env; set +a`)." % secret_name
        )
    return key


def call(method, url, key, body=None, raw=None, content_type=None, timeout=30):
    """Make one request and return its JSON (or {"text": ...} if not JSON).

    `body` is sent as JSON; `raw` is sent as bytes with `content_type`. An
    HTTP error raises CloudError with the status and the start of the body.
    The key goes only into the x-api-key header and is never in a message.
    """
    if raw is not None:
        data = raw
    else:
        data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("x-api-key", key)
    if data is not None:
        req.add_header("Content-Type", content_type or "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8", "replace")
            try:
                return json.loads(text or "{}")
            except ValueError:
                return {"text": text}
    except urllib.error.HTTPError as err:
        text = err.read().decode("utf-8", "replace")[:600]
        raise CloudError("HTTP %d from %s %s: %s" % (err.code, method, url, text)) from None
    except urllib.error.URLError as err:
        raise CloudError("cannot reach %s: %s" % (url, err.reason)) from None


def create_task(universe, place, key, script):
    url = "%suniverses/%d/places/%d/luau-execution-session-tasks" % (BASE, universe, place)
    task = call("POST", url, key, {"script": script, "timeout": TASK_TIMEOUT})
    if not task.get("path"):
        raise CloudError("the create call returned no task path")
    return task


def get_task(path, key):
    return call("GET", BASE + path, key)


def task_logs(path, key):
    try:
        data = call("GET", BASE + path + "/logs?maxPageSize=200", key)
    except CloudError:
        return []
    lines = []
    for chunk in data.get("luauExecutionSessionTaskLogs", []):
        lines.extend(chunk.get("messages", []))
    return lines


def run(pending_file, fingerprint, universe, place, key, script, wait_seconds):
    """Run a script as a task, resuming a pending one with the same fingerprint.

    Returns the finished task, or None when it is still running after
    wait_seconds (the pending file then keeps its path for the next run).
    """
    pending_file = Path(pending_file)
    path = None
    if pending_file.is_file():
        try:
            saved = json.loads(pending_file.read_text(encoding="utf-8"))
            if saved.get("fingerprint") == fingerprint:
                path = saved.get("path")
        except ValueError:
            path = None
    if path is None:
        task = create_task(universe, place, key, script)
        path = task["path"]
        pending_file.parent.mkdir(parents=True, exist_ok=True)
        pending_file.write_text(
            json.dumps({"fingerprint": fingerprint, "path": path}) + "\n", encoding="utf-8"
        )
        print("started task %s" % path)
    else:
        print("resuming task %s" % path)

    deadline = time.monotonic() + wait_seconds
    while True:
        task = get_task(path, key)
        if task.get("state") in DONE_STATES:
            # Cleared rather than deleted: some synced folders refuse deletes.
            pending_file.write_text("{}\n", encoding="utf-8")
            return task
        if time.monotonic() >= deadline:
            print("task %s is %s; run again to keep waiting" % (path, task.get("state")))
            return None
        time.sleep(POLL_SECONDS)


def returned(task):
    """The first value the task's script returned, or None."""
    results = (task.get("output") or {}).get("results") or []
    return results[0] if results else None

#!/usr/bin/env python3
"""Factory tool: check every model in a game's model table on Roblox itself.

Usage:
    python factory/tools/verify_assets.py <game-dir> [--wait SECONDS]

Starts an Open Cloud Luau Execution task on the game's TEST place (ids from
<game-dir>/roblox.json). The task calls AssetService:CreateMeshPartAsync for
every entry in <game-dir>/assets/models.json and preloads each texture with
ContentProvider:PreloadAsync, and returns, per id: whether the mesh loaded or
its error, its MeshSize, and the texture's fetch status.

Writes <game-dir>/assets/verify.json with those results, the time, and the
sha256 of the models.json it checked, then exits 0 when every entry is ok:
the mesh loaded with a MeshSize above zero on every axis and the texture
loaded. Exits 1 otherwise, or on any error. Exits 2 when the task is still
running after --wait seconds (default 290); run it again and it resumes the
same task (its path is kept in <game-dir>/build/verify-task.json).

--if-stale skips the check, and exits 0, when verify.json already covers this
exact models.json with every entry ok, so CI reruns change nothing.

The API key is read only from the environment variable named by
`api_key_secret` in roblox.json. Load .env into the environment before
running; this tool never opens it. Standard library only.
"""
import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import opencloud  # noqa: E402  lives next to this file

SCRIPT = r"""
local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")

local entries = HttpService:JSONDecode([==[%s]==])
local results = {}
for _, entry in entries do
	local result = { id = entry.id }
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync("rbxassetid://" .. entry.mesh)
	end)
	if ok and part ~= nil then
		result.mesh_ok = true
		result.mesh_size = { part.MeshSize.X, part.MeshSize.Y, part.MeshSize.Z }
		part:Destroy()
	else
		result.mesh_ok = false
		result.error = tostring(part)
	end
	local status = "None"
	local loaded, err = pcall(function()
		ContentProvider:PreloadAsync({ "rbxassetid://" .. entry.texture }, function(_, fetch)
			status = fetch.Name
		end)
	end)
	result.texture_status = if loaded then status else ("error: " .. tostring(err))
	table.insert(results, result)
end
return { results = results }
"""


def judge(result):
    size = result.get("mesh_size") or []
    mesh = bool(result.get("mesh_ok")) and len(size) == 3 and all(
        isinstance(n, (int, float)) and n > 0 for n in size
    )
    texture = result.get("texture_status") == "Success"
    result["texture_loaded"] = texture
    result["ok"] = mesh and texture
    return result


def current_and_ok(game, models_path):
    try:
        report = json.loads((game / "assets" / "verify.json").read_text(encoding="utf-8"))
        digest = hashlib.sha256(models_path.read_bytes()).hexdigest()
    except (OSError, ValueError):
        return False
    entries = report.get("entries") or []
    return (
        report.get("models_sha256") == digest
        and len(entries) > 0
        and all(e.get("ok") for e in entries)
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("game_dir")
    parser.add_argument("--wait", type=float, default=290)
    parser.add_argument("--if-stale", action="store_true")
    args = parser.parse_args(argv)
    game = Path(args.game_dir)
    models_path = game / "assets" / "models.json"

    if args.if_stale and current_and_ok(game, models_path):
        print("verify_assets: verify.json already covers this models.json, all ok; skipped")
        return 0

    try:
        raw = models_path.read_bytes()
        table = json.loads(raw.decode("utf-8"))
        universe, place, secret = opencloud.test_place(game)
        key = opencloud.api_key(secret)
    except (OSError, ValueError, KeyError, opencloud.CloudError) as err:
        print("verify_assets: %s" % err)
        return 1

    digest = hashlib.sha256(raw).hexdigest()
    payload = [
        {"id": e["id"], "mesh": str(e["mesh_id"]), "texture": str(e["texture_id"])}
        for e in table["entries"]
    ]
    script = SCRIPT % json.dumps(payload)
    try:
        task = opencloud.run(
            game / "build" / "verify-task.json", digest, universe, place, key, script, args.wait
        )
    except opencloud.CloudError as err:
        print("verify_assets: %s" % err)
        return 1
    if task is None:
        return 2
    if task.get("state") != "COMPLETE":
        print("verify_assets: task ended %s: %s" % (task.get("state"), json.dumps(task.get("error"))))
        for line in opencloud.task_logs(task["path"], key)[-10:]:
            print("  log: %s" % line)
        return 1

    value = opencloud.returned(task) or {}
    results = [judge(r) for r in value.get("results") or []]
    returned_ids = [r.get("id") for r in results]
    for e in table["entries"]:
        if e["id"] not in returned_ids:
            results.append({"id": e["id"], "ok": False, "error": "no result returned"})

    report = {
        "checked": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "models_sha256": digest,
        "universe_id": universe,
        "place_id": place,
        "task": task["path"],
        "ok": sum(1 for r in results if r["ok"]),
        "total": len(results),
        "entries": results,
    }
    out = game / "assets" / "verify.json"
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    for r in results:
        if not r["ok"]:
            print(
                "verify_assets: %s not ok: mesh %s, size %s, texture %s%s"
                % (
                    r["id"],
                    "ok" if r.get("mesh_ok") else "failed",
                    r.get("mesh_size"),
                    r.get("texture_status"),
                    (", " + r["error"]) if r.get("error") else "",
                )
            )
    print("verify_assets: %d of %d ok; wrote %s" % (report["ok"], report["total"], out.as_posix()))
    return 0 if report["ok"] == report["total"] and report["total"] > 0 else 1


if __name__ == "__main__":
    sys.exit(main())

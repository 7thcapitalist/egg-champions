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
    local result = { id = entry.id, parts = {} }
    for _, piece in entry.parts do
        local item = { name = piece.name, mesh_id = piece.mesh_id, texture_id = piece.texture_id }
        local ok, part = pcall(function()
            return AssetService:CreateMeshPartAsync("rbxassetid://" .. piece.mesh_id)
        end)
        item.mesh_ok = ok and part ~= nil
        if item.mesh_ok then
            item.mesh_size = {part.MeshSize.X, part.MeshSize.Y, part.MeshSize.Z}
            part:Destroy()
        else item.error = tostring(part) end
        local status = "None"
        local loaded, err = pcall(function()
            ContentProvider:PreloadAsync({"rbxassetid://" .. piece.texture_id}, function(_, fetch)
                status = fetch.Name
            end)
        end)
        item.texture_status = if loaded then status else ("error: " .. tostring(err))
        table.insert(result.parts, item)
    end
    table.insert(results, result)
    task.wait()
end
return { results = results }
"""


def judge(result):
    if "parts" in result:
        pieces = [judge(piece) for piece in result["parts"]]
        result["mesh_ok"] = bool(pieces) and all(p["mesh_ok"] for p in pieces)
        result["texture_loaded"] = bool(pieces) and all(p["texture_loaded"] for p in pieces)
        result["texture_status"] = "Success" if result["texture_loaded"] else "Failure"
        result["ok"] = bool(pieces) and all(p["ok"] for p in pieces)
        return result
    size = result.get("mesh_size") or []
    mesh = bool(result.get("mesh_ok")) and len(size) == 3 and all(
        isinstance(n, (int, float)) and n > 0 for n in size
    )
    texture = result.get("texture_status") == "Success"
    result["texture_loaded"] = texture
    result["ok"] = mesh and texture
    return result


def payload_for(table):
    return [{"id": e["id"], "parts": [
        {"name": p["name"], "mesh_id": str(p["mesh_id"]), "texture_id": str(p["texture_id"])}
        for p in e.get("parts", [{"name": "Mesh", "mesh_id": e["mesh_id"], "texture_id": e["texture_id"]}])
    ]} for e in table["entries"]]


def checked_results(table, returned):
    by_id = {r.get("id"): r for r in returned}
    results = []
    for expected in payload_for(table):
        result = by_id.get(expected["id"], {"id": expected["id"], "parts": []})
        actual = [{"name": p.get("name"), "mesh_id": str(p.get("mesh_id")), "texture_id": str(p.get("texture_id"))}
                  for p in result.get("parts", [])]
        judge(result)
        if actual != expected["parts"]:
            result["ok"] = False
            result["error"] = "returned mesh pieces do not match the current model table"
        results.append(result)
    return results


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
    parser.add_argument("--studio-results", help="import recorded Studio verification with digest and target IDs")
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
        key = opencloud.api_key(secret) if not args.studio_results else None
    except (OSError, ValueError, KeyError, opencloud.CloudError) as err:
        print("verify_assets: %s" % err)
        return 1

    digest = hashlib.sha256(raw).hexdigest()
    payload = payload_for(table)
    if args.studio_results:
        try:
            recorded = json.loads(Path(args.studio_results).read_text(encoding="utf-8"))
            if (recorded.get("models_sha256") != digest
                    or recorded.get("place_id") != place
                    or recorded.get("universe_id") != universe):
                raise ValueError("Studio evidence hash or TEST target does not match")
            results = checked_results(table, recorded["results"])
            task_path = "studio:" + recorded["studio_id"]
        except (OSError, ValueError, KeyError, TypeError) as err:
            print("verify_assets: %s" % err)
            return 1
    else:
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
        results = checked_results(table, value.get("results") or [])
        task_path = task["path"]

    report = {
        "checked": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "models_sha256": digest,
        "universe_id": universe,
        "place_id": place,
        "task": task_path,
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

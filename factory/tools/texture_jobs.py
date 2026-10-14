#!/usr/bin/env python3
"""Factory tool: save textures that exist only as EditableImages as real assets.

Usage:
    python factory/tools/texture_jobs.py <game-dir> [--wait SECONDS]

Reads <game-dir>/assets/texture_jobs.json, a list of jobs:

    {"id": "moranguete",
     "source": "workspace.MorangueteFix.RepaintNewface_source",
     "return_edit": "partB.TextureContent=Content.fromObject(imgB)",
     "name": "Moranguete face texture"}

`source` is a StringValue in the game's TEST place holding a Luau snippet
that paints an EditableImage named imgB. A job runs only while its manifest
entry has `needs_texture_save`, so a rerun after success does nothing.

For each such job, one Open Cloud Luau Execution task on the TEST place:
- reads the snippet from `source`;
- replaces the line `return_edit` with that line plus `return imgB`, and
  runs the result with loadstring;
- calls AssetService:CreateAssetAsync(imgB, Enum.AssetType.Image, {Name,
  CreatorId = game.CreatorId, CreatorType = User}) and returns the new id.

The id goes into the manifest entry's texture_asset_id, needs_texture_save
is dropped, the notes say where the texture came from, and build_models.py
reruns. On any error the HTTP status and body (never the key) are printed
and the tool exits 1. The API key comes only from the environment variable
roblox.json names. Standard library only.
"""
import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import opencloud  # noqa: E402  lives next to this file

# The JSON arguments are decoded inside the task, so no snippet text or path
# is ever spliced into Luau source.
SCRIPT = r"""
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local job = HttpService:JSONDecode([==[%s]==])

if game.CreatorType ~= Enum.CreatorType.User then
	error("the place's creator is not a user; CreatorId cannot be read from the place")
end

local node: Instance = game
for name in string.gmatch(job.source, "[^%%.]+") do
	if name == "game" then
		continue
	end
	if node == game and name == "workspace" then
		node = workspace
	else
		local child = node:FindFirstChild(name)
		if child == nil then
			error("no " .. name .. " under " .. node:GetFullName())
		end
		node = child
	end
end
if not node:IsA("StringValue") then
	error(job.source .. " is a " .. node.ClassName .. ", not a StringValue")
end

local snippet = (node :: StringValue).Value
local first, last = string.find(snippet, job.return_edit, 1, true)
if first == nil then
	error("the snippet has no line " .. job.return_edit)
end
snippet = string.sub(snippet, 1, last) .. "\nreturn imgB\n" .. string.sub(snippet, last + 1)

if loadstring == nil then
	error("loadstring is not available in this task")
end
local chunk, compileError = loadstring(snippet)
if chunk == nil then
	error("the edited snippet does not compile: " .. tostring(compileError))
end
local imgB = chunk()
if typeof(imgB) ~= "Object" and typeof(imgB) ~= "Instance" then
	error("the snippet returned " .. typeof(imgB) .. ", not an EditableImage")
end

local result, assetId = AssetService:CreateAssetAsync(imgB, Enum.AssetType.Image, {
	Name = job.name,
	CreatorId = game.CreatorId,
	CreatorType = Enum.AssetCreatorType.User,
})
return { result = tostring(result), asset_id = tostring(assetId) }
"""


def run_job(game, job, universe, place, key, wait):
    payload = {
        "source": job["source"],
        "return_edit": job["return_edit"],
        "name": job.get("name") or job["id"],
    }
    script = SCRIPT % json.dumps(payload)
    task = opencloud.run(
        game / "build" / ("texture-job-%s.json" % job["id"]),
        json.dumps(payload, sort_keys=True),
        universe,
        place,
        key,
        script,
        wait,
    )
    if task is None:
        raise opencloud.CloudError("task still running after %d seconds" % wait)
    if task.get("state") != "COMPLETE":
        logs = opencloud.task_logs(task["path"], key)[-10:]
        raise opencloud.CloudError(
            "task ended %s: %s%s"
            % (task.get("state"), json.dumps(task.get("error")), "".join("\n  log: " + l for l in logs))
        )
    value = opencloud.returned(task) or {}
    asset_id = str(value.get("asset_id") or "")
    if not asset_id.isdigit() or int(asset_id) <= 0:
        raise opencloud.CloudError(
            "CreateAssetAsync returned %s with id %r" % (value.get("result"), value.get("asset_id"))
        )
    return int(asset_id)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("game_dir")
    parser.add_argument("--wait", type=float, default=290)
    args = parser.parse_args(argv)
    game = Path(args.game_dir)
    jobs_path = game / "assets" / "texture_jobs.json"
    manifest_path = game / "assets" / "manifest.json"

    try:
        jobs = json.loads(jobs_path.read_text(encoding="utf-8")) if jobs_path.is_file() else []
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print("texture_jobs: %s" % err)
        return 1
    entries = {e.get("id"): e for e in manifest.get("entries", [])}

    pending = []
    for job in jobs:
        missing = [k for k in ("id", "source", "return_edit") if not job.get(k)]
        if missing:
            print("texture_jobs: a job lacks %s" % ", ".join(missing))
            return 1
        entry = entries.get(job["id"])
        if entry is None:
            print("texture_jobs: %s is not in the manifest" % job["id"])
            return 1
        if entry.get("needs_texture_save"):
            pending.append(job)
    if not pending:
        print("texture_jobs: nothing pending")
        return 0

    try:
        universe, place, secret = opencloud.test_place(game)
        key = opencloud.api_key(secret)
    except (OSError, ValueError, KeyError, opencloud.CloudError) as err:
        print("texture_jobs: %s" % err)
        return 1

    for job in pending:
        try:
            asset_id = run_job(game, job, universe, place, key, args.wait)
        except opencloud.CloudError as err:
            print("texture_jobs: %s failed: %s" % (job["id"], err))
            return 1
        entry = entries[job["id"]]
        entry["texture_asset_id"] = "rbxassetid://%d" % asset_id
        entry.pop("needs_texture_save", None)
        entry["status"] = "ready"
        entry["notes"] = "Texture %d saved by factory/tools/texture_jobs.py from %s on %s." % (
            asset_id,
            job["source"],
            date.today().isoformat(),
        )
        manifest["updated"] = date.today().isoformat()
        # Written after each job, so a later failure keeps the ids already made.
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print("texture_jobs: %s texture saved as %d" % (job["id"], asset_id))

    build = Path(__file__).resolve().parent / "build_models.py"
    return subprocess.run([sys.executable, str(build), str(game)]).returncode


if __name__ == "__main__":
    sys.exit(main())

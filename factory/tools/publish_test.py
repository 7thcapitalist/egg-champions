#!/usr/bin/env python3
"""Factory tool: build a game and publish it to its TEST place.

Usage:
    python factory/tools/publish_test.py <game-dir>

Refuses when roblox.json's test ids equal its production ids, and while any
texture job in <game-dir>/assets/texture_jobs.json is still pending
(publishing replaces the test place's content, which holds the snippet a
pending job reads). Then builds <game-dir>/build/game.rbxl with rojo and
publishes it through Open Cloud place publishing
(create.roblox.com/docs/cloud/guides/usage-place-publishing):

    POST https://apis.roblox.com/universes/v1/{universe}/places/{place}/versions?versionType=Published
    Content-Type: application/octet-stream, the .rbxl as the body
    API key scope: universe-places:write

Prints the new version number. On an error it prints the HTTP status and
body (never the key) and exits 1. Only the test place is ever named here.
The API key comes only from the environment variable roblox.json names.
Standard library only.
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import opencloud  # noqa: E402  lives next to this file

PUBLISH_URL = "https://apis.roblox.com/universes/v1/%d/places/%d/versions?versionType=Published"


def pending_jobs(game):
    jobs_path = game / "assets" / "texture_jobs.json"
    if not jobs_path.is_file():
        return []
    jobs = json.loads(jobs_path.read_text(encoding="utf-8"))
    manifest = json.loads((game / "assets" / "manifest.json").read_text(encoding="utf-8"))
    waiting = {e.get("id") for e in manifest.get("entries", []) if e.get("needs_texture_save")}
    return [j["id"] for j in jobs if j.get("id") in waiting]


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        sys.exit(__doc__)
    game = Path(argv[0])
    try:
        universe, place, secret = opencloud.test_place(game)
        waiting = pending_jobs(game)
    except (OSError, ValueError, KeyError, opencloud.CloudError) as err:
        print("publish_test: %s" % err)
        return 1
    if waiting:
        print(
            "publish_test: refusing: texture job(s) still pending (%s). Publishing would "
            "replace the place content they read. Run texture_jobs.py first." % ", ".join(waiting)
        )
        return 1
    try:
        key = opencloud.api_key(secret)
    except opencloud.CloudError as err:
        print("publish_test: %s" % err)
        return 1

    rojo = shutil.which("rojo")
    if rojo is None:
        print("publish_test: rojo is not on PATH")
        return 1
    out = game / "build" / "game.rbxl"
    out.parent.mkdir(parents=True, exist_ok=True)
    built = subprocess.run([rojo, "build", str(game), "-o", str(out)])
    if built.returncode != 0:
        print("publish_test: rojo build failed")
        return 1

    # Roblox answers 409 "Server is busy" while the place is open in Studio
    # or another save is running, and 429 when rate limited. Both pass.
    attempts = 6
    for attempt in range(1, attempts + 1):
        try:
            reply = opencloud.call(
                "POST",
                PUBLISH_URL % (universe, place),
                key,
                raw=out.read_bytes(),
                content_type="application/octet-stream",
                timeout=300,
            )
            break
        except opencloud.CloudError as err:
            busy = "HTTP 409" in str(err) or "HTTP 429" in str(err)
            if not busy or attempt == attempts:
                print("publish_test: %s" % err)
                if busy:
                    print("publish_test: still busy; close the place in Studio and run again")
                return 1
            print("publish_test: busy (try %d of %d), waiting 60 seconds" % (attempt, attempts))
            time.sleep(60)
    version = reply.get("versionNumber", reply.get("text"))
    print("publish_test: published test place %d as version %s" % (place, version))
    return 0


if __name__ == "__main__":
    sys.exit(main())

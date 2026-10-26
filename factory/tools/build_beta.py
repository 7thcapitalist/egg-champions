"""Build a separate unpublished beta QA place. No AI, publication or executor.

python -B factory/tools/build_beta.py GAME NEW_OUTPUT_DIRECTORY
Open this local file in a separate Studio session; use two local clients.
The output directory must be new and inside GAME; shipping files are read only.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess

from build_playtest import source_paths


def build(game, output):
    game, output = game.resolve(), output.resolve()
    if not output.is_relative_to(game) or output == game:
        raise ValueError("new beta output must stay inside game")
    project_path = game / "default.project.json"
    project = copy.deepcopy(json.loads(project_path.read_text(encoding="utf-8")))
    rojo = shutil.which("rojo")
    if rojo is None:
        raise ValueError("rojo unavailable")
    source_paths(project, game, output)
    server = project["tree"]["ServerScriptService"]
    server.setdefault("$attributes", {}).update(BetaQA=True, PlaytestNoPasses=True)
    project["tree"]["ReplicatedStorage"].setdefault("$attributes", {})["BetaQA"] = True
    for name, filename, disabled in (
            ("BetaMultiplayer", "beta_multiplayer.server.luau", False),
            ("BetaSnapshot", "beta_snapshot.server.luau", True)):
        path = Path(__file__).with_name(filename).resolve()
        if not path.is_file():
            raise ValueError("fixture source missing: " + filename)
        if name in server:
            raise ValueError("reserved QA script already exists: " + name)
        server[name] = {"$path": os.path.relpath(path, output).replace("\\", "/"),
                        "$properties": {"Disabled": disabled}}
    starter = project["tree"].setdefault("StarterPlayer", {"$className": "StarterPlayer"})
    scripts = starter.setdefault("StarterPlayerScripts", {"$className": "StarterPlayerScripts"})
    if "BetaMobile" in scripts:
        raise ValueError("reserved QA script already exists: BetaMobile")
    scripts["BetaMobile"] = {"$path": os.path.relpath(
        Path(__file__).with_name("beta_mobile.client.luau").resolve(), output).replace("\\", "/"),
        "$properties": {"Disabled": True}}
    if "BetaMultiplayerClient" in scripts:
        raise ValueError("reserved QA script already exists: BetaMultiplayerClient")
    scripts["BetaMultiplayerClient"] = {"$path": os.path.relpath(
        Path(__file__).with_name("beta_multiplayer.client.luau").resolve(), output).replace("\\", "/"),
        "$properties": {"Disabled": False}}
    output.mkdir(parents=True, exist_ok=False)
    target = output / "beta.project.json"
    target.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    place = output / "beta-local.rbxl"
    subprocess.run([rojo, "build", str(target), "-o", str(place)], check=True, timeout=120)
    print("Local QA only: " + str(place))
    print("Requires fresh temporary profiles. Do not publish this fixture place.")
    return place


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        build(args.game, args.output)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("BLOCKED: " + str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

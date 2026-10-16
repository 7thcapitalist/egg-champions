"""Build an unpublished Studio QA place with a temporary profile scenario.

    python -B factory/tools/build_playtest.py <game-dir> beginner
    python -B factory/tools/build_playtest.py <game-dir> gym1
    python -B factory/tools/build_playtest.py <game-dir> collection

The generated Rojo project and .rbxl stay in <game>/build/playtest. The
shipping default.project.json is read, never changed. Open the resulting
.rbxl as a local file in Studio with Studio API access disabled. Do not
publish it: the injected script asserts game.PlaceId == 0 and IsStudio.
"""

import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("playtest_scenario.server.luau")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def source_paths(tree, old_dir, new_dir):
    if isinstance(tree, dict):
        for key, value in tree.items():
            if key == "$path":
                target = (old_dir / value).resolve()
                tree[key] = os.path.relpath(target, new_dir).replace("\\", "/")
            else:
                source_paths(value, old_dir, new_dir)
    elif isinstance(tree, list):
        for value in tree:
            source_paths(value, old_dir, new_dir)


def scenario_data(game, scenario):
    worlds = sorted(read_json(game / "config" / "worlds.json"), key=lambda row: row["index"])
    tuning = read_json(game / "tuning" / "gyms.json")["gyms"]
    by_world = {gym["world"]: gym for gym in tuning}
    configured_pets = read_json(game / "config" / "pets.json")
    known_pets = {pet["id"] for pet in configured_pets}
    if scenario == "beginner":
        return {"scenario": scenario}
    if scenario == "collection":
        if len(configured_pets) < 2:
            raise ValueError("collection needs at least two configured pets")
        pets = []
        index = {}
        for number, pet in enumerate(configured_pets, 1):
            pet_id = pet["id"]
            pets.append({"uid": "qa-normal-%d" % number, "petId": pet_id})
            index[pet_id] = {"normal": True}
        for variant, pet in zip(("shiny", "golden"), configured_pets[:2]):
            pets.append({"uid": "qa-" + variant, "petId": pet["id"], "variant": variant})
            index[pet["id"]][variant] = True
        team_size = read_json(game / "config" / "constants.json")["team_size"]
        return {
            "scenario": scenario,
            "coins": 0,
            "rebirths": 0,
            "pets": pets,
            "team": [pet["uid"] for pet in pets[:team_size]],
            "index": index,
            "badges": {},
            "gymsBeaten": {},
            "tutorialStep": 5,
        }
    if scenario == "portals":
        prior_worlds = {world["id"]: True for world in worlds[:-1]}
        return {
            "scenario": scenario,
            "coins": 0,
            "rebirths": 0,
            "pets": [],
            "team": [],
            "index": {},
            "badges": {},
            "gymsBeaten": {},
            "unlockWorlds": prior_worlds,
            "tutorialStep": 5,
        }

    gym_index = int(scenario[-1])
    if gym_index > len(worlds) or gym_index < 1:
        raise ValueError("scenario has no matching world")
    world = worlds[gym_index - 1]
    gym = by_world[world["id"]]
    references = gym["reference_team"]
    if len(references) != read_json(game / "config" / "constants.json")["team_size"]:
        raise ValueError("tuned reference team does not fill the configured team")
    pets = []
    team = []
    index = {}
    for number, reference in enumerate(references, 1):
        pet_id = reference["pet"]
        if pet_id not in known_pets:
            raise ValueError("unknown reference pet: " + pet_id)
        uid = "qa-%s-%d" % (scenario, number)
        pets.append({"uid": uid, "petId": pet_id, "variant": "golden"})
        team.append(uid)
        index[pet_id] = {"golden": True}
    beaten = {prior["id"]: True for prior in worlds[: gym_index - 1]}
    return {
        "scenario": scenario,
        "worldId": world["id"],
        "coins": world["gym"]["fee"] * 2,
        "rebirths": gym["target_rebirths"] + 1,
        "pets": pets,
        "team": team,
        "index": index,
        "badges": beaten,
        "gymsBeaten": beaten,
        "tutorialStep": 4,
    }


def build(game, scenario, output_name=None):
    game = game.resolve()
    project_path = game / "default.project.json"
    if not project_path.is_file() or not SCRIPT.is_file():
        raise ValueError("game project or fixture script is missing")
    data = scenario_data(game, scenario)
    output_dir = game / "build" / "playtest"
    output_dir.mkdir(parents=True, exist_ok=True)
    project = copy.deepcopy(read_json(project_path))
    source_paths(project, game, output_dir)
    server = project["tree"]["ServerScriptService"]
    replicated = project["tree"]["ReplicatedStorage"]
    server.setdefault("$attributes", {})["PlaytestNoPasses"] = True
    server["PlaytestScenario"] = {
        "$path": os.path.relpath(SCRIPT.resolve(), output_dir).replace("\\", "/")
    }
    replicated["PlaytestScenario"] = {"$path": "scenario.json"}
    generated_project = output_dir / "qa.project.json"
    generated_data = output_dir / "scenario.json"
    name = output_name or (scenario + ".rbxl")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.rbxl", name):
        raise ValueError("output name must be a simple .rbxl filename")
    output = output_dir / name
    generated_data.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    generated_project.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    rojo = shutil.which("rojo")
    if rojo is None:
        raise ValueError("rojo is unavailable; run rokit install")
    subprocess.run([rojo, "build", str(generated_project), "-o", str(output)], check=True)
    print("QA place: " + str(output))
    print("Scenario: " + scenario)
    print("Open as a local file in Studio; keep Studio API access disabled; do not publish.")
    return output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("scenario", choices=("beginner", "gym1", "gym2", "gym3", "collection", "portals"))
    parser.add_argument("--output-name", help="safe filename inside <game>/build/playtest")
    args = parser.parse_args(argv)
    try:
        build(args.game, args.scenario, args.output_name)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as exc:
        print("build_playtest: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

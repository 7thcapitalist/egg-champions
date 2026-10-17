#!/usr/bin/env python3
"""Factory tool: build a game's model table from its asset manifest.

Usage:
    python factory/tools/build_models.py <game-dir> [--manifest PATH] [--out PATH]

Reads <game-dir>/assets/manifest.json (the approved asset ids) and the pet and
egg lists in <game-dir>/config, and writes <game-dir>/assets/models.json:

    {
      "manifest_sha256": "<sha256 of the manifest file>",
      "entries": [
        {"id": "leafpup", "kind": "pet", "mesh_id": 123, "texture_id": 456, "height": 5.0},
        ...
      ]
    }

One entry per pet id and per egg id from config, pets first, each in config
order. The Rojo project maps the file to ReplicatedStorage.GameConfig.models,
where the server's ModelLibrary builds a template for every entry.

Exits 1, naming the id, when a pet or egg in config has no model, a mesh or
texture id is not a positive integer, a height is not a positive number, an
id appears twice, a kind does not match config, or the manifest names an id
that is not in config. Nothing is written on failure.

--manifest and --out exist to try a scratch copy of the manifest without
touching the real files. Standard library only.
"""
import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

ASSET_URI = re.compile(r"^(?:rbxassetid://)?([0-9]+)$")
KINDS = ("pet", "egg")


def asset_id(value):
    """Return the positive integer in an id given as 123, "123" or
    "rbxassetid://123", or None if it is anything else."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    if isinstance(value, str):
        m = ASSET_URI.match(value.strip())
        if m:
            number = int(m.group(1))
            return number if number > 0 else None
    return None


def config_ids(config_dir, name):
    data = json.loads((config_dir / name).read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("%s is not a list" % (config_dir / name).as_posix())
    return [item["id"] for item in data]


def build(manifest_bytes, pets, eggs):
    """Return (table, errors). The table is None when there are errors."""
    errors = []
    try:
        manifest = json.loads(manifest_bytes.decode("utf-8"))
    except ValueError as err:
        return None, ["the manifest is not valid JSON: %s" % err]
    entries = manifest.get("entries") if isinstance(manifest, dict) else None
    if not isinstance(entries, list):
        return None, ["the manifest has no 'entries' list"]

    expected = {pid: "pet" for pid in pets}
    expected.update({eid: "egg" for eid in eggs})

    by_id = {}
    for position, entry in enumerate(entries, 1):
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            errors.append("manifest entry %d has no id" % position)
            continue
        mid = entry["id"]
        if mid in by_id:
            errors.append("%s: listed twice in the manifest" % mid)
            continue
        by_id[mid] = entry
        if mid not in expected:
            errors.append("%s: in the manifest but not a pet or egg id in config" % mid)
            continue
        kind = entry.get("kind")
        if kind != expected[mid]:
            errors.append("%s: kind is %r, config says %r" % (mid, kind, expected[mid]))
        for field in ("mesh_asset_id", "texture_asset_id"):
            if asset_id(entry.get(field)) is None:
                errors.append(
                    "%s: %s %r is not a positive integer asset id" % (mid, field, entry.get(field))
                )
        height = entry.get("height_studs")
        if isinstance(height, bool) or not isinstance(height, (int, float)) or not height > 0:
            errors.append("%s: height_studs %r is not a positive number" % (mid, height))
        if "parts" in entry:
            parts = entry["parts"]
            if not isinstance(parts, list) or not 1 <= len(parts) <= 8:
                errors.append("%s: parts must contain 1 to 8 mesh pieces" % mid)
                continue
            names = set()
            for part in parts:
                if not isinstance(part, dict):
                    errors.append("%s: invalid mesh piece" % mid)
                    continue
                name = part.get("name")
                if not isinstance(name, str) or not name or name in names:
                    errors.append("%s: mesh piece names must be unique nonempty strings" % mid)
                else:
                    names.add(name)
                for field in ("mesh_id", "texture_id"):
                    if asset_id(part.get(field)) is None:
                        errors.append("%s: piece %s has invalid %s" % (mid, name, field))
                for field, length in (("size", 3), ("cframe", 12)):
                    values = part.get(field)
                    if (not isinstance(values, list) or len(values) != length
                            or any(isinstance(n, bool) or not isinstance(n, (int, float))
                                   or not math.isfinite(n) or (field == "size" and n <= 0)
                                   for n in values)):
                        errors.append("%s: piece %s has invalid %s" % (mid, name, field))

    for cid in list(pets) + list(eggs):
        if cid not in by_id:
            errors.append("%s: %s in config has no model in the manifest" % (cid, expected[cid]))

    if errors:
        return None, errors

    table = {
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "entries": [
            {
                "id": cid,
                "kind": expected[cid],
                "mesh_id": asset_id(by_id[cid]["mesh_asset_id"]),
                "texture_id": asset_id(by_id[cid]["texture_asset_id"]),
                "height": float(by_id[cid]["height_studs"]),
            }
            for cid in list(pets) + list(eggs)
        ],
    }
    for entry in table["entries"]:
        source = by_id[entry["id"]]
        if "parts" in source:
            entry["parts"] = [dict(piece, mesh_id=asset_id(piece["mesh_id"]),
                                   texture_id=asset_id(piece["texture_id"]))
                              for piece in source["parts"]]
            entry["visual_style"] = "FacetedCollector"
            entry["flying"] = bool(source.get("flying", False))
    return table, []


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("game_dir")
    parser.add_argument("--manifest", help="manifest to read (default <game-dir>/assets/manifest.json)")
    parser.add_argument("--out", help="file to write (default <game-dir>/assets/models.json)")
    args = parser.parse_args(argv)

    game = Path(args.game_dir)
    manifest_path = Path(args.manifest) if args.manifest else game / "assets" / "manifest.json"
    out_path = Path(args.out) if args.out else game / "assets" / "models.json"

    try:
        manifest_bytes = manifest_path.read_bytes()
        pets = config_ids(game / "config", "pets.json")
        eggs = config_ids(game / "config", "eggs.json")
    except (OSError, ValueError, KeyError, TypeError) as err:
        print("build_models: %s" % err)
        return 1

    table, errors = build(manifest_bytes, pets, eggs)
    if errors:
        for line in errors:
            print("build_models: %s" % line)
        print("build_models: %d problem(s); %s not written" % (len(errors), out_path.as_posix()))
        return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(table, indent=2) + "\n", encoding="utf-8")
    counts = {k: sum(1 for e in table["entries"] if e["kind"] == k) for k in KINDS}
    print(
        "build_models: wrote %s with %d entries (%d pets, %d eggs)"
        % (out_path.as_posix(), len(table["entries"]), counts["pet"], counts["egg"])
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

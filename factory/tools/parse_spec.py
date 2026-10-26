#!/usr/bin/env python3
"""Agent 1 tool: turn a game spec (markdown) into config JSON files.

Usage: python factory/tools/parse_spec.py <game-dir>/spec.md <game-dir>/config

Tables are found by their column names, not by position, so sections can
move around in the spec. Every number comes from a table, never from prose.
Standard library only.
"""
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path


class SpecError(Exception):
    pass


def slug(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def num(text):
    """'5,000' -> 5000, '1.5x' -> 1.5, '50%' -> 0.5."""
    raw = text.strip().replace(",", "")
    try:
        if raw.endswith("%"):
            return round(float(raw[:-1]) / 100, 6)
        if raw.endswith("x"):
            raw = raw[:-1]
        value = float(raw)
    except ValueError:
        raise SpecError(f"expected a number, got '{text}'")
    return int(value) if value.is_integer() else value


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read_tables(markdown):
    """Return a list of (header, rows) for every pipe table in the spec."""
    lines = markdown.splitlines()
    found, i = [], 0
    while i < len(lines):
        is_header = (
            lines[i].startswith("|")
            and i + 1 < len(lines)
            and re.match(r"^\|\s*-{3}", lines[i + 1])
        )
        if not is_header:
            i += 1
            continue
        header = cells(lines[i])
        rows = []
        i += 2
        while i < len(lines) and lines[i].startswith("|"):
            row = cells(lines[i])
            if len(row) != len(header):
                raise SpecError(f"row has {len(row)} cells, header has {len(header)}: {lines[i]}")
            rows.append(dict(zip(header, row)))
            i += 1
        found.append((header, rows))
    return found


def table(tables, *columns):
    matches = [rows for header, rows in tables if all(c in header for c in columns)]
    if len(matches) != 1:
        raise SpecError(f"need exactly one table with columns {columns}, found {len(matches)}")
    return matches[0]


def parse(markdown):
    tables = read_tables(markdown)

    constants = {}
    for row in table(tables, "Key", "Value"):
        try:
            constants[row["Key"]] = num(row["Value"])
        except SpecError:
            constants[row["Key"]] = row["Value"]

    rarities = [
        {
            "id": slug(r["Rarity"]),
            "name": r["Rarity"],
            "order": i + 1,
            "hatch_chance": num(r["Hatch chance"]),
            "click_mult": num(r["Click Power budget"]),
            "battle_mult": num(r["Battle stat multiplier"]),
        }
        for i, r in enumerate(table(tables, "Rarity", "Hatch chance"))
    ]

    roles = [
        {
            "id": slug(r["Role"]),
            "name": r["Role"],
            "click_mult": num(r["Click Power"]),
            "battle_mult": num(r["HP and Attack"]),
        }
        for r in table(tables, "Role", "HP and Attack")
    ]

    variants = [
        {
            "id": slug(r["Variant"]),
            "name": r["Variant"],
            "hatch_chance": num(r["Hatch chance"]),
            "click_mult": num(r["Click Power"]),
            "battle_mult": num(r["Battle HP and Attack"]),
            "look": r["Look"],
        }
        for r in table(tables, "Variant", "Hatch chance")
    ]

    types = [
        {
            "id": slug(r["Type"]),
            "name": r["Type"],
            "strong_against": slug(r["Strong against"]),
            "weak_against": slug(r["Weak against"]),
        }
        for r in table(tables, "Type", "Strong against")
    ]

    specials = [
        {
            "id": slug(r["Special"]),
            "name": r["Special"],
            "kind": r["Kind"],
            "power": num(r["Power"]),
            "value": num(r["Value"]),
            "effect": r["Effect"],
        }
        for r in table(tables, "Special", "Kind")
    ]

    passes = [
        {"id": slug(r["Pass"]), "name": r["Pass"], "effect": r["Effect"]}
        for r in table(tables, "Pass", "Effect")
    ]

    eggs = {}
    for r in table(tables, "Egg", "Base HP"):
        eggs[slug(r["Egg"])] = {
            "id": slug(r["Egg"]),
            "name": r["Egg"] + " Egg",
            "base_click_power": num(r["Base Click Power"]),
            "base_hp": num(r["Base HP"]),
            "base_attack": num(r["Base Attack"]),
        }

    worlds = []
    for r in table(tables, "World", "Gym fee"):
        m = re.match(r"^(\d+)\.\s*(.+)$", r["World"])
        if not m:
            raise SpecError(f"world must look like '1. Name', got '{r['World']}'")
        index, name = int(m.group(1)), m.group(2)
        egg_ids = []
        priced = re.findall(r"([A-Za-z][A-Za-z\- ]*?) Egg (\d{1,3}(?:,\d{3})*|\d+)", r["Eggs (price in coins)"])
        if not priced:
            raise SpecError(f"no eggs found in '{r['Eggs (price in coins)']}'")
        for egg_name, price in priced:
            egg_id = slug(egg_name)
            if egg_id not in eggs:
                raise SpecError(f"egg '{egg_name}' in world '{name}' has no row in the egg stats table")
            eggs[egg_id]["price"] = num(price)
            eggs[egg_id]["world"] = slug(name)
            egg_ids.append(egg_id)
        lead = re.match(r"^(\d+) (\w+) pets, (\w+) strength$", r["Leader team"])
        if not lead:
            raise SpecError(f"leader team must look like '3 Grass pets, Rare strength', got '{r['Leader team']}'")
        worlds.append(
            {
                "index": index,
                "id": slug(name),
                "name": name,
                "environment": r["Environment"],
                "eggs": egg_ids,
                "gym": {
                    "fee": num(r["Gym fee"]),
                    "leader_count": int(lead.group(1)),
                    "leader_type": slug(lead.group(2)),
                    "leader_strength": slug(lead.group(3)),
                    "counter_type": slug(r["Counter"]),
                    "target_rebirths": num(r["Target rebirths"]),
                    "cohort_power_factor": num(r.get("Cohort power", "100%")),
                },
            }
        )

    rarity_by_id = {r["id"]: r for r in rarities}
    role_by_id = {r["id"]: r for r in roles}
    pets = []
    for r in table(tables, "Pet", "Looks like"):
        name, edition = r["Pet"], None
        tag = re.match(r"^(.+?)\s*\((.+?) Edition\)$", name)
        if tag:
            name, edition = tag.group(1), slug(tag.group(2))
        special, off_type = r["Special"], None
        off = re.match(r"^(.+?)\s*\((\w+)\)$", special)
        if off:
            special, off_type = off.group(1), slug(off.group(2))
        egg = eggs.get(slug(r["Egg"]))
        rarity = rarity_by_id.get(slug(r["Rarity"]))
        role = role_by_id.get(slug(r["Role"]))
        if not (egg and rarity and role):
            raise SpecError(f"pet '{name}' refers to an unknown egg, rarity, or role")
        battle = rarity["battle_mult"] * role["battle_mult"]
        pets.append(
            {
                "id": slug(name),
                "name": name,
                "looks_like": r["Looks like"],
                "edition": edition,
                "egg": egg["id"],
                "world": egg.get("world"),
                "rarity": rarity["id"],
                "type": slug(r["Type"]),
                "role": role["id"],
                "special": slug(special),
                "special_off_type": off_type,
                "speed": num(r["Speed"]),
                "click_power": round(egg["base_click_power"] * rarity["click_mult"] * role["click_mult"], 2),
                "hp": round(egg["base_hp"] * battle),
                "attack": round(egg["base_attack"] * battle),
            }
        )

    extra = {}
    if any("Prism" in header for header, _ in tables):
        extra["prisms"] = [
            {"id": slug(r["Prism"]), "name": r["Prism"],
             "multiplier": num(r["Multiplier"]), "coin_price": num(r["Coin price"]),
             "starter": num(r["Starter"]), "pack": num(r["Pack"]),
             "test_product": num(r["TEST product"]), "base_robux": num(r["Base Robux"])}
            for r in table(tables, "Prism", "Multiplier")]
        extra["wild_rarities"] = [
            {"id": slug(r["Wild rarity"]), "strength": num(r["Strength"]),
             "capture_chance": num(r["Capture chance"])}
            for r in table(tables, "Wild rarity", "Strength")]
        extra["wild_areas"] = [
            {"id": slug(r["Wild area"]),
             "rarities": {slug(k): num(r[k]) for k in ("Common", "Uncommon", "Rare", "Epic", "Legendary")},
             "drops": {slug(k): num(r[k + " drop"]) for k in ("Basic", "Refined", "Aurora")}}
            for r in table(tables, "Wild area", "Basic drop")]
    return {
        **extra,
        "constants": constants,
        "rarities": rarities,
        "roles": roles,
        "variants": variants,
        "types": types,
        "specials": specials,
        "passes": passes,
        "eggs": list(eggs.values()),
        "worlds": worlds,
        "pets": pets,
    }


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    spec_path, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    raw = spec_path.read_bytes()
    try:
        config = parse(raw.decode("utf-8"))
    except SpecError as err:
        sys.exit(f"SPEC ERROR: {err}")
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, data in config.items():
        (out_dir / f"{name}.json").write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    manifest = {
        "spec": spec_path.as_posix(),
        "spec_sha256": hashlib.sha256(raw).hexdigest(),
        "counts": {k: len(v) for k, v in config.items()},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Wrote config:", ", ".join(f"{k}={len(v)}" for k, v in config.items()))


if __name__ == "__main__":
    main()

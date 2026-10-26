#!/usr/bin/env python3
"""Agent 1 tool: check that generated config is complete and consistent.

Usage: python factory/tools/validate_config.py <game-dir>/config
Exits with code 1 if any check fails. Standard library only.
"""
import json
import math
import sys
from pathlib import Path

REQUIRED_CONSTANTS = [
    "game_name", "roblox_title", "team_size", "pets_per_egg", "basic_move_power",
    "special_cooldown_turns", "type_bonus_strong", "type_bonus_weak",
    "damage_random_min", "damage_random_max", "gym_retry_seconds",
    "rebirth_first_cost", "rebirth_cost_growth", "rebirth_coin_bonus",
    "rebirth_battle_bonus", "index_egg_bonus", "speed_min", "speed_max",
]


def load(folder, name):
    return json.loads((folder / f"{name}.json").read_text(encoding="utf-8"))


def validate(folder):
    errors = []
    c = load(folder, "constants")
    rarities, roles, variants = load(folder, "rarities"), load(folder, "roles"), load(folder, "variants")
    types, specials = load(folder, "types"), load(folder, "specials")
    eggs, worlds, pets = load(folder, "eggs"), load(folder, "worlds"), load(folder, "pets")

    def check(ok, message):
        if not ok:
            errors.append(message)

    for key in REQUIRED_CONSTANTS:
        check(key in c, f"constant '{key}' is missing")
    if errors:
        return errors

    check(abs(sum(r["hatch_chance"] for r in rarities) - 1) < 1e-6, "rarity hatch chances do not add up to 100%")
    check(sum(v["hatch_chance"] for v in variants) < 1, "variant hatch chances add up to 100% or more")

    type_by_id = {t["id"]: t for t in types}
    for t in types:
        strong, weak = type_by_id.get(t["strong_against"]), type_by_id.get(t["weak_against"])
        check(strong is not None and weak is not None, f"type '{t['name']}' points at an unknown type")
        if strong:
            check(strong["weak_against"] == t["id"], f"'{t['name']}' is strong against '{strong['name']}', but '{strong['name']}' is not weak against it")
        if weak:
            check(weak["strong_against"] == t["id"], f"'{t['name']}' is weak against '{weak['name']}', but '{weak['name']}' is not strong against it")

    rarity_ids = {r["id"] for r in rarities}
    role_ids = {r["id"] for r in roles}
    special_by_id = {s["id"]: s for s in specials}
    egg_by_id = {e["id"]: e for e in eggs}

    for e in eggs:
        check("price" in e and "world" in e, f"egg '{e['name']}' is not placed in any world")

    seen = set()
    for p in pets:
        check(p["id"] not in seen, f"pet id '{p['id']}' appears twice")
        seen.add(p["id"])
        check(p["rarity"] in rarity_ids, f"pet '{p['name']}' has an unknown rarity")
        check(p["role"] in role_ids, f"pet '{p['name']}' has an unknown role")
        check(p["type"] in type_by_id, f"pet '{p['name']}' has an unknown type")
        check(c["speed_min"] <= p["speed"] <= c["speed_max"], f"pet '{p['name']}' speed {p['speed']} is outside the allowed range")
        special = special_by_id.get(p["special"])
        check(special is not None, f"pet '{p['name']}' has an unknown special")
        if special and special["kind"] == "offtype":
            check(p["special_off_type"] in type_by_id, f"pet '{p['name']}' needs a valid off-type")
            check(p["special_off_type"] != p["type"], f"pet '{p['name']}' off-type equals its own type")
        elif special:
            check(p["special_off_type"] is None, f"pet '{p['name']}' lists an off-type but its special is not Off-type")

    for e in eggs:
        in_egg = [p for p in pets if p["egg"] == e["id"]]
        check(len(in_egg) == c["pets_per_egg"], f"egg '{e['name']}' has {len(in_egg)} pets, expected {c['pets_per_egg']}")
        check({p["rarity"] for p in in_egg} == rarity_ids, f"egg '{e['name']}' does not have exactly one pet of each rarity")

    worlds = sorted(worlds, key=lambda w: w["index"])
    check([w["index"] for w in worlds] == list(range(1, len(worlds) + 1)), "world numbers must run 1, 2, 3 with no gaps")
    last_price, last_fee, last_rebirths = 0, 0, -1
    for w in worlds:
        gym = w["gym"]
        factor = gym.get("cohort_power_factor", 1)
        check(type(factor) in (int, float) and 0 < factor <= 1,
              f"cohort power in '{w['name']}' must be finite and in (0, 1]")
        for egg_id in w["eggs"]:
            price = egg_by_id[egg_id].get("price", 0)
            check(price > last_price, f"egg '{egg_by_id[egg_id]['name']}' is not more expensive than the egg before it")
            last_price = price
        check(gym["fee"] > last_price, f"gym fee in '{w['name']}' should cost more than its most expensive egg")
        check(gym["fee"] > last_fee, f"gym fee in '{w['name']}' is not higher than the previous gym")
        check(gym["target_rebirths"] >= last_rebirths, f"target rebirths in '{w['name']}' go down")
        last_fee, last_rebirths = gym["fee"], gym["target_rebirths"]
        check(gym["leader_count"] == c["team_size"], f"gym leader in '{w['name']}' does not field a full team")
        check(gym["leader_strength"] in rarity_ids, f"gym leader strength in '{w['name']}' is not a known rarity")
        leader, counter = type_by_id.get(gym["leader_type"]), type_by_id.get(gym["counter_type"])
        check(leader is not None and counter is not None, f"gym in '{w['name']}' uses an unknown type")
        if leader and counter:
            check(counter["strong_against"] == leader["id"], f"counter type in '{w['name']}' is not strong against the leader's type")
        reachable = {egg_id for earlier in worlds if earlier["index"] <= w["index"] for egg_id in earlier["eggs"]}
        check(any(p["type"] == gym["counter_type"] and p["egg"] in reachable for p in pets), f"no pet of the counter type can be hatched before the gym in '{w['name']}'")

    if (folder / "prisms.json").exists():
        prisms = load(folder, "prisms")
        wild_rarities, wild_areas = load(folder, "wild_rarities"), load(folder, "wild_areas")
        prism_ids = {p["id"] for p in prisms}
        check(len(prism_ids) == len(prisms), "prism IDs must be unique")
        products = [p["test_product"] for p in prisms]
        check(len(set(products)) == len(products), "prism product IDs must be unique")
        def finite(value):
            return type(value) in (int, float) and math.isfinite(value)
        for p in prisms:
            check(finite(p["multiplier"]) and p["multiplier"] > 0, "prism multiplier must be positive")
            for key in ("coin_price", "starter", "pack", "test_product", "base_robux"):
                value = p[key]
                check(type(value) is int and value >= (1 if key in ("pack", "test_product", "base_robux") else 0),
                      f"prism {p['id']} {key} must be a valid integer")
        check({r["id"] for r in wild_rarities} == rarity_ids, "wild rarities must cover every rarity")
        for r in wild_rarities:
            check(finite(r["strength"]) and r["strength"] > 0, "wild strength must be positive")
            check(finite(r["capture_chance"]) and 0 < r["capture_chance"] <= 1, "invalid wild capture chance")
        check({a["id"] for a in wild_areas} == {w["id"] for w in worlds}, "wild areas must cover every world")
        for area in wild_areas:
            for field, ids in (("rarities", rarity_ids), ("drops", prism_ids)):
                weights = area[field]
                check(set(weights) == ids, f"wild area {area['id']} has incomplete {field}")
                check(all(finite(v) and 0 <= v <= 1 for v in weights.values()), "invalid wild weights")
                check(abs(sum(weights.values()) - 1) < 1e-6, "wild weights must sum to 100%")
        for key in ("wild_visitor_chance", "wild_prism_drop_chance", "wild_capture_cap"):
            check(finite(c.get(key)) and 0 <= c[key] <= 1, f"invalid {key}")

    return errors


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    errors = validate(Path(sys.argv[1]))
    if errors:
        print(f"FAILED: {len(errors)} problem(s)")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    print("OK: config passed all checks")


if __name__ == "__main__":
    main()

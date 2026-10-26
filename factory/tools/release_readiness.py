"""Read-only release gates. Evidence cannot be replaced by fixture/test counts."""
import hashlib
import json
import math
from pathlib import Path
import sys

import beta_checks
import quality_review


def source_hash(game):
    digest = hashlib.sha256(quality_review.source_hash(game).encode())
    for name in ("spec.md", "default.project.json", "tuning/gyms.json", "roblox.json"):
        path = game / name
        digest.update(name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def artifact(game, reference):
    if not isinstance(reference, dict) or not isinstance(reference.get("file"), str):
        raise ValueError("evidence reference unavailable")
    name = reference["file"]
    path = (game / name).resolve()
    if not name or Path(name).is_absolute() or not path.is_relative_to(game.resolve()):
        raise ValueError("evidence must stay inside game")
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != reference.get("sha256"):
        raise ValueError("evidence missing/changed: " + name)
    return path


def read(game, manifest, key):
    path = artifact(game, manifest.get(key))
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(key + ": object required")
    return data, path


def bound(game, manifest, key):
    data, path = read(game, manifest, key)
    if data.get("build_sha256") != manifest["build"]["sha256"]:
        raise ValueError(key + ": evidence belongs to another build")
    return data, path


def check(game, stage):
    errors = []
    try:
        if stage not in ("worlds", "playtested", "published_test"):
            raise ValueError("unsupported release stage")
        manifest = json.loads((game / "release/manifest.json").read_text(encoding="utf-8"))
        if manifest.get("schema") != 1 or manifest.get("source_sha256") != source_hash(game):
            raise ValueError("release manifest missing/current source binding invalid")
        artifact(game, manifest.get("build"))
        visual, _ = read(game, manifest, "visual")
        errors += ["visual: " + e for e in quality_review.check(game, visual)]
        traversal, _ = bound(game, manifest, "traversal")
        worlds = json.loads((game / "config/worlds.json").read_text(encoding="utf-8"))
        required = {w["id"] for w in worlds}
        rows = traversal.get("worlds", [])
        if (not isinstance(rows, list) or len(rows) != len(required)
                or {w.get("id") for w in rows} != required
                or any(w.get("arrival_reviewed") is not True or w.get("routes_passed") is not True for w in rows)):
            errors.append("all configured world arrivals and routes need observed evidence")
        if stage == "worlds":
            return errors
        for kind in ("mobile", "multiplayer"):
            data, path = bound(game, manifest, kind)
            errors += [kind + ": " + e for e in beta_checks.matrix(data, path.parent, kind)["errors"]]
        network, _ = bound(game, manifest, "slow_network")
        latency = network.get("added_latency_ms")
        bandwidth = network.get("bandwidth_kbps")
        if (network.get("environment") != "published-client"
                or network.get("physical_device") is not True
                or not isinstance(network.get("impairment_method"), str)
                or not network["impairment_method"].strip()
                or any(type(n) not in (int, float) or not math.isfinite(n) or n <= 0
                       for n in (latency, bandwidth))
                or any(network.get(k) != "passed" for k in ("hatch", "battle", "reconnect"))):
            errors.append("physical slow-network play requires observed impairment and hatch/battle/reconnect results")
        natural, _ = bound(game, manifest, "natural_progression")
        played = natural.get("gyms", [])
        required_gyms = {w["id"] for w in worlds if w["index"] >= 2}
        if (natural.get("environment") != "published-client" or natural.get("seeded") is not False
                or natural.get("owned_passes") != [] or not isinstance(played, list)
                or {w.get("id") for w in played} != required_gyms or len(played) != len(required_gyms)
                or any(w.get("status") != "passed" or type(w.get("duration_seconds")) not in (int, float)
                       or not 0 < w["duration_seconds"] < float("inf") for w in played)):
            errors.append("gyms 2+ require observed natural free-player progression, not seeded QA")
        config = json.loads((game / "roblox.json").read_text(encoding="utf-8"))
        if natural.get("place_id") != config["test"]["place_id"]:
            errors.append("natural progression must identify the configured TEST place")
        if stage == "playtested":
            return errors
        before, before_path = bound(game, manifest, "save_before")
        after, _ = bound(game, manifest, "save_after")
        if not beta_checks.evidence(before_path.parent, before.get("release_evidence")):
            raise ValueError("DataStore release evidence missing/changed")
        release_path = before_path.parent / before["release_evidence"]["file"]
        before["release_event"] = json.loads(release_path.read_text(encoding="utf-8"))
        errors += ["saves: " + e for e in beta_checks.saves(before, after)["errors"]]
        publication, _ = bound(game, manifest, "publication")
        if (publication.get("place_id") != config["test"]["place_id"]
                or type(publication.get("place_version")) is not int or publication["place_version"] <= 0
                or publication.get("sources_reopened_match") is not True):
            errors.append("TEST publication/version and reopened source match are unverified")
        for data in (before, after, natural):
            if (data.get("place_id") != publication.get("place_id")
                    or data.get("place_version") != publication.get("place_version")):
                errors.append("published gameplay/save evidence must match one reviewed TEST version")
        passes, _ = bound(game, manifest, "passes")
        expected = {p["id"] for p in json.loads((game / "config/passes.json").read_text(encoding="utf-8"))}
        rows = passes.get("passes", [])
        if (passes.get("place_id") != publication.get("place_id")
                or passes.get("place_version") != publication.get("place_version")
                or not isinstance(rows, list) or len(rows) != len(expected)
                or {p.get("id") for p in rows} != expected
                or any(p.get("purchase_completion") != "passed" or p.get("ownership_effect") != "passed" for p in rows)):
            errors.append("configured pass purchase completion/ownership need TEST evidence; mocks are insufficient")
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        errors.append(str(exc))
    return errors


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: python -B factory/tools/release_readiness.py GAME")
        return 2
    game = Path(args[0]).resolve()
    results = {stage: check(game, stage) for stage in ("worlds", "playtested", "published_test")}
    print(json.dumps({"schema": 1, "game": str(game), "scope": "release-evidence-only",
                      "ready": not any(results.values()), "errors": results}, indent=2))
    return int(any(results.values()))


if __name__ == "__main__":
    sys.exit(main())

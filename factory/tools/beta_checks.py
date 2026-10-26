"""Read-only beta evidence checks. No Studio, network, model or executor calls.

python -B factory/tools/beta_checks.py saves BEFORE.json AFTER.json
python -B factory/tools/beta_checks.py mobile RUN.json
python -B factory/tools/beta_checks.py multiplayer RUN.json
Missing evidence fails closed. Passing checks does not certify source truth.
"""
import argparse
import hashlib
import json
import math
from datetime import datetime
from pathlib import Path

PROFILE_FIELDS = (
    "version", "coins", "pets", "team", "index", "badges", "rebirths",
    "gymsBeaten", "feesPaid", "gymRetryAt", "playSeconds", "tutorialStep",
)
MOBILE_CASES = ("desktop", "portrait-small", "portrait-phone", "landscape-short", "physical-phone")
REQUESTED_VIEWPORTS = {"desktop": [1280, 720], "portrait-small": [320, 720],
                       "portrait-phone": [390, 844], "landscape-short": [568, 239]}
MOBILE_ACTIONS = ("joystick", "camera-drag", "training-enter-exit", "hatch", "equip", "journey-target", "battle-attack", "battle-heal", "resize")
MULTIPLAYER_CASES = (
    "profile-isolation", "fee-once", "parallel-battles", "duplicate-start",
    "foreign-session", "foreign-pet", "retry-isolation", "rate-limit-isolation",
    "disconnect-rejoin", "remote-transport",
)


def canonical(value):
    return json.dumps(value, sort_keys=True, allow_nan=False, separators=(",", ":"))


def saves(before, after):
    errors = []
    fields = {}
    for key in ("subject", "build_sha256", "place_id", "place_version"):
        if key not in before or key not in after or before[key] is None or before[key] != after[key]:
            errors.append("missing/different " + key)
    for snap in (before, after):
        if snap.get("storage_mode") != "datastore" or snap.get("capture_kind") != "server":
            errors.append("server DataStore evidence required; temporary/unknown is not persistence")
        if type(snap.get("place_id")) is not int or snap["place_id"] <= 0:
            errors.append("published TEST place required")
        if type(snap.get("place_version")) is not int or snap["place_version"] <= 0:
            errors.append("published version unknown")
        if not isinstance(snap.get("subject"), str) or not snap["subject"].strip():
            errors.append("stable private subject alias required")
        digest = snap.get("build_sha256")
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            errors.append("build hash unknown/invalid")
    if (not before.get("session_id") or not after.get("session_id")
            or before["session_id"] == after["session_id"]):
        errors.append("distinct session identities required")
    try:
        first = datetime.fromisoformat(before["captured_at"].replace("Z", "+00:00"))
        last = datetime.fromisoformat(after["captured_at"].replace("Z", "+00:00"))
        if first.tzinfo is None or last.tzinfo is None or last <= first:
            raise ValueError("invalid order")
    except (KeyError, TypeError, ValueError, AttributeError):
        errors.append("capture timestamps unknown or not ordered")
    if before.get("release_confirmed") is not True:
        errors.append("release/save confirmation unavailable")
    release = before.get("release_event", {})
    if (not isinstance(release, dict) or release.get("released") is not True
            or release.get("saved") is not True or release.get("storage_mode") != "datastore"
            or any(release.get(key) != before.get(key) for key in
                   ("subject", "session_id", "place_id", "place_version", "build_sha256"))):
        errors.append("matching successful persistent release event required")
    try:
        when = datetime.fromisoformat(release["captured_at"].replace("Z", "+00:00"))
        if not first <= when <= last:
            raise ValueError("release outside roundtrip")
    except (KeyError, TypeError, ValueError, AttributeError, UnboundLocalError):
        errors.append("release timestamp unknown/outside capture interval")
    for snap in (before, after):
        profile = snap.get("profile")
        if not isinstance(profile, dict) or set(profile) != set(PROFILE_FIELDS):
            errors.append("profile schema incomplete/unknown; update coverage before accepting")
        elif type(profile.get("version")) is not int or profile["version"] != 5:
            errors.append("profile version unknown; update coverage before accepting")
    a, b = before.get("profile", {}), after.get("profile", {})
    if not isinstance(a, dict) or not isinstance(b, dict):
        return {"status": "blocked", "errors": errors, "fields": fields}
    for key in PROFILE_FIELDS:
        if key not in a or key not in b or a[key] is None or b[key] is None:
            fields[key] = "unknown"
        elif key == "coins" and a[key] != b[key]:
            receipt = after.get("offline_reward", {})
            snapshot = release.get("offline_snapshot", {})
            valid = False
            try:
                rate, at = snapshot["rate"], snapshot["at"]
                awarded_at = receipt["at"]
                cap = before["offline_max_seconds"]
                numeric = (rate, at, awarded_at, cap, a[key], b[key])
                if (all(type(v) in (int, float) and math.isfinite(v) for v in numeric)
                        and rate > 0 and at >= 0 and cap > 0 and awarded_at >= at
                        and receipt["source"] == snapshot
                        and receipt["jobId"] == after["session_id"]
                        and after["offline_max_seconds"] == cap
                        and release["saved_coins"] == a[key]
                        and when.timestamp() - 2 <= at <= last.timestamp()
                        and at <= awarded_at <= last.timestamp()):
                    seconds = min(math.floor(awarded_at - at), cap)
                    amount = math.floor(seconds * rate)
                    valid = (receipt["seconds"] == seconds and receipt["coins"] == amount
                             and b[key] == a[key] + amount)
            except (KeyError, TypeError, ValueError, OverflowError, UnboundLocalError):
                pass
            fields[key] = "passed" if valid else "failed"
        elif key == "playSeconds":
            av, bv = a[key], b[key]
            valid = (type(av) in (int, float) and type(bv) in (int, float)
                     and math.isfinite(av) and math.isfinite(bv) and 0 <= av <= bv)
            fields[key] = "passed" if valid else "failed"
        else:
            fields[key] = "passed" if canonical(a[key]) == canonical(b[key]) else "failed"
    errors += ["profile " + key + ": " + status for key, status in fields.items() if status != "passed"]
    return {"status": "blocked" if errors else "passed", "errors": errors, "fields": fields}


def evidence(root, item):
    if not isinstance(item, dict):
        return False
    name = item.get("file")
    if not isinstance(name, str) or not name or Path(name).is_absolute():
        return False
    path = (root / name).resolve()
    return (path.is_relative_to(root.resolve()) and path.is_file()
            and hashlib.sha256(path.read_bytes()).hexdigest() == item.get("sha256"))


def cases(data, required):
    entries = data.get("cases", [])
    if not isinstance(entries, list) or any(not isinstance(v, dict) for v in entries):
        raise ValueError("cases must be a list of objects")
    ids = [v.get("id") for v in entries]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate evidence case")
    known = {v.get("id"): v for v in entries}
    return [known.get(key, {"id": key, "status": "unknown"}) for key in required]


def matrix(data, root, kind):
    errors = []
    if not isinstance(data.get("build_sha256"), str) or len(data["build_sha256"]) != 64:
        errors.append("build hash unknown")
    if kind == "mobile":
        required = MOBILE_CASES
    else:
        required = MULTIPLAYER_CASES
        subjects = data.get("subjects", [])
        if (not isinstance(subjects, list) or len(subjects) < 2
                or any(not isinstance(s, str) or not s.strip() for s in subjects)
                or len(set(subjects)) != len(subjects)):
            errors.append("at least two distinct subject aliases required")
        if data.get("mode") != "real-clients":
            errors.append("mocks/server callbacks do not validate multi-client transport")
    for case in cases(data, required):
        key = str(case["id"])
        if case.get("status") != "passed" or not evidence(root, case.get("evidence")):
            errors.append(key + ": unknown/failed or missing bound evidence")
        if kind != "mobile":
            continue
        for dim in ("requested", "effective"):
            size = case.get(dim)
            if (not isinstance(size, list) or len(size) != 2
                    or any(type(v) not in (int, float) or not math.isfinite(v) or v <= 0 for v in size)):
                errors.append(key + ": " + dim + " viewport unknown")
        if key in REQUESTED_VIEWPORTS and case.get("requested") != REQUESTED_VIEWPORTS[key]:
            errors.append(key + ": required viewport was not requested")
        if not isinstance(case.get("device"), str) or not case["device"].strip():
            errors.append(key + ": device unknown")
        if case.get("input_verified") is not True:
            errors.append(key + ": interaction evidence missing")
        if key == "physical-phone" and case.get("physical_touch") is not True:
            errors.append(key + ": physical touch evidence missing")
        actions = case.get("actions", {})
        if not isinstance(actions, dict) or any(actions.get(v) != "passed" for v in MOBILE_ACTIONS):
            errors.append(key + ": action coverage incomplete")
        if case.get("text_readable") is not True or case.get("controls_reachable") is not True:
            errors.append(key + ": text/touch review incomplete")
    return {"status": "blocked" if errors else "passed", "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("saves", "mobile", "multiplayer"))
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path, nargs="?")
    args = parser.parse_args()
    try:
        data = json.loads(args.first.read_text(encoding="utf-8"))
        if args.kind == "saves":
            if args.second is None:
                raise ValueError("saves requires before and after snapshots")
            if not evidence(args.first.resolve().parent, data.get("release_evidence")):
                raise ValueError("bound release event evidence unavailable")
            release_path = args.first.resolve().parent / data["release_evidence"]["file"]
            data["release_event"] = json.loads(release_path.read_text(encoding="utf-8"))
            result = saves(data, json.loads(args.second.read_text(encoding="utf-8")))
        else:
            result = matrix(data, args.first.resolve().parent, args.kind)
        print(json.dumps(result, indent=2, allow_nan=False))
        return 0 if result["status"] == "passed" else 1
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        print(json.dumps({"status": "blocked", "errors": [str(exc)]}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

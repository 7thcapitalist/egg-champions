"""Check visual review evidence, never infer aesthetic approval from code."""
import hashlib
import json
import sys
from pathlib import Path

CATEGORIES = ("composition", "models", "animation", "feedback", "onboarding")

def source_hash(game):
    digest = hashlib.sha256()
    files = list((game / "src").rglob("*.luau")) + list((game / "config").glob("*.json"))
    files += [p for p in (game / "assets/manifest.json", game / "assets/models.json") if p.is_file()]
    for path in sorted(files):
        digest.update(path.relative_to(game).as_posix().encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()

def check(game, review):
    errors = []
    if review.get("source_sha256") != source_hash(game):
        errors.append("review is stale for current sources/config/assets")
    for field in ("reviewer", "date", "environment", "limitations"):
        if not review.get(field):
            errors.append("missing " + field)
    if review.get("environment") not in ("Studio", "published-client"):
        errors.append("environment must identify Studio or published-client")
    for key in CATEGORIES:
        row = review.get("categories", {}).get(key, {})
        if type(row.get("score")) not in (int, float) or not 4 <= row["score"] <= 5:
            errors.append(key + ": score must be 4 or higher for approval")
        if not row.get("observation"):
            errors.append(key + ": missing actual observation")
        if not row.get("evidence"):
            errors.append(key + ": missing evidence")
        for entry in row.get("evidence", []):
            path = (game / entry).resolve()
            if not path.is_relative_to(game.resolve()) or not path.is_file():
                errors.append(key + ": missing/local evidence outside game: " + entry)
            elif review.get("evidence_sha256", {}).get(entry) != hashlib.sha256(path.read_bytes()).hexdigest():
                errors.append(key + ": evidence hash missing or changed: " + entry)
    if not {"desktop", "mobile"}.issubset(set(review.get("viewports", []))):
        errors.append("desktop and mobile review required")
    captures = review.get("viewport_captures", [])
    if not isinstance(captures, list) or not captures:
        errors.append("requested and effective viewport captures required")
    else:
        seen = set()
        for capture in captures:
            if not isinstance(capture, dict):
                errors.append("invalid viewport capture")
                continue
            valid = True
            for field in ("requested", "actual"):
                size = capture.get(field)
                if (not isinstance(size, list) or len(size) != 2 or
                        any(type(n) not in (int, float) or not 0 < n < 16384 for n in size)):
                    errors.append("viewport capture needs valid " + field + " dimensions")
                    valid = False
            if not valid:
                continue
            orientation = capture.get("orientation")
            width, height = capture["actual"]
            if orientation not in ("portrait", "landscape"):
                errors.append("viewport capture needs explicit orientation")
            elif (orientation == "portrait") != (height > width):
                errors.append("viewport orientation differs from effective dimensions")
            surface = capture.get("surface")
            if surface not in ("desktop", "mobile"):
                errors.append("viewport capture needs desktop/mobile surface")
            else:
                seen.add(surface)
            entry = capture.get("evidence")
            if not isinstance(entry, str) or not entry:
                errors.append("viewport capture needs evidence")
            else:
                path = (game / entry).resolve()
                if not path.is_relative_to(game.resolve()) or not path.is_file():
                    errors.append("viewport capture evidence missing or outside game")
                elif review.get("evidence_sha256", {}).get(entry) != hashlib.sha256(path.read_bytes()).hexdigest():
                    errors.append("viewport capture evidence hash missing or changed")
        if not {"desktop", "mobile"}.issubset(seen):
            errors.append("effective desktop and mobile viewport captures required")
    return errors

def main():
    game = Path(sys.argv[1])
    if len(sys.argv) == 2:
        print(source_hash(game))
        return 0
    try:
        errors = check(game, json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError) as error:
        errors = [str(error)]
    for error in errors:
        print("FAIL: " + error)
    if not errors:
        print("OK: current review evidence complete; aesthetic scores remain reviewer judgments")
    return int(bool(errors))

if __name__ == "__main__":
    sys.exit(main())

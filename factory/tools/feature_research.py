"""Validate evidence-led feature research and draft bounded briefs. No AI/network.

python -B factory/tools/feature_research.py GAME check
python -B factory/tools/feature_research.py GAME plan NEW_OUTPUT_DIRECTORY
Plans never edit spec/config, task index, state, executor policy or credentials.
"""
import argparse
import hashlib
import json
import re
from datetime import date
from pathlib import Path
from urllib.parse import urlparse


def local(game, name):
    if not isinstance(name, str) or not name:
        raise ValueError("missing relative path")
    path = (game / name).resolve()
    if Path(name).is_absolute() or not path.is_relative_to(game.resolve()):
        raise ValueError("path outside game: " + name)
    return path


def check(game, data, *, today=None, require_plan=True):
    today = today or date.today()
    errors = []
    try:
        if data.get("version") != 1:
            raise ValueError("unsupported research version")
        sources = data["sources"]
        features = data["features"]
        if not isinstance(sources, list) or not sources or not isinstance(features, list) or not features:
            raise ValueError("sources and features must be nonempty lists")
        known = {}
        for source in sources:
            key = source["id"]
            if not isinstance(key, str) or key in known:
                raise ValueError("duplicate/invalid source id")
            url = urlparse(source["url"])
            if url.scheme != "https" or not url.hostname:
                raise ValueError("source needs an https URL")
            age = (today - date.fromisoformat(source["checked_at"])).days
            if not 0 <= age <= 14:
                raise ValueError("stale/future reference: " + key)
            if source["kind"] not in ("official_update", "official_description", "charts_snapshot"):
                raise ValueError("identify the primary source kind")
            if type(source["available"]) is not bool or not source.get("observation") or not source.get("limitations"):
                raise ValueError("source needs observation, availability and limitations")
            if "rank" in source:
                evidence = local(game, source["evidence"])
                if (source["kind"] != "charts_snapshot" or not source["available"]
                        or type(source["rank"]) is not int or source["rank"] < 1
                        or hashlib.sha256(evidence.read_bytes()).hexdigest() != source["evidence_sha256"]):
                    raise ValueError("ranking requires a bound charts snapshot")
            known[key] = source
        tasks = {}
        if require_plan:
            raw = json.loads((game / "tasks/index.json").read_text(encoding="utf-8"))
            entries = raw["tasks"] if isinstance(raw, dict) else raw
            tasks = {str(t["id"]): t for t in entries if isinstance(t, dict)}
        ids = set()
        for feature in features:
            key = feature["id"]
            if not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9-]{1,63}", key) or key in ids:
                raise ValueError("duplicate/invalid feature id")
            ids.add(key)
            if feature["decision"] not in ("adopt", "defer", "reject"):
                raise ValueError("invalid decision: " + key)
            if not feature.get("title") or not feature.get("rationale") or not feature.get("adaptation"):
                raise ValueError("feature needs title, rationale and original adaptation")
            refs = feature["source_ids"]
            if (not isinstance(refs, list) or not refs
                    or any(ref not in known or not known[ref]["available"] for ref in refs)):
                raise ValueError("feature cites missing/unavailable evidence: " + key)
            if feature["decision"] != "adopt":
                continue
            if feature.get("approved") is not True:
                raise ValueError("adoption requires explicit scoped design approval: " + key)
            for field in ("changes_economy", "changes_persistence"):
                if type(feature.get(field)) is not bool:
                    raise ValueError("declare economy/save impacts: " + key)
            if (feature["changes_economy"] or feature["changes_persistence"]) and not feature.get("design_contract"):
                raise ValueError("economy/save change needs an explicit design contract: " + key)
            for field in ("build", "automated_checks", "engine_checks", "scope_paths"):
                if not isinstance(feature.get(field), list) or not feature[field] or any(
                        not isinstance(v, str) or not v.strip() for v in feature[field]):
                    raise ValueError("missing bounded build/checks/scope: " + key)
            for name in feature["scope_paths"]:
                local(game, name)
            if feature.get("design_contract"):
                if not local(game, feature["design_contract"]).is_file():
                    raise ValueError("missing design contract: " + key)
            if require_plan:
                task = tasks.get(str(feature.get("task_id")))
                if task is None:
                    raise ValueError("adopted feature has no indexed task: " + key)
                brief = local(game, "tasks/" + task["file"])
                if key not in brief.read_text(encoding="utf-8"):
                    raise ValueError("brief does not bind feature id: " + key)
    except (ValueError, TypeError, KeyError, OSError, AttributeError) as exc:
        errors.append(str(exc))
    return errors


def draft(feature):
    return ("# " + feature["title"] + "\n\nFeature: `" + feature["id"] + "`\n\n"
            "## Goal\n\n" + feature["adaptation"] + "\n\n## Build\n\n"
            + "\n".join("- " + item for item in feature["build"])
            + "\n\nScope: " + ", ".join("`" + p + "`" for p in feature["scope_paths"])
            + "\n\n## Done when\n\n"
            + "\n".join("- [ ] " + item for item in feature["automated_checks"])
            + "\n\n## Needs human or playtester\n\n"
            + "\n".join("- [ ] " + item for item in feature["engine_checks"])
            + "\n\n## Out of scope\n\nNo automatic publication, executor launch or budget authorization. "
              "Do not copy reference branding, pets or assets. Changes outside the declared scope "
              "need a new design review. A drafted brief is not evidence of implementation.\n")


def plan(game, data, output, *, today=None):
    errors = check(game, data, today=today, require_plan=False)
    if errors:
        raise ValueError("; ".join(errors))
    output = output.resolve()
    if not output.is_relative_to(game.resolve()):
        raise ValueError("proposal output must stay inside game")
    adopted = [f for f in data["features"] if f["decision"] == "adopt"]
    if not adopted:
        raise ValueError("no approved adopted features to draft")
    # Never overwrite or register tasks, including when a plan was interrupted.
    output.mkdir(parents=True, exist_ok=False)
    for feature in adopted:
        (output / (feature["id"] + ".md")).write_text(draft(feature), encoding="utf-8")
    manifest = {"status": "proposal-only", "research_sha256": hashlib.sha256(
        json.dumps(data, sort_keys=True).encode()).hexdigest(),
        "features": [{"id": f["id"], "brief": f["id"] + ".md"} for f in adopted]}
    (output / "plan.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("command", choices=("check", "plan"))
    parser.add_argument("output", type=Path, nargs="?")
    args = parser.parse_args()
    try:
        data = json.loads((args.game / "design/feature-research.json").read_text(encoding="utf-8"))
        if args.command == "check":
            errors = check(args.game, data)
            if errors:
                raise ValueError("; ".join(errors))
            print("PASS: current sources, original adaptations and adopted feature/task coverage")
        else:
            if args.output is None:
                raise ValueError("plan requires a new output directory")
            print(json.dumps(plan(args.game, data, args.output), indent=2))
    except (OSError, ValueError, TypeError) as exc:
        print("BLOCKED: " + str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

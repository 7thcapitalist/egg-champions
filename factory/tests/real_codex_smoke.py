"""Optional live Codex smoke: execute Run.run_agent in an isolated Git fixture."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "factory" / "tools"))
from run_factory import Run

with tempfile.TemporaryDirectory(prefix="codex-run-agent-", dir=root / "games" / "egg-champions" / "build") as tmp:
    repo = Path(tmp)
    game = repo / "games" / "fixture"
    game.mkdir(parents=True)
    role = repo / ".claude" / "agents" / "coder.md"
    role.parent.mkdir(parents=True)
    role.write_text("---\nname: coder\n---\nFixture coder role.\n", encoding="utf-8")
    (game / "seed.txt").write_text("fixture\n", encoding="utf-8")
    for argv in (["git", "init", "-q"], ["git", "config", "user.name", "Smoke"],
                 ["git", "config", "user.email", "smoke@example.invalid"],
                 ["git", "add", "-A"], ["git", "commit", "-qm", "fixture"]):
        subprocess.run(argv, cwd=repo, check=True, capture_output=True)
    args = SimpleNamespace(game_dir=str(game), agent_cmd=None, push=False)
    run = Run(args)
    ok, report = run.run_agent(
        "coder", "Read-only fixture. Do not run commands or edit files. Reply exactly CODEX_FIXTURE_OK.",
        2, "real-smoke", 1)
    trace = game / "reports" / "agents" / "real-smoke-attempt1.jsonl"
    events = [json.loads(line)["type"] for line in trace.read_text(encoding="utf-8").splitlines()]
    print(json.dumps({"ok": ok, "report": report, "events": events,
                      "git_status": subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                                                   capture_output=True, text=True).stdout.strip()}, indent=2))
    if not ok or "CODEX_FIXTURE_OK" not in report:
        sys.exit(1)

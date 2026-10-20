#!/usr/bin/env python3
"""Factory tool: build one game from its state and task list, nobody typing.

Usage:
    python factory/tools/run_factory.py <game-dir> [options]

Options:
    --max-tasks N       build at most N tasks this run (default 1)
    --task-minutes M    wall-clock limit for one task, all attempts (default 10)
    --attempts N        tries per task or stage, the first included (default/max 2)
    --unblock ID        set a blocked task back to pending before starting
    --push              push commits (default: local commits only)
    --agent-cmd CMD     disabled; tests use subprocess mocks in fixtures.

The loop reads `<game-dir>/state.json` and works on the first stage that has
not passed:
- A stage whose gate already passes is recorded as passed and skipped.
- `spec_parsed` and `economy_tuned` run scripts; `planned` uses one agent.
- `built` walks `<game-dir>/tasks/index.json` in dependency order. Each task
  gets a fresh headless coder run on its one brief, then the orchestrator
  checks the result itself: only allowed paths changed, every Done-when box is
  ticked, the brief's Done-when commands pass, and so do the test entry point,
  rojo, selene and stylua. Pass: mark done and commit locally. Fail: retry with
  the failing output. Out of attempts: save the work as a patch, revert it,
  mark the task blocked, write the report, stop.
- A stage with no agent yet stops the run.

Every step adds a line to `<game-dir>/reports/run-log.md`, and every run ends
by rewriting `<game-dir>/reports/latest.md`.

The coder never commits. This tool does, after its own checks, so nothing
reaches git that the checks have not seen. Standard library only.
"""
import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import concurrent.futures  # noqa: E402
import gate  # noqa: E402  lives next to this file
from executor_policy import Ledger, PolicyError, exclusive, load_policy  # noqa: E402

STAGE_AGENTS = {
    "spec_parsed": "spec-parser",
    "economy_tuned": "economy-tuner",
    "planned": "planner",
    "built": "coder",
}

# What each stage's agent may write, relative to the game folder.
STAGE_WRITES = {
    "spec_parsed": ["config/"],
    "economy_tuned": ["tuning/"],
    "planned": ["tasks/"],
}

# Test files a coder may write even though they live outside the game folder.
# The planner names `factory/tools/run_tests` as the test entry point.
TEST_ENTRY = ["factory/tools/run_tests.py", "factory/tools/run_tests"]
TEST_FILE = re.compile(r"\.spec\.luau$")

# Programs a Done-when command may start with for this tool to run it.
RUNNABLE = {"python", "python3", "py", "rojo", "selene", "stylua", "grep"}

# A Done-when item that describes an experiment (break something, see it fail,
# put it back) cannot be rerun as is. The coder's tick is the record for it.
EXPERIMENT = re.compile(r"deliberately|\bbroken\b|\brevert\b", re.IGNORECASE)

# A Done-when item about committing is this tool's job, so it ticks it.
COMMIT_ITEM = re.compile(r"\bcommitted\b", re.IGNORECASE)

CHECK_TIMEOUT = 600  # seconds, for one check command
FEEDBACK_CHARS = 2000  # bounded failing output, never a full history
EM_DASH = chr(0x2014)


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def tail(text, limit):
    text = (text or "").strip()
    return text if len(text) <= limit else "...\n" + text[-limit:]


def one_line(text, limit=160):
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


class Stop(Exception):
    """End the run now. The message goes into the report."""


# ------------------------------------------------------------------ the brief


def done_when_items(path):
    """Return the Done-when checklist as [{line, ticked, text}]."""
    items = []
    inside = False
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("## "):
            inside = stripped == gate.DONE_WHEN
            continue
        if not inside:
            continue
        box = re.match(r"- \[( |x|X)\]\s*(.*)", stripped)
        if box:
            items.append({"line": n, "ticked": box.group(1) != " ", "text": box.group(2)})
        elif stripped and items:
            items[-1]["text"] += " " + stripped
    return items


def tick_commit_items(path):
    """Tick Done-when boxes about committing. Return how many were ticked."""
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    wanted = {i["line"] for i in done_when_items(path) if not i["ticked"] and COMMIT_ITEM.search(i["text"])}
    for n in wanted:
        lines[n - 1] = lines[n - 1].replace("- [ ]", "- [x]", 1)
    if wanted:
        path.write_bytes("".join(lines).encode("utf-8"))
    return len(wanted)


def brief_commands(items):
    """The commands this tool can rerun from a brief's Done-when items.

    Returns [(argv, expect)] where expect is "zero" (exit 0) or "empty" (no
    output: a grep that must find nothing).
    """
    found = []
    for item in items:
        if EXPERIMENT.search(item["text"]):
            continue
        for span in re.findall(r"`([^`]+)`", item["text"]):
            try:
                argv = shlex.split(span)
            except ValueError:
                continue
            if not argv or argv[0] not in RUNNABLE:
                continue
            expect = "zero"
            if argv[0] == "grep" and re.search(r"finds no|no match", item["text"], re.IGNORECASE):
                expect = "empty"
            found.append((argv, expect))
    return found


def named_paths(path):
    """Paths a brief names in backticks: the files it asks the coder to write."""
    names = set()
    for span in re.findall(r"`([^`\s]+)`", path.read_text(encoding="utf-8")):
        if "/" in span or re.search(r"\.(luau|lua|json|toml|md|py|yml|yaml|txt)$", span):
            names.add(span[2:] if span.startswith("./") else span)
    return names


# ------------------------------------------------------------- built-in grep


def builtin_grep(argv, root):
    """Run `grep -[rnEil] PATTERN PATH...` where no grep is installed.

    Prints matches as path:line:text, exits 0 on a match and 1 on none, like
    grep. Patterns are POSIX extended expressions, which Python's `re` reads
    the same way for the classes the briefs use.
    """
    flags, rest = set(), []
    for arg in argv[1:]:
        if arg.startswith("-") and not rest:
            flags.update(arg[1:])
        else:
            rest.append(arg)
    if not rest:
        return 2, "grep: no pattern"
    pattern = re.compile(rest[0], re.IGNORECASE if "i" in flags else 0)
    out = []
    for target in rest[1:] or ["."]:
        base = root / target
        files = sorted(p for p in base.rglob("*") if p.is_file()) if base.is_dir() else [base]
        for f in files:
            try:
                text = f.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if pattern.search(line):
                    rel = f.relative_to(root).as_posix()
                    if "l" in flags:
                        out.append(rel)
                        break
                    out.append("%s:%d:%s" % (rel, n, line) if "n" in flags else "%s:%s" % (rel, line))
    return (0 if out else 1), "\n".join(out)


# ---------------------------------------------------------------------- run


class Run:
    def __init__(self, args):
        self.args = args
        self.root = self._repo_root(Path(args.game_dir))
        self.game = Path(os.path.relpath(Path(args.game_dir).resolve(), self.root)).as_posix()
        self.game_path = self.root / self.game
        self.reports = self.game_path / "reports"
        self.started = now()
        self.t0 = time.time()
        self.owned = {}  # repo path -> bytes this tool wrote and still owns
        self.done = []  # {id, title, attempts, commit}
        self.problems = []  # {what, reason, detail}
        self.headline = ""
        self.next_step = ""
        self.branch = self.git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        common = self.git("rev-parse", "--git-common-dir").stdout.strip()
        self.control_dir = (self.root / common).resolve() / "factory-executor"
        self.ledger = Ledger(self.control_dir)
        self.locked = False
        self.deadlines = {}

    def policy(self):
        # Operators can pause or lower authorization while a run is active.
        try:
            return load_policy(self.root / "factory/executor.json")
        except PolicyError as exc:
            raise Stop(str(exc)) from exc

    def next_attempt(self, label):
        policy = self.policy()
        try:
            attempt = self.ledger.admit(policy, self.game + ":" + label)
        except PolicyError as exc:
            raise Stop(str(exc)) from exc
        if attempt > min(2, self.args.attempts, policy["attempts"]):
            raise Stop("task exhausted configured total attempts")
        return attempt

    def execute(self):
        """Lock before state changes; production pause also covers --finish."""
        try:
            # A paused executor must not need write access to Git metadata.
            if self.policy()["paused"]:
                raise Stop("production paused in factory/executor.json")
            with exclusive(self.control_dir):
                self.locked = True
                policy = self.policy()
                if policy["paused"]:
                    raise Stop("production paused in factory/executor.json")
                if self.args.agent_cmd:
                    raise Stop("--agent-cmd is disabled; use subprocess mocks in temporary fixtures")
                if self.args.push:
                    raise Stop("push disabled by executor policy; publication stays manual")
                self.ledger.admit(policy, self.game + ":admission")
                return self.finish(self.args.finish) if self.args.finish else self.go()
        except (PolicyError, Stop, OSError) as exc:
            print("BLOCKED: %s" % exc)
            return 1
        finally:
            self.locked = False

    # ----------------------------------------------------------- utilities

    @staticmethod
    def _repo_root(game):
        if not game.is_dir():
            raise SystemExit("no game folder at %s" % game.as_posix())
        done = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=game, capture_output=True, text=True
        )
        if done.returncode != 0:
            raise SystemExit("%s is not inside a git repository" % game.as_posix())
        return Path(done.stdout.strip()).resolve()

    def git(self, *args, check=True):
        done = subprocess.run(
            ["git"] + list(args), cwd=self.root, capture_output=True, text=True, encoding="utf-8", errors="replace"
        )
        if check and done.returncode != 0:
            raise Stop("git %s failed: %s" % (" ".join(args), one_line(done.stderr or done.stdout)))
        return done

    def write_owned(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))
        self.owned[rel] = path.read_bytes()

    def adopt(self, rel):
        """Record a file another factory tool just wrote on this tool's behalf."""
        self.owned[rel] = (self.root / rel).read_bytes()

    def restore_owned(self):
        for rel, data in self.owned.items():
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def log(self, step, result, detail=""):
        rel = "%s/reports/run-log.md" % self.game
        path = self.root / rel
        text = path.read_text(encoding="utf-8") if path.is_file() else (
            "# Factory run log\n\nOne line per step, newest last. Written by "
            "`factory/tools/run_factory.py`.\n\n| Time | Step | Result | Detail |\n| --- | --- | --- | --- |\n"
        )
        detail = one_line(detail, 300).replace("|", "/")
        self.write_owned(rel, text + "| %s | %s | %s | %s |\n" % (now(), step, result, detail))
        print("[%s] %s: %s %s" % (now(), step, result, ("(" + one_line(detail, 120) + ")") if detail else ""))

    def state(self, stage, status, note=None):
        cmd = [sys.executable, str(self.root / "factory/tools/state.py"), "set", self.game, stage, status]
        if note is not None:
            cmd += ["--note", note]
        done = subprocess.run(cmd, cwd=self.root, capture_output=True, text=True)
        if done.returncode != 0:
            raise Stop("state.py could not record %s %s: %s" % (stage, status, one_line(done.stderr)))
        self.adopt("%s/state.json" % self.game)

    def next_stage(self):
        data = json.loads((self.game_path / "state.json").read_text(encoding="utf-8"))
        status = {s["id"]: s.get("status") for s in data["stages"]}
        for stage in gate.STAGES:
            if status.get(stage) != "passed":
                return stage, status.get(stage)
        return None, None

    def run_gate(self, stage):
        done = subprocess.run(
            [sys.executable, str(self.root / "factory/tools/gate.py"), self.game, stage],
            cwd=self.root, capture_output=True, text=True,
        )
        return done.returncode == 0, (done.stdout + done.stderr).strip()

    # --------------------------------------------------------- task index

    def index_path(self):
        return self.game_path / "tasks" / "index.json"

    def load_index(self):
        return json.loads(self.index_path().read_text(encoding="utf-8"))

    def set_task_status(self, task_id, status):
        data = self.load_index()
        entries = data["tasks"] if isinstance(data, dict) else data
        for entry in entries:
            if isinstance(entry, dict) and str(entry.get("id")) == task_id:
                entry["status"] = status
                break
        else:
            raise Stop("task %s is not in %s" % (task_id, self.index_path().as_posix()))
        rel = "%s/tasks/index.json" % self.game
        self.write_owned(rel, json.dumps(data, indent=2, ensure_ascii=False) + "\n")

    def next_task(self):
        """The first pending task whose dependencies are all done, in index order.

        Returns (task, None), or (None, reason) when nothing can run.
        """
        tasks, err = gate.load_tasks(self.game_path)
        if err:
            raise Stop(err)
        status = {t["id"]: t["status"] for t in tasks}
        blocked = [t["id"] for t in tasks if t["status"] == "blocked"]
        for task in tasks:
            if task["status"] != "pending":
                continue
            if all(status.get(d) == "done" for d in task["depends_on"]):
                return task, None
        pending = [t["id"] for t in tasks if t["status"] == "pending"]
        if not pending:
            return None, "no pending tasks"
        if blocked:
            return None, "task(s) %s are blocked, and every pending task waits on them" % ", ".join(blocked)
        return None, "pending task(s) %s wait on tasks that are not done" % ", ".join(pending)

    # ------------------------------------------------------------ the guard

    def changed_paths(self, base):
        tracked = self.git("diff", "--name-only", "--no-renames", "-z", base).stdout.split("\0")
        untracked = self.git("ls-files", "--others", "--exclude-standard", "-z").stdout.split("\0")
        paths = sorted({p for p in tracked + untracked if p})
        # Files this tool wrote itself are not the agent's change, unless the
        # agent changed them after this tool did.
        return [p for p in paths if not (p in self.owned and self._bytes(p) == self.owned[p])]

    def _bytes(self, rel):
        path = self.root / rel
        return path.read_bytes() if path.is_file() else None

    def forbidden(self, rel, stage):
        """Why an agent at this stage may not change `rel`, or None if it may."""
        game = self.game + "/"
        if rel == ".env" or rel.endswith("/.env"):
            return ".env is never touched"
        if rel.startswith(".claude/"):
            return ".claude/ holds the agents; agents do not edit agents"
        if rel.startswith("factory/") and not (stage == "built" and rel in TEST_ENTRY):
            return "factory/ is the factory, not the game"
        if rel.startswith("games/") and not rel.startswith(game):
            return "another game's folder"
        inner = rel[len(game):] if rel.startswith(game) else None
        if inner is None:
            return None
        if inner == "state.json":
            return "state.json changes only through state.py"
        if inner == "spec.md":
            return "the spec is the design; a person changes it"
        if inner.startswith("design/"):
            return "the approved design folder"
        if inner == "tasks/index.json" and stage == "built":
            return "the task index belongs to the orchestrator"
        if inner.startswith("reports/"):
            return "reports are written by the orchestrator"
        for sub, owner in (("config/", "spec_parsed"), ("tuning/", "economy_tuned")):
            if inner.startswith(sub) and stage != owner:
                return "%s is generated; change the spec and rerun agents 1 and 2" % sub
        return None

    def allowed(self, rel, stage, brief=None):
        game = self.game + "/"
        inner = rel[len(game):] if rel.startswith(game) else None
        if stage != "built":
            return inner is not None and any(inner.startswith(p) for p in STAGE_WRITES[stage])
        if inner is not None and (inner.startswith("src/") or inner.startswith("tasks/")):
            return True
        if rel in TEST_ENTRY or TEST_FILE.search(rel):
            return True
        if brief is not None:
            for name in named_paths(brief):
                for cand in (name, game + name):
                    if rel == cand.rstrip("/") or (cand.endswith("/") and rel.startswith(cand)):
                        return True
        return False

    def guard(self, base, stage, brief=None):
        """Return a list of rule breaks in the agent's change since `base`."""
        breaks = []
        head = self.git("rev-parse", "HEAD").stdout.strip()
        if head != base:
            # Fold the agent's own commits back into the working tree, so the
            # checks below see them and only this tool's commit lands.
            self.git("reset", "--soft", base)
            self.log("guard", "note", "the agent committed on its own; folded back into the working tree")
        if self.upstream() != self.upstream_before:
            self.next_step = "An agent pushed on its own. Check the remote branch by hand before running again."
            raise Stop("an agent pushed to the remote on its own, which only this tool may do")
        if self.env_stat() != self.env_before:
            breaks.append(".env changed")
        for rel in self.changed_paths(base):
            why = self.forbidden(rel, stage)
            if why is None and not self.allowed(rel, stage, brief):
                why = "outside the paths this run may change"
            if why:
                breaks.append("%s: %s" % (rel, why))
        return breaks

    def env_stat(self):
        # Compare size and modification time only. Nothing here reads .env.
        try:
            st = (self.root / ".env").stat()
            return (st.st_size, st.st_mtime_ns)
        except OSError:
            return None

    def revert_to(self, base):
        self.git("reset", "--hard", base)
        self.git("clean", "-fdq")
        self.restore_owned()

    # ----------------------------------------------------------- agent runs

    def run_agent(self, agent, prompt, minutes, label, attempt):
        """Start one fresh headless agent run. Return (ok, result_text)."""
        if self.policy()["paused"]:
            raise Stop("production paused in factory/executor.json")
        if not self.locked:
            try:
                with exclusive(self.control_dir):
                    self.locked = True
                    return self.run_agent(agent, prompt, minutes, label, attempt)
            except (PolicyError, OSError) as exc:
                raise Stop(str(exc)) from exc
            finally:
                self.locked = False
        policy = self.policy()
        if self.args.agent_cmd:
            raise Stop("alternate executor disabled; use subprocess mocks")
        if not 1 <= attempt <= min(2, policy["attempts"]):
            raise Stop("at most two total attempts permitted")
        task_key = self.game + ":" + label
        try:
            expected = self.ledger.admit(policy, task_key)
            if attempt != expected or attempt > getattr(self.args, "attempts", 2):
                raise PolicyError("attempt does not match persistent ledger")
        except PolicyError as exc:
            raise Stop(str(exc)) from exc
        deadline = self.deadlines.setdefault(task_key, time.monotonic() + min(
            policy["task_timeout_seconds"], getattr(self.args, "task_minutes", 10) * 60))
        try:
            seconds = min(policy["call_timeout_seconds"], minutes * 60, deadline - time.monotonic(),
                          self.ledger.remaining_seconds(task_key, min(policy["task_timeout_seconds"],
                                                        getattr(self.args, "task_minutes", 10) * 60)))
        except PolicyError as exc:
            raise Stop(str(exc)) from exc
        if seconds <= 0:
            raise Stop("task deadline exhausted")
        env = dict(os.environ, FACTORY_AGENT=agent, FACTORY_TASK=label, FACTORY_ATTEMPT=str(attempt))
        # The agent does not need publishing credentials. Do not pass them on.
        env.pop("ROBLOX_API_KEY", None)
        exe = shutil.which("codex")
        if exe is None:
            raise Stop("the codex CLI is not on PATH")
        prompt = self.role_instructions(agent) + "\n\n# Assignment for this run\n\n" + prompt
        if len(prompt) > policy["prompt_max_chars"]:
            raise Stop("prompt exceeds context allowance; narrow the brief")
        scratch = self.game_path / "build"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="factory-codex-", dir=scratch) as temp_dir:
            last_message = Path(temp_dir) / "last-message.txt"
            argv = [exe, "exec", "--sandbox", "workspace-write", "-c", "approval_policy=\"never\"",
                    "--model", policy["model"], "-c", 'model_reasoning_effort="%s"' % policy["effort"],
                    "-c", "model_auto_compact_token_limit=16000",
                    "-c", "model_context_window=24000",
                    "-c", "features.multi_agent=false",
                    "-c", "features.goals=false",
                    "-c", "features.memories=false",
                    "-c", "tool_output_token_limit=1500",
                    "--ephemeral", "--json", "--output-last-message", str(last_message), "-"]
            try:
                if self.policy() != policy:
                    raise PolicyError("policy changed during preparation; launch refused")
                start = self.ledger.start(policy, task_key, agent,
                                          task_seconds=getattr(self.args, "task_minutes", 10) * 60)
            except PolicyError as exc:
                raise Stop(str(exc)) from exc
            t0 = time.monotonic()
            out, err, final = "", "", ""
            status = "launch_error"
            ok = False
            try:
                proc = subprocess.Popen(
                    argv, cwd=self.root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace",
                    start_new_session=os.name != "nt",
                    creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
                )
                status = "finished"
                out, err = proc.communicate(prompt, timeout=seconds)
                if proc.returncode != 0:
                    status = "failed"
                final = last_message.read_text(encoding="utf-8").strip() if last_message.is_file() else ""
                ok, report = self.codex_result(proc.returncode, out, err, final)
            except subprocess.TimeoutExpired:
                status = "timeout"
                self.kill_tree(proc)
                out, err = proc.communicate()
                report = "the %s run hit its %.3f second limit and was stopped" % (agent, seconds)
            except KeyboardInterrupt:
                status = "interrupted"
                self.kill_tree(proc)
                out, err = proc.communicate()
                raise
            except OSError as exc:
                report = "executor failed: %s" % exc
            finally:
                row = self.ledger.finish(start, out, time.monotonic() - t0, status, ok)
                trace = "%s/reports/agents/%s-attempt%d.jsonl" % (self.game, label, start["attempt"])
                self.write_owned(trace, out)
        if not row["ok"] and ok:
            report += "\nRequired usage unknown or effective model mismatch; review ledger."
        return row["ok"], report

    def role_instructions(self, agent):
        """Load the portable body of the existing factory role definition."""
        source = self.root / ".claude" / "agents" / (agent + ".md")
        body = source.read_text(encoding="utf-8")
        if body.startswith("---\n"):
            body = body.split("---\n", 2)[2]
        return ("# Factory role: %s\n\n" % agent + body.strip()
                + "\n\nThe assignment below overrides role text about committing, pushing, "
                  "publishing, tests, or broad scope. Read only the brief and named source files. "
                  "Consult specific spec/config sections only when necessary. Do not read old "
                  "reports, exports or full directory trees. Do not spawn agents or invoke AI. "
                  "Do not run verification/status/tests: the orchestrator runs scripts once. "
                  "Leave those checklist boxes for the orchestrator. Follow local-only limits.")

    @staticmethod
    def codex_result(returncode, stdout, stderr, final):
        """Summarize Codex JSONL and final message without treating output as success."""
        events = []
        bad_lines = 0
        for line in stdout.splitlines():
            if not line.strip():
                continue
            try:
                event = json.loads(line)
                if isinstance(event, dict):
                    events.append(event)
                else:
                    bad_lines += 1
            except ValueError:
                bad_lines += 1
        errors = [str(e.get("message") or e.get("error") or e.get("type"))
                  for e in events if e.get("type") in ("error", "turn.failed")]
        completed = any(e.get("type") == "turn.completed" for e in events)
        if not final:
            for event in reversed(events):
                item = event.get("item") or {}
                if (event.get("type") == "item.completed" and isinstance(item, dict)
                        and item.get("type") == "agent_message"):
                    final = str(item.get("text") or "").strip()
                    break
        details = ["Exit code: %d; JSONL events: %d; turn completed: %s." %
                   (returncode, len(events), "yes" if completed else "no")]
        if bad_lines:
            details.append("Non-JSON output lines: %d." % bad_lines)
        if errors:
            details.append("Errors: " + tail("; ".join(errors), 1200))
        if stderr.strip():
            details.append("stderr: " + tail(stderr, 1200))
        details.append("Final message:\n" + (final or "(missing)"))
        ok = returncode == 0 and completed and bool(final) and not errors and bad_lines == 0
        return ok, "\n\n".join(details)

    @staticmethod
    def kill_tree(proc):
        if os.name == "nt":
            killed = subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True)
            if killed.returncode != 0 and proc.poll() is None:
                proc.kill()
        else:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                proc.kill()

    def save_agent_report(self, label, attempt, text):
        rel = "%s/reports/agents/%s-attempt%d.md" % (self.game, label, attempt)
        self.write_owned(rel, "# %s, attempt %d\n\n%s\n" % (label, attempt, text or "(no report)"))
        return rel

    # --------------------------------------------------------------- checks

    def run_check(self, argv, expect):
        """Run one check from the repo root. Return (ok, output)."""
        argv = list(argv)
        if argv[0] in ("python", "python3", "py"):
            argv[0] = sys.executable
        elif argv[0] == "grep" and shutil.which("grep") is None:
            code, out = builtin_grep(argv, self.root)
            return self._judge(code, out, expect)
        else:
            exe = shutil.which(argv[0])
            if exe is None:
                return False, "%s is not on PATH" % argv[0]
            argv[0] = exe
        try:
            done = subprocess.run(
                argv, cwd=self.root, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=CHECK_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            return False, "timed out after %d seconds" % CHECK_TIMEOUT
        return self._judge(done.returncode, (done.stdout + done.stderr).strip(), expect)

    @staticmethod
    def _judge(code, out, expect):
        if expect == "empty":
            return (not out.strip()), (out or "no matches")
        return code == 0, (out or "exit code %d" % code)

    def task_checks(self, brief):
        g = self.game
        (self.game_path / "build").mkdir(parents=True, exist_ok=True)
        checks = [(argv, expect) for argv, expect in brief_commands(done_when_items(brief))]
        if (self.root / "factory/tools/run_tests.py").is_file():
            checks.append((["python", "factory/tools/run_tests.py", g], "zero"))
        checks += [
            (["rojo", "build", g, "-o", "%s/build/game.rbxl" % g], "zero"),
            (["selene", "%s/src" % g], "zero"),
            (["stylua", "--check", "%s/src" % g], "zero"),
        ]
        seen, unique = set(), []
        for argv, expect in checks:
            key = (" ".join(argv), expect)
            if key not in seen:
                seen.add(key)
                unique.append((argv, expect))
        return unique

    def verify_task(self, task, base):
        """Return a list of failures, each a (title, output) pair."""
        brief = task["path"]
        failures = []
        left = [
            "line %d: %s" % (i["line"], one_line(i["text"], 100))
            for i in done_when_items(brief)
            if not i["ticked"] and not COMMIT_ITEM.search(i["text"])
            and not brief_commands([i])
        ]
        if left:
            failures.append(("Done-when boxes left unticked", "\n".join(left)))
        for rel in self.changed_paths(base):
            path = self.root / rel
            try:
                if path.is_file() and EM_DASH in path.read_text(encoding="utf-8"):
                    failures.append(("em dash in a changed file", rel))
            except (OSError, UnicodeDecodeError):
                pass
        # The checks are independent, so run them side by side. Agent shells
        # can be short (45 seconds), and in sequence the checks plus the
        # orchestrator's own work did not fit.
        checks = self.task_checks(brief)
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(checks))) as pool:
            results = list(pool.map(lambda c: self.run_check(c[0], c[1]), checks))
        for (argv, expect), (ok, out) in zip(checks, results):
            name = " ".join(argv) + (" (must find nothing)" if expect == "empty" else "")
            self.log("check %s" % task["id"], "pass" if ok else "FAIL", name)
            if not ok:
                failures.append((name, tail(out, 2500)))
        if not failures:
            lines = brief.read_text(encoding="utf-8").splitlines(keepends=True)
            for item in done_when_items(brief):
                if brief_commands([item]) and not item["ticked"]:
                    lines[item["line"] - 1] = lines[item["line"] - 1].replace("- [ ]", "- [x]", 1)
            brief.write_text("".join(lines), encoding="utf-8")
        return failures

    # -------------------------------------------------------------- prompts

    def coder_prompt(self, task, attempt, feedback):
        g = self.game
        brief = task["path"].relative_to(self.root).as_posix()
        checks = "\n".join("- `%s`" % " ".join(a) for a, _ in self.task_checks(task["path"]))
        text = """You are the coder agent, started headless by factory/tools/run_factory.py.
Nobody can answer questions during this run. Decide, or stop and report.

Do the task brief `{brief}` and nothing else. Game folder: `{g}`.

Rules for this run, on top of your agent instructions:
- Do not commit, push, reset or check out. The orchestrator checks your work
  and commits it.
- Change only `{g}/src/`, the brief itself (to tick it), test files
  (`*.spec.luau`, `factory/tools/run_tests.py`, `factory/tools/run_tests`),
  and files the brief names by path. A change anywhere else, and any change to
  `{g}/config/`, `{g}/tuning/`, `{g}/spec.md`, `{g}/state.json`,
  `{g}/tasks/index.json`, `factory/` or `.claude/`, gets the whole attempt
  reverted.
- Never read or print `.env`. Never publish anything.
- Do not run tests, status, gates or verification commands. Scripts in the
  orchestrator do those once and tick command checks. Leave those boxes and
  the box about committing to the orchestrator.

When you finish, the orchestrator runs these itself and the task passes only
if all of them pass and every Done-when box is ticked:
{checks}

This is attempt {attempt} of {total}.""".format(
            brief=brief, g=g, checks=checks, attempt=attempt, total=self.args.attempts
        )
        if feedback:
            text += "\n\nThe previous attempt failed. " + tail(feedback, FEEDBACK_CHARS)
        return text + "\n\nEnd with a short report: what you built, each check and its result, and anything left.\n"

    def stage_prompt(self, stage, agent, gate_out, attempt, feedback):
        text = """You are the {agent} agent, started headless by factory/tools/run_factory.py.
Nobody can answer questions during this run. Decide, or stop and report.

Game folder: `{g}`. Do your job for this game so the `{stage}` gate passes.
The gate is `python factory/tools/gate.py {g} {stage}` and it now says:

{gate_out}

Rules for this run, on top of your agent instructions:
- Do not commit or push. The orchestrator checks your work and commits it.
- Write only under {writes}. Anything else gets the attempt reverted.
- Never read or print `.env`. Never publish anything.

This is attempt {attempt} of {total}.""".format(
            agent=agent, g=self.game, stage=stage, gate_out=tail(gate_out, FEEDBACK_CHARS),
            writes=", ".join("`%s/%s`" % (self.game, w) for w in STAGE_WRITES[stage]),
            attempt=attempt, total=self.args.attempts,
        )
        if feedback:
            text += "\n\nThe previous attempt failed. " + tail(feedback, FEEDBACK_CHARS)
        return text + "\n\nEnd with a short report of what you did and what is left.\n"

    # ---------------------------------------------------------------- commit

    def commit(self, message):
        self.git("add", "-A")
        if not self.git("diff", "--cached", "--name-only").stdout.strip():
            return self.git("rev-parse", "--short", "HEAD").stdout.strip()
        self.git("commit", "-q", "-m", message)
        self.owned.clear()
        sha = self.git("rev-parse", "--short", "HEAD").stdout.strip()
        # Nothing is logged from here on: a log line now would land after the
        # commit and leave the tree dirty. The caller logs the outcome.
        if not self.args.push:
            return sha
        upstream = self.git("rev-parse", "--abbrev-ref", "@{u}", check=False)
        if upstream.returncode == 0:
            pushed = self.git("push", "-q", check=False)
        else:
            pushed = self.git("push", "-q", "-u", "origin", self.branch, check=False)
        if pushed.returncode != 0:
            raise Stop("commit %s was made but the push failed: %s" % (sha, one_line(pushed.stderr)))
        self.upstream_before = self.upstream()
        return sha

    # ---------------------------------------------------------------- stages

    def stage_with_agent(self, stage):
        agent = STAGE_AGENTS[stage]
        # These stages are deterministic: never pay an agent to run a script.
        if stage in ("spec_parsed", "economy_tuned"):
            g = self.game
            argv = (["python", "factory/tools/parse_spec.py", g + "/spec.md", g + "/config"]
                    if stage == "spec_parsed" else
                    ["python", "factory/tools/simulate_economy.py", g + "/config", g + "/tuning"])
            ran, output = self.run_check(argv, "zero")
            ok, gate_out = self.run_gate(stage)
            if not ran or not ok:
                raise Stop("deterministic stage failed: " + tail(output + "\n" + gate_out, 2000))
            self.state(stage, "passed", gate_out)
            self.commit("Factory: %s passes deterministic gate" % stage)
            return
        first_attempt = self.next_attempt(stage)
        limit = min(self.args.attempts, self.policy()["attempts"])
        self.state(stage, "running")
        feedback = ""
        attempted, accepted = False, False
        for attempt in range(first_attempt, limit + 1):
            ok, gate_out = self.run_gate(stage)
            if ok:
                break
            base = self.git("rev-parse", "HEAD").stdout.strip()
            self.log(stage, "agent start", "%s, attempt %d: %s" % (agent, attempt, gate_out))
            ran, report = self.run_agent(
                agent, self.stage_prompt(stage, agent, gate_out, attempt, feedback),
                self.args.task_minutes, stage, attempt,
            )
            attempted, accepted = True, ran
            rel = self.save_agent_report(stage, attempt, report)
            breaks = self.guard(base, stage)
            if breaks:
                accepted = False
                self.revert_to(base)
                self.log(stage, "REJECTED", "; ".join(breaks))
                feedback = "It changed files it may not change, so all of it was reverted:\n" + "\n".join(breaks)
                continue
            if not ran:
                self.log(stage, "agent failed", report)
                feedback = report
                continue
            self.log(stage, "agent done", "report in %s" % rel)
        ok, gate_out = self.run_gate(stage)
        if ok and (not attempted or accepted):
            if attempted:
                self.ledger.task_done(self.game + ":" + stage)
            self.state(stage, "passed", gate_out.replace("OK: ", ""))
            self.log(stage, "passed", gate_out)
            self.commit("Factory: %s stage passes its gate" % stage)
            return
        self.state(stage, "blocked", gate_out)
        self.log(stage, "BLOCKED", gate_out)
        self.problems.append({"what": "stage %s" % stage, "reason": gate_out, "detail": feedback})
        self.next_step = (
            "Read the agent reports in `%s/reports/agents/`, fix what the gate names, then run "
            "`python factory/tools/state.py set %s %s pending` and start the run again." % (self.game, self.game, stage)
        )
        raise Stop("stage %s is blocked: %s" % (stage, gate_out))

    def stage_built(self):
        self.state("built", "running")
        built = 0
        while True:
            task, why = self.next_task()
            if task is None:
                if why == "no pending tasks":
                    break
                self.state("built", "blocked", why)
                self.next_step = self.unblock_hint()
                raise Stop(why)
            if built >= self.args.max_tasks:
                note = "stopped at the limit of %d task(s) per run; next is task %s" % (self.args.max_tasks, task["id"])
                self.state("built", "pending", note)
                self.log("built", "paused", note)
                self.headline = "Stopped at the task limit after %d task(s)." % built
                self.next_step = "Run it again to build task %s (%s)." % (task["id"], task["title"])
                return False
            self.build_task(task)
            built += 1
        ok, gate_out = self.run_gate("built")
        if not ok:
            self.state("built", "blocked", gate_out)
            self.log("built", "BLOCKED", gate_out)
            self.problems.append({"what": "stage built", "reason": gate_out, "detail": ""})
            self.next_step = "Every task is done but the built gate fails. Fix what it names and run again."
            raise Stop("the built gate fails: %s" % gate_out)
        self.state("built", "passed", gate_out.replace("OK: ", ""))
        self.log("built", "passed", gate_out)
        self.commit("Factory: built stage passes its gate")
        return True

    def build_task(self, task):
        tid = task["id"]
        first_attempt = self.next_attempt("task-" + tid)
        limit = min(self.args.attempts, self.policy()["attempts"])
        base = self.git("rev-parse", "HEAD").stdout.strip()
        deadline = time.time() + self.args.task_minutes * 60
        feedback = ""
        attempt = 0
        reports = []
        for attempt in range(first_attempt, limit + 1):
            minutes_left = (deadline - time.time()) / 60
            if minutes_left <= 0:
                feedback = "the task used its %d minute limit" % self.args.task_minutes
                self.log("task %s" % tid, "out of time", feedback)
                break
            self.log("task %s" % tid, "coder start", "attempt %d of %d: %s" % (attempt, self.args.attempts, task["title"]))
            ran, report = self.run_agent(
                "coder", self.coder_prompt(task, attempt, feedback), minutes_left, "task-%s" % tid, attempt
            )
            reports.append(self.save_agent_report("task-%s" % tid, attempt, report))
            breaks = self.guard(base, "built", task["path"])
            if breaks:
                self.revert_to(base)
                self.log("task %s" % tid, "REJECTED", "; ".join(breaks))
                feedback = (
                    "It changed files it may not change, so every change from that attempt was "
                    "reverted and you start from a clean tree:\n" + "\n".join("- " + b for b in breaks)
                )
                continue
            if not ran:
                self.log("task %s" % tid, "coder failed", report)
            failures = self.verify_task(task, base)
            if ran and not failures:
                tick_commit_items(task["path"])
                self.set_task_status(tid, "done")
                self.ledger.task_done(self.game + ":task-" + tid)
                self.log("task %s" % tid, "passed", "attempt %d" % attempt)
                sha = self.commit("Task %s: %s\n\nBuilt by the coder agent through factory/tools/run_factory.py,\n"
                                  "attempt %d. Every check in the brief and the build checks pass." % (tid, task["title"], attempt))
                self.log("task %s" % tid, "committed", sha)
                self.done.append({"id": tid, "title": task["title"], "attempts": attempt, "commit": sha})
                return
            feedback = (
                ("The coder run itself failed: %s\n\n" % tail(report, 1500) if not ran else "")
                + "These checks failed. Your changes are still in the working tree; fix them:\n\n"
                + "\n\n".join("### %s\n```\n%s\n```" % f for f in failures)
            )
            feedback = tail(feedback, FEEDBACK_CHARS)
            self.log("task %s" % tid, "checks failed", "; ".join(f[0] for f in failures))
        self.block_task(task, base, attempt, feedback, reports)

    def block_task(self, task, base, attempts, feedback, reports):
        tid = task["id"]
        patch_rel = "%s/reports/blocked/task-%s.patch" % (self.game, tid)
        self.git("add", "-A")
        patch = self.git("diff", "--cached", "--binary", base).stdout
        mine = {p for p in self.owned}
        self.git("reset", "-q")
        # Keep the agent's work as a patch, without this tool's own files.
        patch = "".join(
            chunk for chunk in re.split(r"(?m)^(?=diff --git )", patch)
            if chunk and not any(chunk.split("\n", 1)[0].endswith(" b/" + m) for m in mine)
        )
        self.revert_to(base)
        if patch.strip():
            self.write_owned(patch_rel, patch)
        self.set_task_status(tid, "blocked")
        reason = "failed after %d attempt(s)" % attempts
        self.state("built", "blocked", "task %s %s" % (tid, reason))
        self.log("task %s" % tid, "BLOCKED", reason)
        self.problems.append({
            "what": "task %s (%s)" % (tid, task["title"]),
            "reason": reason,
            "detail": feedback,
            "patch": patch_rel if patch.strip() else None,
            "reports": reports,
        })
        self.next_step = self.unblock_hint(tid, patch_rel if patch.strip() else None)
        self.commit("Task %s blocked: %s\n\nThe coder's last attempt is saved as a patch in reports/blocked/." % (tid, task["title"]))
        raise Stop("task %s is blocked" % tid)

    def unblock_hint(self, tid=None, patch=None):
        tid = tid or "<id>"
        start = " You can start from the saved work with `git apply %s`." % patch if patch else ""
        return (
            "Read what failed above and the coder reports, and fix the cause: the brief, the "
            "code, or a tool.%s Commit the fix, then run "
            "`python factory/tools/run_factory.py %s --unblock %s`." % (start, self.game, tid)
        )

    # ---------------------------------------------------------------- finish

    def finish(self, tid):
        """Check and commit a task an agent already made in the working tree.

        For agent shells too short for a full run (each git call can take
        seconds on a mounted folder): no stage gates, no agent, no run
        report. The same path guard and checks as a normal attempt. Nothing
        is reverted on failure; the agent fixes it and runs again.
        """
        if not self.locked or self.policy()["paused"]:
            raise Stop("--finish requires an unpaused, locked execute()")
        # --finish cannot manufacture a measured task after an unrecorded agent run.
        rows = self.ledger.read()
        if any(r["event"] == "task_done" and r["task"] == self.game + ":task-" + tid for r in rows):
            raise Stop("task already completed; duplicate --finish refused")
        previous = [r for r in rows if r["event"] == "finished" and r["task"] == self.game + ":task-" + tid]
        if not previous or not previous[-1]["ok"]:
            raise Stop("--finish requires a successful measured invocation for this task")
        task, reason = self.next_task()
        if task is None or task["id"] != tid:
            print("FINISH REFUSED: task %s is not the next runnable task (%s)" % (
                tid, reason if task is None else "next is task %s" % task["id"]))
            return 1
        base = self.git("rev-parse", "HEAD").stdout.strip()
        # The agent already ran, so these baselines are taken now: the guard
        # still catches pushes and .env changes made from here on, and every
        # path rule applies to the whole working tree change.
        self.upstream_before = self.upstream()
        self.env_before = self.env_stat()
        try:
            breaks = self.guard(base, "built", task["path"])
        except Stop as stop:
            print("FINISH REFUSED: %s" % stop)
            return 1
        if breaks:
            print("FINISH REFUSED: changed files the task may not change:\n"
                  + "\n".join("- " + b for b in breaks))
            return 1
        failures = self.verify_task(task, base)
        if failures:
            print("FINISH FAILED:\n" + "\n\n".join("### %s\n%s" % f for f in failures))
            return 1
        tick_commit_items(task["path"])
        self.set_task_status(tid, "done")
        self.ledger.task_done(self.game + ":task-" + tid)
        self.log("task %s" % tid, "passed", "checked with --finish")
        sha = self.commit("Task %s: %s\n\nBuilt by the coder agent and checked by factory/tools/run_factory.py\n"
                          "--finish. Every check in the brief and the build checks pass." % (tid, task["title"]))
        # One commit only: a second "run log" commit was cut off by the 45 s
        # shell limit every time, leaving a staged line and a stale lock.
        print("FINISHED: task %s committed as %s" % (tid, sha))
        return 0

    # ------------------------------------------------------------------ main

    def preflight(self):
        if self.git("status", "--porcelain").stdout.strip():
            raise SystemExit("the working tree has uncommitted changes. Commit or stash them first, "
                             "so a revert can never take a person's work with it.")
        if self.git("ls-files", ".env").stdout.strip():
            raise SystemExit(".env is tracked by git. Remove it from the index before running.")
        self.env_before = self.env_stat()
        self.upstream_before = self.upstream()

    def upstream(self):
        """The remote branch's commit as this clone last saw it, or None."""
        done = self.git("rev-parse", "-q", "--verify", "@{u}", check=False)
        return done.stdout.strip() or None

    def unblock(self, tid):
        self.set_task_status(tid, "pending")
        self.log("task %s" % tid, "unblocked", "set back to pending by --unblock")
        stage, status = self.next_stage()
        if stage == "built" and status == "blocked":
            self.state("built", "pending", "task %s unblocked" % tid)

    def go(self):
        if not self.locked:
            raise Stop("use execute() to acquire the repository lock")
        self.preflight()
        self.log("run", "start", "%s on branch %s, max %d task(s)" % (self.game, self.branch, self.args.max_tasks))
        try:
            if self.args.unblock:
                self.unblock(self.args.unblock)
            while True:
                stage, status = self.next_stage()
                if stage is None:
                    self.headline = "Every stage has passed."
                    break
                if status == "blocked":
                    self.next_step = self.unblock_hint() if stage == "built" else (
                        "Fix the cause, then `python factory/tools/state.py set %s %s pending`." % (self.game, stage))
                    raise Stop("stage %s is blocked from an earlier run" % stage)
                ok, gate_out = self.run_gate(stage)
                if ok:
                    self.state(stage, "passed", gate_out.replace("OK: ", ""))
                    self.log(stage, "passed", gate_out)
                    self.commit("Factory: %s stage passes its gate" % stage)
                    continue
                if stage == "built":
                    if not self.stage_built():
                        break
                elif stage in STAGE_AGENTS:
                    self.stage_with_agent(stage)
                else:
                    self.headline = "Stopped at stage %s, which has no agent yet." % stage
                    self.next_step = "Build the agent for `%s` (see factory/README.md), then run again." % stage
                    self.log(stage, "stop", "no agent for this stage yet")
                    break
        except (Stop, PolicyError) as stop:
            self.preserve_partial = True
            self.problems.append({"what": "executor", "reason": str(stop), "detail": ""})
            self.headline = "Stopped: %s." % str(stop).rstrip(".")
            self.log("run", "stop", str(stop))
        except KeyboardInterrupt:
            self.preserve_partial = True
            self.problems.append({"what": "executor", "reason": "interrupted", "detail": ""})
            self.headline = "Interrupted by a person."
            self.log("run", "stop", "interrupted")
        self.log("run", "end", "%d task(s) done, %d problem(s)" % (len(self.done), len(self.problems)))
        self.write_latest()
        try:
            if not getattr(self, "preserve_partial", False):
                self.commit("Factory run report for %s" % self.game)
        except Stop as stop:
            print("could not commit the run report: %s" % stop)
        print("\n" + (self.root / self.game / "reports/latest.md").read_text(encoding="utf-8"))
        return 1 if self.problems else 0

    def write_latest(self):
        minutes = (time.time() - self.t0) / 60
        out = ["# Latest factory run: %s" % self.game, ""]
        out.append("Started %s, took %.0f minute(s), branch `%s`%s." % (
            self.started, minutes, self.branch, " (local commits only)" if not self.args.push else " (push enabled)"))
        out += ["", "**Result:** %s" % (self.headline or "Finished."), "", "## Done this run", ""]
        if self.done:
            out += ["| Task | Title | Attempts | Commit |", "| --- | --- | --- | --- |"]
            out += ["| %s | %s | %d | %s |" % (d["id"], d["title"], d["attempts"], d["commit"]) for d in self.done]
        else:
            out.append("No task was finished.")
        out += ["", "## What failed", ""]
        if not self.problems:
            out.append("Nothing.")
        for p in self.problems:
            out.append("### %s: %s" % (p["what"], p["reason"]))
            out.append("")
            if p.get("patch"):
                out.append("The last attempt's changes were reverted and saved to `%s`." % p["patch"])
            if p.get("reports"):
                out.append("Coder reports: %s." % ", ".join("`%s`" % r for r in p["reports"]))
            if p.get("detail"):
                out += ["", "Last failure:", "", tail(p["detail"], 3000)]
            out.append("")
        out += ["", "## State now", ""]
        data = json.loads((self.game_path / "state.json").read_text(encoding="utf-8"))
        for s in data["stages"]:
            note = (": " + s["note"]) if s.get("note") else ""
            out.append("- `%s` %s%s" % (s["id"], s.get("status"), note))
        try:
            tasks, _ = gate.load_tasks(self.game_path)
            counts = {}
            for t in tasks or []:
                counts[t["status"]] = counts.get(t["status"], 0) + 1
            out += ["", "Tasks: " + ", ".join("%d %s" % (n, s) for s, n in sorted(counts.items()))]
        except (OSError, ValueError):
            pass
        out += ["", "## Next", "", self.next_step or "Nothing is waiting.", "",
                "Every step of every run is in `reports/run-log.md`."]
        self.write_owned("%s/reports/latest.md" % self.game, "\n".join(out) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build one game from its state and task list")
    ap.add_argument("game_dir")
    ap.add_argument("--max-tasks", type=int, default=1)
    ap.add_argument("--task-minutes", type=int, default=10)
    ap.add_argument("--attempts", type=int, default=2)
    ap.add_argument("--budget-usd", type=float, default=None,
                    help="unsupported by Codex; rejected to avoid implying a spend cap")
    ap.add_argument("--unblock", default=None, metavar="ID")
    push = ap.add_mutually_exclusive_group()
    push.add_argument("--push", action="store_true", help="explicitly allow pushing commits")
    push.add_argument("--no-push", action="store_true", help="legacy spelling; local commits are already the default")
    ap.add_argument("--agent-cmd", default=None, help="disabled; use mocks, never another executor")
    ap.add_argument("--finish", default=None, metavar="ID",
                    help="check and commit task ID from the working tree, for short agent shells")
    ap.add_argument("--executor-status", action="store_true", help="read-only policy/ledger, no AI")
    args = ap.parse_args(argv)
    if args.max_tasks < 1 or args.attempts < 1 or args.task_minutes < 1:
        ap.error("--max-tasks, --attempts and --task-minutes must be at least 1")
    if args.attempts > 2:
        ap.error("at most two total attempts are permitted")
    if args.budget_usd is not None:
        ap.error("--budget-usd is unsupported by codex exec; no USD spend cap is available")
    if args.executor_status:
        run = Run(args)
        try:
            policy = run.policy()
            rows = run.ledger.read()
            try:
                run.ledger.admit(policy, run.game + ":status")
                admission = "available (not authorization to resume)"
            except PolicyError as exc:
                admission = str(exc)
            print(json.dumps({"policy": policy, "admission": admission,
                              "ledger_path": str(run.ledger.path), "ledger": rows}, indent=2))
            return 0
        except (PolicyError, Stop) as exc:
            print("BLOCKED: %s" % exc)
            return 1
    return Run(args).execute()


if __name__ == "__main__":
    sys.exit(main())

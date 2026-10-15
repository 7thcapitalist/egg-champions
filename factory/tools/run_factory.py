#!/usr/bin/env python3
"""Factory tool: build one game from its state and task list, nobody typing.

Usage:
    python factory/tools/run_factory.py <game-dir> [options]

Options:
    --max-tasks N       build at most N tasks this run (default 5)
    --task-minutes M    wall-clock limit for one task, all attempts (default 60)
    --attempts N        tries per task or stage, the first included (default 3)
    --budget-usd X      spend cap passed to each agent run (default: none)
    --unblock ID        set a blocked task back to pending before starting
    --no-push           commit but do not push (for scratch branches)
    --agent-cmd CMD     run CMD in place of `claude` for every agent run. For
                        testing this tool only. CMD gets the prompt on stdin
                        and FACTORY_AGENT, FACTORY_TASK and FACTORY_ATTEMPT in
                        its environment.

The loop reads `<game-dir>/state.json` and works on the first stage that has
not passed:
- A stage whose gate already passes is recorded as passed and skipped.
- `spec_parsed`, `economy_tuned` and `planned` run their agent, then the gate.
- `built` walks `<game-dir>/tasks/index.json` in dependency order. Each task
  gets a fresh headless coder run on its one brief, then the orchestrator
  checks the result itself: only allowed paths changed, every Done-when box is
  ticked, the brief's Done-when commands pass, and so do the test entry point,
  rojo, selene and stylua. Pass: mark done, commit, push. Fail: retry with
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
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import concurrent.futures  # noqa: E402
import gate  # noqa: E402  lives next to this file

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
FEEDBACK_CHARS = 6000  # failing output handed back to the coder
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
        self.cost = 0.0
        self.branch = self.git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()

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
        env = dict(os.environ, FACTORY_AGENT=agent, FACTORY_TASK=label, FACTORY_ATTEMPT=str(attempt))
        if self.args.agent_cmd:
            argv = shlex.split(self.args.agent_cmd, posix=os.name != "nt")
        else:
            exe = shutil.which("claude")
            if exe is None:
                raise Stop("the claude CLI is not on PATH")
            argv = [exe] + self.claude_flags(agent)
        proc = subprocess.Popen(
            argv, cwd=self.root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace",
            start_new_session=os.name != "nt",
        )
        try:
            out, err = proc.communicate(prompt, timeout=max(60, minutes * 60))
        except subprocess.TimeoutExpired:
            self.kill_tree(proc)
            proc.communicate()
            return False, "the %s run hit its time limit of %d minute(s) and was stopped" % (agent, minutes)
        if self.args.agent_cmd:
            return proc.returncode == 0, (out + err).strip()
        try:
            result = json.loads(out)
        except ValueError:
            return False, "the %s run exited %d with no JSON result: %s" % (agent, proc.returncode, tail(out + err, 1500))
        self.cost += float(result.get("total_cost_usd") or 0)
        text = str(result.get("result") or "").strip()
        if proc.returncode != 0 or result.get("is_error"):
            return False, "the %s run ended with an error (%s): %s" % (agent, result.get("subtype"), tail(text, 1500))
        return True, text

    def claude_flags(self, agent):
        """Headless flags. See `claude --help` and the Claude Code docs on
        running programmatically and on permissions.

        -p reads the prompt from stdin. dontAsk denies anything not allowed
        below, and `--permission-prompts none` tells the agent nobody can
        approve, so it does not wait or retry. The deny rules are a first
        line only; the orchestrator's own guard is the real check.
        """
        game = self.game
        allow = ["Read", "Glob", "Grep", "Edit", "Write", "Bash"]
        deny = [
            "Read(./.env)", "Edit(./.env)", "Edit(./.claude/**)",
            "Edit(./%s/spec.md)" % game, "Edit(./%s/state.json)" % game,
            "Bash(git commit *)", "Bash(git push *)", "Bash(git reset *)", "Bash(git checkout *)",
            "Bash(git restore *)", "Bash(git clean *)", "Bash(git rebase *)", "Bash(git stash *)",
            "Bash(rojo upload *)", "WebFetch", "WebSearch",
        ]
        if agent != "spec-parser":
            deny.append("Edit(./%s/config/**)" % game)
        if agent != "economy-tuner":
            deny.append("Edit(./%s/tuning/**)" % game)
        flags = [
            "-p", "--agent", agent,
            "--permission-mode", "dontAsk", "--permission-prompts", "none",
            "--output-format", "json", "--no-session-persistence",
            "--allowedTools", ",".join(allow),
            "--disallowedTools", ",".join(deny),
        ]
        if self.args.budget_usd:
            flags += ["--max-budget-usd", str(self.args.budget_usd)]
        return flags

    @staticmethod
    def kill_tree(proc):
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True)
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
- Tick a Done-when box only after you ran its check and saw it pass. Leave a
  box about committing to the orchestrator.

When you finish, the orchestrator runs these itself and the task passes only
if all of them pass and every Done-when box is ticked:
{checks}

This is attempt {attempt} of {total}.""".format(
            brief=brief, g=g, checks=checks, attempt=attempt, total=self.args.attempts
        )
        if feedback:
            text += "\n\nThe previous attempt failed. " + feedback
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
            agent=agent, g=self.game, stage=stage, gate_out=gate_out,
            writes=", ".join("`%s/%s`" % (self.game, w) for w in STAGE_WRITES[stage]),
            attempt=attempt, total=self.args.attempts,
        )
        if feedback:
            text += "\n\nThe previous attempt failed. " + feedback
        return text + "\n\nEnd with a short report of what you did and what is left.\n"

    # ---------------------------------------------------------------- commit

    def commit(self, message):
        self.git("add", "-A")
        if not self.git("diff", "--cached", "--name-only").stdout.strip():
            return self.git("rev-parse", "--short", "HEAD").stdout.strip()
        self.git("commit", "-q", "-m", message + "\n\nCo-Authored-By: Claude <noreply@anthropic.com>")
        self.owned.clear()
        sha = self.git("rev-parse", "--short", "HEAD").stdout.strip()
        # Nothing is logged from here on: a log line now would land after the
        # commit and leave the tree dirty. The caller logs the outcome.
        if self.args.no_push:
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
        self.state(stage, "running")
        feedback = ""
        for attempt in range(1, self.args.attempts + 1):
            ok, gate_out = self.run_gate(stage)
            if ok:
                break
            base = self.git("rev-parse", "HEAD").stdout.strip()
            self.log(stage, "agent start", "%s, attempt %d: %s" % (agent, attempt, gate_out))
            ran, report = self.run_agent(
                agent, self.stage_prompt(stage, agent, gate_out, attempt, feedback),
                self.args.task_minutes, stage, attempt,
            )
            rel = self.save_agent_report(stage, attempt, report)
            breaks = self.guard(base, stage)
            if breaks:
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
        if ok:
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
        base = self.git("rev-parse", "HEAD").stdout.strip()
        deadline = time.time() + self.args.task_minutes * 60
        feedback = ""
        attempt = 0
        reports = []
        for attempt in range(1, self.args.attempts + 1):
            minutes_left = int((deadline - time.time()) / 60)
            if minutes_left < 1:
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
            if not failures:
                tick_commit_items(task["path"])
                self.set_task_status(tid, "done")
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
        except Stop as stop:
            self.headline = "Stopped: %s." % str(stop).rstrip(".")
            self.log("run", "stop", str(stop))
        except KeyboardInterrupt:
            self.headline = "Interrupted by a person."
            self.log("run", "stop", "interrupted")
        self.log("run", "end", "%d task(s) done, %d problem(s), cost about $%.2f" % (len(self.done), len(self.problems), self.cost))
        self.write_latest()
        try:
            self.commit("Factory run report for %s" % self.game)
        except Stop as stop:
            print("could not commit the run report: %s" % stop)
        print("\n" + (self.root / self.game / "reports/latest.md").read_text(encoding="utf-8"))
        return 1 if self.problems else 0

    def write_latest(self):
        minutes = (time.time() - self.t0) / 60
        out = ["# Latest factory run: %s" % self.game, ""]
        out.append("Started %s, took %.0f minute(s), branch `%s`%s. Agent spend about $%.2f." % (
            self.started, minutes, self.branch, " (commits not pushed: --no-push)" if self.args.no_push else "",
            self.cost))
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
    ap.add_argument("--max-tasks", type=int, default=5)
    ap.add_argument("--task-minutes", type=int, default=60)
    ap.add_argument("--attempts", type=int, default=3)
    ap.add_argument("--budget-usd", type=float, default=None)
    ap.add_argument("--unblock", default=None, metavar="ID")
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--agent-cmd", default=None, help="for testing this tool: run CMD instead of claude")
    ap.add_argument("--finish", default=None, metavar="ID",
                    help="check and commit task ID from the working tree, for short agent shells")
    args = ap.parse_args(argv)
    if args.max_tasks < 1 or args.attempts < 1 or args.task_minutes < 1:
        ap.error("--max-tasks, --attempts and --task-minutes must be at least 1")
    if args.finish:
        return Run(args).finish(args.finish)
    return Run(args).go()


if __name__ == "__main__":
    sys.exit(main())

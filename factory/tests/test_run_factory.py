"""Focused executor tests. All Git mutations stay in temporary repositories."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from run_factory import Run  # noqa: E402


class CodexResultTests(unittest.TestCase):
    def test_success_uses_jsonl_and_last_message(self):
        stream = "\n".join(json.dumps(event) for event in (
            {"type": "thread.started", "thread_id": "fixture"},
            {"type": "turn.completed"},
        ))
        ok, report = Run.codex_result(0, stream, "", "Completed the fixture")
        self.assertTrue(ok)
        self.assertIn("Completed the fixture", report)

    def test_failure_and_missing_final_cannot_pass(self):
        for code, stream, final in (
            (1, '{"type":"turn.completed"}', "done"),
            (0, '{"type":"turn.failed","message":"blocked"}', "done"),
            (0, '{"type":"turn.completed"}', ""),
            (0, "not json", "done"),
        ):
            with self.subTest(code=code, stream=stream, final=final):
                self.assertFalse(Run.codex_result(code, stream, "", final)[0])

    def test_final_message_falls_back_to_agent_event(self):
        stream = '\n'.join((
            '{"type":"item.completed","item":{"type":"agent_message","text":"from event"}}',
            '{"type":"turn.completed"}',
        ))
        ok, report = Run.codex_result(0, stream, "", "")
        self.assertTrue(ok)
        self.assertIn("from event", report)

    @unittest.skipUnless(os.name == "nt", "Windows process-tree check")
    def test_kill_tree_stops_child_process(self):
        child = "import time; time.sleep(60)"
        parent = ("import subprocess,sys,time; "
                  "p=subprocess.Popen([sys.executable,'-c'," + repr(child) + "]); "
                  "print(p.pid,flush=True); time.sleep(60)")
        proc = subprocess.Popen([sys.executable, "-c", parent], stdout=subprocess.PIPE,
                                text=True, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
        child_pid = int(proc.stdout.readline().strip())
        try:
            Run.kill_tree(proc)
            proc.wait(timeout=10)
            for _ in range(20):
                listed = subprocess.run(["tasklist", "/FI", "PID eq %d" % child_pid],
                                        capture_output=True, text=True).stdout
                if str(child_pid) not in listed:
                    break
                time.sleep(0.1)
            self.assertNotIn(str(child_pid), listed)
        finally:
            if proc.poll() is None:
                Run.kill_tree(proc)
            proc.stdout.close()


class TemporaryGitFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="factory-executor-test-",
                                                 dir=Path(__file__).resolve().parents[2])
        self.root = Path(self.temp.name)
        self.game = self.root / "games" / "fixture"
        self.game.mkdir(parents=True)
        self._git("init", "-q")
        self._git("config", "user.name", "Factory Test")
        self._git("config", "user.email", "factory-test@example.invalid")
        (self.game / "seed.txt").write_text("seed\n", encoding="utf-8")
        self._git("add", "-A")
        self._git("commit", "-qm", "fixture")
        self.args = SimpleNamespace(game_dir=str(self.game), push=False, agent_cmd=None,
                                    attempts=2, task_minutes=1)
        self.run = Run(self.args)

    def tearDown(self):
        self.temp.cleanup()

    def _git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True,
                              text=True, check=True).stdout.strip()

    def test_untracked_import_blocks_preflight_without_deleting_it(self):
        imported = self.root / "claude-artifacts" / "reference.txt"
        imported.parent.mkdir()
        imported.write_text("keep me", encoding="utf-8")
        with self.assertRaises(SystemExit):
            self.run.preflight()
        self.assertEqual(imported.read_text(encoding="utf-8"), "keep me")

    def test_path_guard_rejects_cross_scope_change(self):
        self.run.upstream_before = self.run.upstream()
        self.run.env_before = self.run.env_stat()
        base = self._git("rev-parse", "HEAD")
        config = self.game / "config" / "pets.json"
        config.parent.mkdir()
        config.write_text("{}", encoding="utf-8")
        self.assertTrue(any("config/pets.json" in issue for issue in
                            self.run.guard(base, "built")))

    def test_codex_command_receives_role_and_saves_trace(self):
        role = self.root / ".claude" / "agents" / "coder.md"
        role.parent.mkdir(parents=True)
        role.write_text("---\nname: coder\n---\n\nFixture role instruction.\n", encoding="utf-8")

        class FakeProcess:
            returncode = 0

            def __init__(self, argv, **_kwargs):
                self.argv = argv

            def communicate(self, prompt, timeout):
                FakeProcess.last_prompt = prompt
                Path(self.argv[self.argv.index("--output-last-message") + 1]).write_text(
                    "fixture final", encoding="utf-8")
                return '{"type":"turn.completed"}\n', ""

        with patch("run_factory.shutil.which", return_value="codex.exe"), patch(
            "run_factory.subprocess.Popen", side_effect=FakeProcess
        ) as started:
            ok, report = self.run.run_agent("coder", "One fixture task.", 1, "fixture", 1)
        self.assertTrue(ok)
        self.assertIn("fixture final", report)
        argv = started.call_args.args[0]
        self.assertEqual(argv[:2], ["codex.exe", "exec"])
        self.assertIn("--json", argv)
        self.assertIn("--sandbox", argv)
        self.assertIn("Fixture role instruction", FakeProcess.last_prompt)
        self.assertIn("One fixture task", FakeProcess.last_prompt)
        self.assertTrue((self.game / "reports" / "agents" / "fixture-attempt1.jsonl").is_file())

    def test_commit_stays_local_by_default(self):
        (self.game / "new.txt").write_text("local", encoding="utf-8")
        before = self._git("rev-parse", "HEAD")
        self.run.commit("local fixture")
        self.assertNotEqual(before, self._git("rev-parse", "HEAD"))
        self.assertEqual(self._git("status", "--porcelain"), "")

    def test_failed_agent_run_retries_even_if_checks_pass(self):
        tasks = self.game / "tasks"
        tasks.mkdir()
        brief = tasks / "001.md"
        brief.write_text("## Done when\n- [x] fixture check\n", encoding="utf-8")
        (tasks / "index.json").write_text(json.dumps({"tasks": [
            {"id": "001", "status": "pending"}]}), encoding="utf-8")
        task = {"id": "001", "title": "fixture", "path": brief}
        base = self._git("rev-parse", "HEAD")
        with (patch.object(self.run, "run_agent", side_effect=[(False, "failed"), (True, "done")]) as agent,
              patch.object(self.run, "guard", return_value=[]),
              patch.object(self.run, "verify_task", return_value=[]),
              patch.object(self.run, "task_checks", return_value=[]),
              patch.object(self.run, "commit", return_value="local-commit")):
            self.run.build_task(task)
        self.assertEqual(agent.call_count, 2)
        self.assertEqual(self.run.done[0]["attempts"], 2)
        self.assertEqual(base, self._git("rev-parse", "HEAD"))


if __name__ == "__main__":
    unittest.main()

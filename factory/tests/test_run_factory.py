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
        policy_path = self.root / "factory" / "executor.json"
        policy_path.parent.mkdir()
        policy = json.loads((Path(__file__).resolve().parents[1] / "executor.json").read_text())
        policy.update(paused=False, authorized_calls=10, authorized_tokens=100000)
        policy["quota"].update(remaining_percent=7, measured_at=time.time(), source="mock")
        policy_path.write_text(json.dumps(policy), encoding="utf-8")
        self._git("add", "-A")
        self._git("commit", "-qm", "fixture policy")

    def update_policy(self, **changes):
        path = self.root / "factory/executor.json"
        policy = json.loads(path.read_text())
        policy.update(changes)
        path.write_text(json.dumps(policy), encoding="utf-8")

    def tearDown(self):
        # Windows can briefly retain a Git process/scanner handle on the root.
        # Retry sharing violations only; never suppress an access-policy error.
        for attempt in range(5):
            try:
                self.temp.cleanup()
                return
            except PermissionError as exc:
                if getattr(exc, "winerror", None) != 32 or attempt == 4:
                    raise
                time.sleep(0.1)

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
                return '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}\n', ""

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
        self.assertEqual(argv[argv.index("--model") + 1], "gpt-6-luna")
        self.assertIn('model_reasoning_effort="low"', argv)
        self.assertIn("features.multi_agent=false", argv)
        self.assertIn("features.goals=false", argv)
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
              patch.object(self.run, "commit", return_value="local-commit"),
              patch.object(self.run.ledger, "task_done")):
            self.run.build_task(task)
        self.assertEqual(agent.call_count, 2)
        self.assertEqual(self.run.done[0]["attempts"], 2)
        self.assertEqual(base, self._git("rev-parse", "HEAD"))

    def test_timeout_records_usage_and_kills_mock_tree(self):
        role = self.root / ".claude/agents/coder.md"
        role.parent.mkdir(parents=True)
        role.write_text("fixture", encoding="utf-8")
        proc = unittest.mock.Mock()
        proc.communicate.side_effect = [subprocess.TimeoutExpired("mock", 1), ("", "partial")]
        with patch("run_factory.shutil.which", return_value="mock-codex"), patch(
                "run_factory.subprocess.Popen", return_value=proc), patch.object(self.run, "kill_tree") as kill:
            ok, report = self.run.run_agent("coder", "fixture", 0.001, "timeout", 1)
        self.assertFalse(ok)
        kill.assert_called_once_with(proc)
        self.assertIn("limit", report)
        rows = self.run.ledger.read()
        self.assertEqual(rows[-1]["status"], "timeout")
        self.assertIsNone(rows[-1]["usage"]["total_tokens"])
        self.assertGreaterEqual(rows[-1]["duration_seconds"], 0)
        self.assertLessEqual(proc.communicate.call_args_list[0].kwargs["timeout"], 0.06)
        with patch("run_factory.subprocess.Popen") as start:
            from run_factory import Stop
            with self.assertRaisesRegex(Stop, "unknown usage"):
                self.run.run_agent("coder", "fixture", 1, "next", 1)
            start.assert_not_called()

    def test_pause_and_alternate_executor_never_launch(self):
        from run_factory import Stop
        self.update_policy(paused=True)
        with patch("run_factory.subprocess.Popen") as start:
            with self.assertRaisesRegex(Stop, "paused"):
                self.run.run_agent("coder", "fixture", 1, "paused", 1)
            self.update_policy(paused=False)
            self.run.args.agent_cmd = "any-other-executor"
            with self.assertRaisesRegex(Stop, "alternate executor"):
                self.run.run_agent("coder", "fixture", 1, "alternate", 1)
            start.assert_not_called()

    def test_execute_paused_preserves_files(self):
        self.update_policy(paused=True)
        original = (self.game / "seed.txt").read_bytes()
        with patch.object(self.run, "go") as go, patch.object(self.run, "finish") as finish, patch(
                "run_factory.exclusive") as lock:
            self.assertEqual(self.run.execute(), 1)
            go.assert_not_called()
            finish.assert_not_called()
            lock.assert_not_called()
        self.assertEqual((self.game / "seed.txt").read_bytes(), original)

    def test_context_and_attempt_limit_prevent_launch(self):
        from run_factory import Stop
        role = self.root / ".claude/agents/coder.md"
        role.parent.mkdir(parents=True)
        role.write_text("fixture", encoding="utf-8")
        with patch("run_factory.shutil.which", return_value="mock"), patch("run_factory.subprocess.Popen") as start:
            with self.assertRaisesRegex(Stop, "context allowance"):
                self.run.run_agent("coder", "x" * 20001, 1, "large", 1)
            with self.assertRaisesRegex(Stop, "two total"):
                self.run.run_agent("coder", "fixture", 1, "third", 3)
            start.assert_not_called()

    def test_deterministic_stage_does_not_call_ai(self):
        with patch.object(self.run, "run_check", return_value=(True, "ok")) as script, patch.object(
                self.run, "run_gate", return_value=(True, "ok")), patch.object(
                self.run, "state"), patch.object(self.run, "commit"), patch.object(self.run, "run_agent") as ai:
            for stage in ("spec_parsed", "economy_tuned"):
                self.run.stage_with_agent(stage)
        self.assertEqual(script.call_count, 2)
        ai.assert_not_called()

    def test_invalid_runtime_model_never_uses_fallback(self):
        from run_factory import Stop
        role = self.root / ".claude/agents/coder.md"
        role.parent.mkdir(parents=True)
        role.write_text("fixture", encoding="utf-8")
        proc = unittest.mock.Mock(returncode=1)
        proc.communicate.return_value = ('{"type":"error","message":"invalid model"}', "")
        with patch("run_factory.shutil.which", return_value="mock"), patch(
                "run_factory.subprocess.Popen", return_value=proc) as start:
            ok, report = self.run.run_agent("coder", "fixture", 1, "bad-model", 1)
            self.assertFalse(ok)
            self.assertIn("invalid model", report)
            with self.assertRaisesRegex(Stop, "unknown usage"):
                self.run.run_agent("coder", "fixture", 1, "bad-model", 2)
            self.assertEqual(start.call_count, 1)

    def test_script_verification_ticks_command_check(self):
        brief = self.game / "brief.md"
        brief.write_text("## Done when\n- [ ] `python fixture.py` passes\n", encoding="utf-8")
        task = {"id": "fixture", "path": brief}
        with patch.object(self.run, "changed_paths", return_value=[]), patch.object(
                self.run, "task_checks", return_value=[(["python", "fixture.py"], "zero")]), patch.object(
                self.run, "run_check", return_value=(True, "ok")) as check:
            self.assertEqual(self.run.verify_task(task, "base"), [])
        check.assert_called_once()
        self.assertIn("- [x]", brief.read_text())

    def mock_coder(self):
        role = self.root / ".claude/agents/coder.md"
        role.parent.mkdir(parents=True, exist_ok=True)
        role.write_text("fixture", encoding="utf-8")
        proc = unittest.mock.Mock(returncode=0)
        proc.communicate.return_value = ('\n'.join((
            '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}',
            '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":20}}',
        )), "")
        return proc

    def test_policy_pause_is_reloaded_after_previous_read(self):
        from run_factory import Stop
        self.assertFalse(self.run.policy()["paused"])
        self.update_policy(paused=True)
        with patch("run_factory.subprocess.Popen") as start:
            with self.assertRaisesRegex(Stop, "paused"):
                self.run.run_agent("coder", "fixture", 1, "task", 1)
            start.assert_not_called()

    def test_lower_budget_is_enforced_before_second_call(self):
        from run_factory import Stop
        proc = self.mock_coder()
        with patch("run_factory.shutil.which", return_value="mock"), patch(
                "run_factory.subprocess.Popen", return_value=proc) as start:
            self.assertTrue(self.run.run_agent("coder", "fixture", 1, "task", 1)[0])
            self.update_policy(authorized_calls=1)
            with self.assertRaisesRegex(Stop, "budget insufficient"):
                self.run.run_agent("coder", "fixture", 1, "task", 2)
            self.assertEqual(start.call_count, 1)

    def test_policy_change_during_preparation_cannot_launch(self):
        from run_factory import Stop

        def role(_agent):
            self.update_policy(paused=True)
            return "fixture"

        with patch("run_factory.shutil.which", return_value="mock"), patch.object(
                self.run, "role_instructions", side_effect=role), patch("run_factory.subprocess.Popen") as start:
            with self.assertRaisesRegex(Stop, "policy changed"):
                self.run.run_agent("coder", "fixture", 1, "task", 1)
            start.assert_not_called()
        self.assertEqual(self.run.ledger.read(), [])

    def test_restart_uses_attempt_two_in_prompt_report_and_ledger(self):
        proc = self.mock_coder()
        tasks = self.game / "tasks"
        tasks.mkdir()
        brief = tasks / "001.md"
        brief.write_text("## Done when\n- [x] fixture\n", encoding="utf-8")
        (tasks / "index.json").write_text(json.dumps({"tasks": [{"id": "001", "status": "pending"}]}))
        task = {"id": "001", "title": "fixture", "path": brief}
        real_popen = subprocess.Popen

        def dispatch(argv, **kwargs):
            return proc if argv[0] == "mock" else real_popen(argv, **kwargs)

        with patch("run_factory.shutil.which", return_value="mock"), patch(
                "run_factory.subprocess.Popen", side_effect=dispatch) as start:
            self.assertTrue(self.run.run_agent("coder", "fixture", 1, "task-001", 1)[0])
            first_trace = (self.game / "reports/agents/task-001-attempt1.jsonl").read_bytes()
            resumed = Run(self.args)
            with patch.object(resumed, "guard", return_value=[]), patch.object(
                    resumed, "verify_task", return_value=[]), patch.object(
                    resumed, "task_checks", return_value=[]), patch.object(resumed, "commit", return_value="mock"):
                resumed.build_task(task)
            self.assertEqual(sum(c.args[0][0] == "mock" for c in start.call_args_list), 2)
        rows = resumed.ledger.read()
        self.assertEqual([r["attempt"] for r in rows if r["event"] == "started"], [1, 2])
        self.assertEqual(resumed.done[0]["attempts"], 2)
        self.assertIn("This is attempt 2 of 2", proc.communicate.call_args.args[0])
        self.assertTrue((self.game / "reports/agents/task-001-attempt2.md").exists())
        self.assertEqual((self.game / "reports/agents/task-001-attempt1.jsonl").read_bytes(), first_trace)

    def test_finish_without_measured_call_is_refused_before_checks(self):
        from run_factory import Stop
        self.run.locked = True
        with patch.object(self.run, "verify_task") as check:
            with self.assertRaisesRegex(Stop, "successful measured invocation"):
                self.run.finish("001")
            check.assert_not_called()

    def test_failed_exit_with_partial_completed_usage_blocks_next_call(self):
        from run_factory import Stop
        proc = self.mock_coder()
        proc.returncode = 1
        with patch("run_factory.shutil.which", return_value="mock"), patch(
                "run_factory.subprocess.Popen", return_value=proc) as start:
            self.assertFalse(self.run.run_agent("coder", "fixture", 1, "task", 1)[0])
            with self.assertRaisesRegex(Stop, "unknown usage"):
                self.run.run_agent("coder", "fixture", 1, "task", 2)
            self.assertEqual(start.call_count, 1)


if __name__ == "__main__":
    unittest.main()

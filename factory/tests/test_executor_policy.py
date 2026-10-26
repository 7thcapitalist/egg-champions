"""Deterministic policy/ledger tests. No CLI, network or production writes."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from executor_policy import Ledger, PolicyError, exclusive, load_policy, usage_from_jsonl


def stream(model=None, **usage):
    event = {"type": "turn.completed", "usage": dict(
        input_tokens=100, cached_input_tokens=80, output_tokens=20, **{})}
    event["usage"].update(usage)
    if model:
        event["model"] = model
    return json.dumps(event)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="factory-policy-", dir=Path(__file__).resolve().parents[2])
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.policy = json.loads((Path(__file__).resolve().parents[1] / "executor.json").read_text())
        self.policy.update(paused=False, authorized_calls=4, authorized_tokens=1000)
        self.policy["quota"].update(remaining_percent=7, measured_at=1000, source="mock")
        self.ledger = Ledger(self.path)

    def start(self, task="task"):
        return self.ledger.start(self.policy, task, "coder", clock=lambda: 1000)

    def admit(self, task="task"):
        return self.ledger.admit(self.policy, task, clock=lambda: 1000)

    def test_two_attempts_survive_restart_and_unknown_blocks(self):
        for expected in (1, 2):
            start = self.start()
            self.assertEqual(start["attempt"], expected)
            self.ledger.finish(start, stream(), 1.25, "finished", False)
            self.ledger = Ledger(self.path)
        with self.assertRaisesRegex(PolicyError, "exhausted"):
            self.start()
        self.assertEqual(self.admit("other"), 1)

    def test_duplicate_task_and_atomic_lock(self):
        with exclusive(self.path):
            with self.assertRaisesRegex(PolicyError, "duplicate"):
                with exclusive(self.path):
                    self.fail("second lock acquired")
        self.assertFalse((self.path / "executor.lock").exists())
        start = self.start()
        self.ledger.finish(start, stream(), 1, "finished", True)
        self.ledger.task_done("task")
        with self.assertRaisesRegex(PolicyError, "duplicate"):
            self.admit()

    def test_crash_or_absent_usage_blocks_next_task(self):
        start = self.start()
        with self.assertRaisesRegex(PolicyError, "unfinished"):
            self.admit("next")
        self.ledger.finish(start, '{"type":"turn.completed"}', 1, "timeout", False)
        with self.assertRaisesRegex(PolicyError, "unknown usage"):
            self.admit("next")

    def test_budget_and_measurement_fail_closed(self):
        cases = [({"authorized_calls": 0}, {}, "budget"),
                 ({"authorized_tokens": 0}, {}, "budget"),
                 ({}, {"remaining_percent": None}, "unknown"),
                 ({}, {"measured_at": None}, "unknown"),
                 ({}, {"measured_at": 699}, "stale"),
                 ({}, {"measured_at": 1001}, "stale"),
                 ({}, {"source": ""}, "unknown"),
                 ({}, {"remaining_percent": 5}, "floor"),
                 ({"paused": True}, {}, "paused")]
        for top, quota, message in cases:
            with self.subTest(top=top, quota=quota):
                policy = copy.deepcopy(self.policy)
                policy.update(top)
                policy["quota"].update(quota)
                with self.assertRaisesRegex(PolicyError, message):
                    self.ledger.admit(policy, "task", clock=lambda: 1000)

    def test_budget_consumed_globally_and_cache_not_added(self):
        self.policy["authorized_tokens"] = 120
        start = self.start()
        self.ledger.finish(start, stream(), 2, "finished", True)
        usage = self.ledger.read()[-1]["usage"]
        self.assertEqual(usage["total_tokens"], 120)
        self.assertEqual(usage["cached_input_tokens"], 80)
        self.assertIsNone(usage["effective_models"])
        self.assertIsNone(usage["provider_call_count"])
        with self.assertRaisesRegex(PolicyError, "budget"):
            self.admit("another-game:task")

    def test_call_budget_consumed_even_on_failure(self):
        self.policy["authorized_calls"] = 1
        start = self.start()
        self.ledger.finish(start, stream(), 2, "finished", False)
        with self.assertRaisesRegex(PolicyError, "budget"):
            self.admit("other")

    def test_effective_model_mismatch_blocks_without_fallback(self):
        start = self.start()
        row = self.ledger.finish(start, stream(model="unexpected-expensive"), 2, "finished", True)
        self.assertFalse(row["ok"])
        self.assertTrue(row["model_mismatch"])
        with self.assertRaisesRegex(PolicyError, "model mismatch"):
            self.admit("other")

    def test_invalid_model_effort_and_attempts(self):
        for field, value in (("model", "typo"), ("effort", "ultra"), ("attempts", 3),
                             ("authorized_calls", None), ("paused", "false")):
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                policy[field] = value
                path = self.path / "fixture.json"
                path.write_text(json.dumps(policy))
                with self.assertRaises(PolicyError):
                    load_policy(path)

    def test_corrupt_ledger_blocks(self):
        self.ledger.path.write_text('{"event":')
        with self.assertRaisesRegex(PolicyError, "corrupt"):
            self.admit()

    def test_metrics_multiple_turns_and_invalid_metrics(self):
        self.assertEqual(usage_from_jsonl(stream() + "\n" + stream())["total_tokens"], 240)
        event = json.loads(stream())
        event["turn_id"] = "same"
        text = json.dumps(event)
        self.assertEqual(usage_from_jsonl(text + "\n" + text)["total_tokens"], 120)
        for text in (stream(cached_input_tokens=101), stream(output_tokens=-1),
                     stream(input_tokens=True), stream() + '\n{"type":"turn.completed"}',
                     stream() + "\ninvalid"):
            self.assertIsNone(usage_from_jsonl(text)["total_tokens"])

    def test_persistent_task_deadline(self):
        self.start()
        self.assertEqual(self.ledger.remaining_seconds("task", 600, clock=lambda: 1500), 100)
        self.assertLess(self.ledger.remaining_seconds("task", 600, clock=lambda: 1700), 0)

    def test_partial_later_turn_or_error_keeps_usage_unknown(self):
        for suffix in ('{"type":"turn.started"}', '{"type":"turn.failed"}',
                       '{"type":"error","message":"connection lost"}'):
            with self.subTest(suffix=suffix):
                usage = usage_from_jsonl(stream() + "\n" + suffix)
                self.assertIsNone(usage["total_tokens"])
                self.assertEqual(len(usage["turns"]), 1)

    def test_timeout_after_completed_turn_still_blocks_budget(self):
        start = self.start()
        row = self.ledger.finish(start, stream(), 1, "timeout", False)
        self.assertIsNone(row["usage"]["total_tokens"])
        self.assertEqual(len(row["usage"]["turns"]), 1)
        with self.assertRaisesRegex(PolicyError, "unknown usage"):
            self.admit("other")

    def test_deleted_or_truncated_ledger_cannot_reset_budget(self):
        start = self.start()
        self.ledger.finish(start, stream(), 1, "finished", True)
        original = self.ledger.path.read_bytes()
        for content in (b"", original.splitlines(keepends=True)[0]):
            self.ledger.path.write_bytes(content)
            with self.assertRaisesRegex(PolicyError, "corrupt"):
                self.admit("other")
        self.ledger.path.unlink()
        with self.assertRaisesRegex(PolicyError, "corrupt"):
            self.admit("other")

    def test_append_interrupted_before_head_update_blocks(self):
        from unittest.mock import patch
        with patch("executor_policy.os.replace", side_effect=OSError("mock crash")):
            with self.assertRaises(PolicyError):
                self.start()
        with self.assertRaisesRegex(PolicyError, "corrupt"):
            self.admit("other")

    def test_ledger_schema_mismatch_and_fake_success_are_rejected(self):
        start = self.start()
        row = self.ledger.finish(start, stream(), 1, "finished", False)
        for changes in ({"task": "other"}, {"attempt": True}, {"duration_seconds": -1},
                        {"model_mismatch": True}, {"status": "timeout"}):
            with self.subTest(changes=changes):
                altered = dict(row, **changes)
                with self.assertRaises((ValueError, TypeError)):
                    self.ledger.validate_rows([start, altered])
        with self.assertRaisesRegex(PolicyError, "completion requires"):
            self.ledger.task_done("task")
        second = dict(start, call_id="different", attempt=1)
        with self.assertRaises(PolicyError):
            self.ledger.append(second)

    def test_conflicting_duplicate_turn_cannot_hide_usage(self):
        event = json.loads(stream())
        event["turn_id"] = "same"
        changed = copy.deepcopy(event)
        changed["usage"]["output_tokens"] = 900
        usage = usage_from_jsonl(json.dumps(event) + "\n" + json.dumps(changed))
        self.assertIsNone(usage["total_tokens"])

    def test_shorter_cli_deadline_survives_restart_and_clock_rollback(self):
        start = self.ledger.start(self.policy, "short", "coder", clock=lambda: 1000, task_seconds=60)
        self.ledger.finish(start, stream(), 1, "finished", False)
        other = Ledger(self.path)
        self.assertEqual(other.remaining_seconds("short", 600, clock=lambda: 1030), 30)
        with self.assertRaisesRegex(PolicyError, "deadline exhausted"):
            other.start(self.policy, "short", "coder", clock=lambda: 1061)
        with self.assertRaisesRegex(PolicyError, "clock moved backwards"):
            other.remaining_seconds("short", 600, clock=lambda: 999)


if __name__ == "__main__":
    unittest.main()

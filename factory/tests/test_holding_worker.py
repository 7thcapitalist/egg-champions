"""Bridge checks use isolated fixtures and mock every factory/model dispatch."""
import contextlib
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'factory/tools'))
import holding_worker as worker
from executor_policy import Ledger, PolicyError, exclusive


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.workspaces = self.base / 'workspaces'
        self.repo = self.workspaces / 'owned'
        self.game = self.repo / 'games/fixture'
        self.hq = self.base / 'hq'
        (self.hq / 'studios/roblox').mkdir(parents=True)
        for directory in (self.game / 'tasks', self.repo / 'factory', self.repo / '.git'):
            directory.mkdir(parents=True)
        self.policy = json.loads((ROOT / 'factory/executor.json').read_text())
        self.policy.update(paused=False, authorized_calls=2, authorized_tokens=10000)
        self.policy['quota'].update(remaining_percent=50, measured_at=time.time(), source='fixture')
        self.save_policy()
        (self.game / 'state.json').write_text(json.dumps({'stages': [
            {'id': 'spec_parsed', 'status': 'passed'}, {'id': 'built', 'status': 'pending'}]}))
        (self.game / 'tasks/index.json').write_text(json.dumps([
            {'id': '50', 'file': '50.md', 'status': 'pending', 'depends_on': []}]))
        (self.game / 'tasks/50.md').write_text('synthetic, not a shipping brief')
        self.branch = 'hq/fixture'
        self.dirty = ''
        self.addCleanup(patch.stopall)
        patch.object(worker, 'git', side_effect=self.git).start()
        patch.object(worker, 'CONTROL_REPO', self.repo).start()
        self.guard = patch.object(worker, 'guard', return_value={'quota': {'codex': {
            'used_pct': 50, 'source': 'fixture', 'measured_at': datetime.now(timezone.utc).isoformat()}}}).start()
        self.factory = patch.object(worker, 'execute_factory', return_value=0).start()

    def save_policy(self):
        (self.repo / 'factory/executor.json').write_text(json.dumps(self.policy))
        (self.hq / 'studios/roblox/executor-runtime.json').write_text(json.dumps(self.policy))

    def git(self, game, *args):
        return {('rev-parse', '--show-toplevel'): str(self.repo),
                ('branch', '--show-current'): self.branch,
                ('status', '--porcelain'): self.dirty,
                ('rev-parse', '--git-common-dir'): '.git'}[args]

    def inspect(self, task='50'):
        return worker.inspect(self.game, self.hq, self.workspaces, task)

    def invoke(self, execute=False):
        argv = ['--game', str(self.game), '--hq', str(self.hq),
                '--workspaces', str(self.workspaces), '--task', '50']
        if execute:
            argv.append('--execute')
        with contextlib.redirect_stdout(io.StringIO()):
            return worker.main(argv)

    def test_inspection_has_no_dispatch_or_accounting_writes(self):
        self.assertTrue(self.inspect()['admitted'])
        self.factory.assert_not_called()
        self.assertFalse((self.repo / '.git/factory-executor').exists())
        self.guard.assert_called_once_with(self.hq, 'check', 'roblox', 'codex')

    def test_owner_checkout_branch_and_dirty_state_are_preserved(self):
        with self.assertRaises(PolicyError):
            worker.inspect(self.game, self.hq, self.base / 'other', '50')
        self.branch = 'codex/user-work'
        with self.assertRaises(PolicyError):
            self.inspect()
        self.branch = 'hq/fixture'
        self.dirty = ' M user-file'
        self.assertEqual(self.invoke(True), 3)
        self.factory.assert_not_called()

    def test_paused_unknown_and_insufficient_budget_never_dispatch(self):
        for change in ({'paused': True}, {'authorized_calls': 0}, {'authorized_tokens': 0}):
            old = dict(self.policy)
            self.policy.update(change)
            self.save_policy()
            self.assertEqual(self.invoke(True), 3)
            self.policy = old
        self.guard.side_effect = PolicyError('required measurement unknown/stale')
        self.assertEqual(self.invoke(True), 3)
        self.factory.assert_not_called()

    def test_wrong_task_and_global_lock_never_dispatch(self):
        with self.assertRaises(PolicyError):
            self.inspect('51')
        with exclusive(self.hq / 'runtime/roblox-factory'):
            self.assertEqual(self.invoke(True), 3)
        self.factory.assert_not_called()

    def test_existing_executor_lock_is_never_removed(self):
        controls = self.repo / '.git/factory-executor'
        controls.mkdir()
        lock = controls / 'executor.lock'
        lock.write_text('fixture-existing-lock')
        self.assertEqual(self.invoke(True), 3)
        self.assertEqual(lock.read_text(), 'fixture-existing-lock')
        self.factory.assert_not_called()

    def test_persistent_attempts_and_completed_tasks_use_same_label(self):
        ledger = Ledger(self.repo / '.git/factory-executor')
        label = 'games/fixture:task-50'
        for _ in range(2):
            started = ledger.start(self.policy, label, 'coder')
            ledger.finish(started, json.dumps({'type': 'turn.completed', 'usage': {
                'input_tokens': 100, 'cached_input_tokens': 80, 'output_tokens': 20}}), 1, 'finished', False)
        with self.assertRaisesRegex(PolicyError, 'exhausted'):
            self.inspect()
        self.factory.assert_not_called()

    def test_unknown_holding_budget_blocks_dispatch(self):
        self.guard.side_effect = PolicyError('unknown measurement')
        self.assertEqual(self.invoke(True), 3)
        self.factory.assert_not_called()

    def test_missing_runtime_cannot_fall_back_to_an_authorized_local_policy(self):
        (self.hq / 'studios/roblox/executor-runtime.json').unlink()
        with self.assertRaisesRegex(PolicyError, 'no legacy-policy fallback'):
            self.inspect()
        self.factory.assert_not_called()

    def test_independent_clone_cannot_reset_attempts(self):
        def cloned(game, *args):
            if game == self.game and args == ('rev-parse', '--git-common-dir'):
                return 'independent.git'
            return self.git(game, *args)
        with patch.object(worker, 'git', side_effect=cloned):
            self.assertEqual(self.invoke(True), 3)
        self.factory.assert_not_called()

    def test_execution_records_both_sides_and_delegates_only_once(self):
        self.assertEqual(self.invoke(True), 0)
        self.factory.assert_called_once_with(self.game, self.hq)
        self.assertEqual([c.args[1:4] for c in self.guard.call_args_list], [
            ('check', 'roblox', 'codex'), ('record', 'roblox', 'start'), ('record', 'roblox', 'end')])
        self.assertEqual(self.guard.call_args_list[1].args[-1], self.guard.call_args_list[2].args[-1])

    def test_failed_factory_still_records_final_measurement(self):
        self.factory.side_effect = OSError('mock failure')
        self.assertEqual(self.invoke(True), 3)
        self.assertEqual(self.guard.call_args_list[-1].args[1:4], ('record', 'roblox', 'end'))


class GuardContractTests(unittest.TestCase):
    def test_legacy_or_unknown_success_exit_cannot_admit_worker(self):
        for body in ({'verdict': 'OK'}, {'verdict': 'UNKNOWN', 'provider_scope': ['codex']}):
            result = SimpleNamespace(returncode=0, stdout=json.dumps(body))
            with patch.object(worker.subprocess, 'run', return_value=result):
                with self.assertRaises(PolicyError):
                    worker.guard(Path('fixture-hq'), 'check', 'roblox', 'codex')
        result = SimpleNamespace(returncode=0, stdout=json.dumps({'verdict': 'OK', 'provider_scope': ['codex']}))
        with patch.object(worker.subprocess, 'run', return_value=result):
            worker.guard(Path('fixture-hq'), 'check', 'roblox', 'codex')


if __name__ == '__main__':
    unittest.main()

"""Integration stays mocked; authorization fixtures never overwrite live controls."""
from datetime import datetime, timedelta, timezone
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'factory/tools'))
import holding_authorization as auth
import holding_worker as worker
import paperclip_agent as agent
from executor_policy import PolicyError


class AuthorizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.policy = self.root / 'policy.json'
        self.original = (ROOT / 'factory/executor.json').read_bytes()
        self.policy.write_bytes(self.original)
        self.sample = {'codex': dict(used_pct=50, paid_credits=False, five_hour_pct=5,
            measured_at=datetime.now(timezone.utc).isoformat(),
            resets_at=(datetime.now(timezone.utc) + timedelta(days=3)).isoformat(), source='mock')}

    def test_explicit_first_window_preserves_unknown_history_and_source(self):
        result = auth.initialize(self.root, self.policy, self.sample, 'human-authorized-fixture')
        self.assertIsNone(result['historical_usage_pct'])
        self.assertEqual(result['authorized_calls'], 2)
        self.assertEqual(self.policy.read_bytes(), self.original)
        baseline = json.loads((self.root / 'ledger/quota.jsonl').read_text())
        runtime = json.loads((self.root / 'studios/roblox/executor-runtime.json').read_text())
        self.assertIsNone(baseline['historical_usage_pct'])
        self.assertEqual(baseline['used_pct'], 50)
        self.assertEqual(runtime['authorized_tokens'], 20000)
        self.assertEqual(runtime['quota']['minimum_percent'], 49)
        with self.assertRaises(PolicyError):
            auth.initialize(self.root, self.policy, self.sample, 'do-not-reset')

    def test_new_window_scales_from_previous_and_archives_old_ledger(self):
        (self.root / 'budget.json').write_text(json.dumps({'studios': {'roblox': {'codex_weekly_share_pct': 35}}}))
        first = auth.initialize(self.root, self.policy, self.sample, 'human-authorized-fixture')
        runtime = self.root / 'studios/roblox/executor-runtime.json'
        with self.assertRaises(PolicyError):  # above budget.json share
            auth.initialize(self.root, runtime, self.sample, 'joao', share_pct=36, new_window=True)
        with patch.object(auth, 'executor_usage', return_value=(3, 25000)):
            result = auth.initialize(self.root, runtime, self.sample, 'joao: 35%', share_pct=35, new_window=True)
        # 20000 tokens for 1% -> 700000 for 35%; 10000 tokens per call -> 70 calls; plus what was already used.
        self.assertEqual(result['authorized_tokens'], 25000 + 700000)
        self.assertEqual(result['authorized_calls'], 3 + 70)
        self.assertEqual(result['archived_ledger'], 'quota-%s.jsonl' % first['window'])
        self.assertTrue((self.root / 'ledger' / result['archived_ledger']).exists())
        baseline = json.loads((self.root / 'ledger/quota.jsonl').read_text())
        policy = json.loads(runtime.read_text())
        self.assertEqual((baseline['share_pct'], policy['holding_window']['share_pct']), (35, 35))
        self.assertEqual(policy['quota']['minimum_percent'], 15)  # 100 - 50 used - 35 share
        self.assertEqual(policy['model'], 'gpt-6-luna')

    def test_unknown_exhausted_or_reserve_budget_cannot_initialize(self):
        for field, value in (('used_pct', 85), ('paid_credits', None), ('five_hour_pct', 100),
                             ('measured_at', '2000-01-01T00:00:00Z')):
            old = self.sample['codex'][field]
            self.sample['codex'][field] = value
            with self.assertRaises(PolicyError):
                auth.initialize(self.root, self.policy, self.sample, 'fixture')
            self.sample['codex'][field] = old
        self.assertFalse((self.root / 'ledger/quota.jsonl').exists())

    def test_runtime_policy_refreshes_measurement_without_rewriting_authorization(self):
        auth.initialize(self.root, self.policy, self.sample, 'human-authorized-fixture')
        path = self.root / 'studios/roblox/executor-runtime.json'
        before = path.read_bytes()
        newer = dict(self.sample['codex'], used_pct=50.25)
        with patch.object(worker, 'guard', return_value={'quota': {'codex': newer}}):
            policy = worker.runtime_policy(self.root, self.root)
        self.assertEqual(policy['quota']['remaining_percent'], 49.75)
        self.assertEqual(policy['authorized_calls'], 2)
        self.assertEqual(path.read_bytes(), before)

    def test_exhausted_guard_never_falls_back_to_legacy_authorization(self):
        auth.initialize(self.root, self.policy, self.sample, 'human-authorized-fixture')
        with patch.object(worker, 'guard', side_effect=PolicyError('window exhausted')):
            with self.assertRaises(PolicyError):
                worker.runtime_policy(self.root, self.root)

    def test_permission_denial_is_reported_without_retry_or_alternate_location(self):
        output = io.StringIO()
        result = SimpleNamespace(stdout=json.dumps(self.sample))
        with patch.object(auth.subprocess, 'run', return_value=result), \
                patch.object(auth, 'initialize', side_effect=PermissionError('access denied')) as install, \
                contextlib.redirect_stdout(output):
            code = auth.main(['--hq', str(self.root), '--policy', str(self.policy), '--authorization', 'fixture'])
        self.assertEqual(code, 3)
        self.assertFalse(json.loads(output.getvalue())['initialized'])
        install.assert_called_once()
        self.assertFalse((self.root / 'ledger/quota.jsonl').exists())


class AgentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.args = SimpleNamespace(role='engineer', game=root, worker_game=root/'worker',
            hq=root/'hq', workspaces=root/'workspaces', company='fixture-company')
        patcher = patch.dict(os.environ, {'PAPERCLIP_AGENT_ID': 'fixture-agent'})
        patcher.start(); self.addCleanup(patcher.stop)
        self.issue = dict(identifier='ROB-5', title='Tarefa 50: fixture', status='todo', assigneeAgentId='fixture-agent')

    def test_director_and_analyst_checks_never_dispatch_ai(self):
        self.args.role = 'director'
        with patch.object(agent.release_readiness, 'check', return_value=['unknown']), \
                patch.object(agent.holding_worker, 'guard', return_value={'verdict':'OK'}), \
                patch.object(agent, 'invoke_worker') as dispatch:
            self.assertEqual(agent.evaluate(self.args)['model_calls_requested'], 0)
            dispatch.assert_not_called()
        self.args.role = 'analyst'
        with patch.object(agent.gate, 'gate_economy_tuned', return_value=0), \
                patch.object(agent, 'invoke_worker') as dispatch:
            self.assertEqual(agent.evaluate(self.args)['model_calls_requested'], 0)
            dispatch.assert_not_called()

    def test_unknown_or_other_assignees_never_dispatch(self):
        with patch.object(agent, 'issues', return_value=[dict(self.issue, assigneeAgentId='other')]), \
                patch.object(agent, 'invoke_worker') as dispatch:
            self.assertEqual(agent.evaluate(self.args)['status'], 'blocked')
            dispatch.assert_not_called()

    def test_running_task_prevents_duplicate(self):
        with patch.object(agent, 'issues', return_value=[self.issue]), \
                patch.object(agent.gate, 'load_tasks', return_value=([{'status':'running'}],None)), \
                patch.object(agent, 'invoke_worker') as dispatch:
            self.assertEqual(agent.evaluate(self.args)['status'], 'blocked')
            dispatch.assert_not_called()

    def test_eligible_job_still_requires_protected_inspection(self):
        tasks=[dict(id='50', status='pending', depends_on=[])]
        with patch.object(agent, 'issues', return_value=[self.issue]), \
                patch.object(agent.gate, 'load_tasks', return_value=(tasks,None)), \
                patch.object(agent.holding_worker, 'inspect', side_effect=PolicyError('no budget')), \
                patch.object(agent, 'invoke_worker') as dispatch:
            with self.assertRaises(PolicyError):
                agent.evaluate(self.args)
            dispatch.assert_not_called()

    def test_only_one_eligible_job_delegates_to_protected_worker(self):
        tasks=[dict(id='50', status='pending', depends_on=[])]
        with patch.object(agent, 'issues', return_value=[self.issue]), \
                patch.object(agent.gate, 'load_tasks', return_value=(tasks,None)), \
                patch.object(agent.holding_worker, 'inspect'), \
                patch.object(agent, 'invoke_worker', return_value={'status':'finished'}) as dispatch:
            self.assertEqual(agent.evaluate(self.args)['task'], '50')
            dispatch.assert_called_once_with(self.args, '50')

    def test_awaiting_windows_dependency_frees_next_code_task(self):
        tasks=[dict(id='50', status='awaiting_windows', depends_on=[]),
               dict(id='51', status='pending', depends_on=['50'])]
        issue = dict(self.issue, identifier='ROB-18', title='Tarefa 51: collection trail')
        with patch.object(agent, 'issues', return_value=[issue]), \
                patch.object(agent.gate, 'load_tasks', return_value=(tasks,None)), \
                patch.object(agent.holding_worker, 'inspect'), \
                patch.object(agent, 'invoke_worker', return_value={'status':'finished'}) as dispatch:
            result = agent.evaluate(self.args)
        self.assertEqual((result['task'], result['issue']), ('51', 'ROB-18'))
        dispatch.assert_called_once_with(self.args, '51')

    def test_issue_for_another_task_never_dispatches(self):
        tasks=[dict(id='51', status='pending', depends_on=[])]
        with patch.object(agent, 'issues', return_value=[self.issue]), \
                patch.object(agent.gate, 'load_tasks', return_value=(tasks,None)), \
                patch.object(agent, 'invoke_worker') as dispatch:
            self.assertEqual(agent.evaluate(self.args)['status'], 'blocked')
            dispatch.assert_not_called()

    def test_model_child_gets_no_bearer_or_paid_api_credentials(self):
        with patch.dict(os.environ, {'PAPERCLIP_API_KEY':'fake', 'OPENAI_API_KEY':'fake',
                                    'ANTHROPIC_API_KEY':'fake', 'ROBLOX_API_KEY':'fake'}):
            clean = agent.model_environment()
        for key in ('PAPERCLIP_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY','ROBLOX_API_KEY'):
            self.assertNotIn(key, clean)

    def test_worker_timeout_kills_the_whole_tree_no_retry(self):
        process = Mock()
        process.communicate.side_effect = [subprocess.TimeoutExpired('mock',3600), ('','')]
        with patch.object(agent.subprocess, 'Popen', return_value=process) as start, \
                patch.object(agent.holding_worker.run_factory.Run, 'kill_tree') as kill:
            self.assertEqual(agent.invoke_worker(self.args,'50')['status'], 'blocked')
            start.assert_called_once(); kill.assert_called_once_with(process)

    def test_protected_rollback_preserves_partial_work(self):
        run = worker.ProtectedRun.__new__(worker.ProtectedRun)
        with self.assertRaises(worker.run_factory.Stop):
            run.revert_to('fixture-base')
        self.assertTrue(run.preserve_partial)


if __name__ == '__main__':
    unittest.main()

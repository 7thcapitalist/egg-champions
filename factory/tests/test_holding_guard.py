"""Install holding scripts only in temporary fixtures. No AI or real accounts."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'factory/holding'
AT = '2026-10-20T12:00:00Z'
RESET = '2026-10-22T12:00:00.000Z'


class HoldingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'ledger').mkdir()
        self.budget = {'reserve_for_joao': {'codex_weekly_max_pct': 85, 'claude_weekly_max_pct': 85},
                       'studios': {'roblox': {'codex_weekly_share_pct': 30, 'claude_weekly_share_pct': 10}}}
        self.quota = {k: {'used_pct': 40, 'measured_at': AT, 'resets_at': RESET,
                         'source': 'fixture', 'paid_credits': False} for k in ('codex', 'claude')}
        self.rows = [dict(at=AT, studio='roblox', runId='fixture', phase=phase,
            codex_pct=pct, claude_pct=pct, codex_resets_at=RESET, claude_resets_at=RESET)
            for phase, pct in (('start', 10), ('end', 11))]

    def run_guard(self, rows=True, provider=None):
        shutil.copyfile(SOURCE / 'guard.mjs', self.root / 'scripts/guard.mjs')
        (self.root / 'scripts/quota.mjs').write_text('const q=' + json.dumps(self.quota) +
            '; export const codexQuota=()=>q.codex; export const claudeQuota=()=>q.claude;')
        (self.root / 'budget.json').write_text(json.dumps(self.budget))
        if rows:
            (self.root / 'ledger/quota.jsonl').write_text('\n'.join(json.dumps(r) for r in self.rows))
        boot = self.root / 'boot.mjs'
        boot.write_text("Date.now=()=>Date.parse('" + AT + "'); await import('./scripts/guard.mjs');")
        args = ['node', str(boot), 'check', 'roblox']
        if provider:
            args.append(provider)
        done = subprocess.run(args, capture_output=True, text=True, timeout=15)
        return done.returncode, json.loads(done.stdout)

    def test_complete_measured_accounting_passes(self):
        code, result = self.run_guard()
        self.assertEqual(code, 0)
        self.assertEqual(result['verdict'], 'OK')
        self.assertEqual(result['usage']['codex']['used_pct_of_plan'], 1)

    def forward_window(self):
        baseline = dict(schema=2, phase='baseline', studio='roblox', provider='codex',
            runId='authorized-fixture', at=AT, measured_at=AT, used_pct=40, resets_at=RESET,
            historical_usage_pct=None, share_pct=1, authorized_calls=2,
            authorized_tokens=20000, authorization='explicit-test-authorization')
        self.rows = [baseline]
        runtime = {'authorized_calls': 2, 'authorized_tokens': 20000, 'holding_window': {
            'id': baseline['runId'], 'authorization': baseline['authorization'], 'share_pct': 1,
            'baseline_sha256': hashlib.sha256(json.dumps(baseline).encode()).hexdigest()}}
        target = self.root / 'studios/roblox/executor-runtime.json'
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps(runtime))

    def test_authorized_forward_window_never_claims_historical_zero(self):
        self.forward_window()
        code, result = self.run_guard(provider='codex')
        self.assertEqual(code, 0)
        self.assertIsNone(result['usage']['codex']['used_pct_of_plan'])
        self.assertEqual(result['usage']['codex']['used_pct_of_window'], 0)
        self.assertEqual(result['usage']['codex']['historical_usage'], 'unknown')
        self.quota['codex']['used_pct'] = 41
        self.assertEqual(self.run_guard(provider='codex')[0], 3)

    def test_baseline_change_reset_unknown_end_and_wrong_provider_block(self):
        self.forward_window()
        self.assertEqual(self.run_guard(provider='claude')[0], 3)
        self.quota['codex']['used_pct'] = 39
        self.assertEqual(self.run_guard(provider='codex')[0], 3)
        self.quota['codex']['used_pct'] = 40
        self.rows.append(dict(phase='start', runId='unfinished', studio='roblox', at=AT))
        self.assertEqual(self.run_guard(provider='codex')[0], 3)
        self.rows.pop()
        self.rows[0]['share_pct'] = 2
        self.assertEqual(self.run_guard(provider='codex')[0], 3)

    def test_unknown_quota_never_success(self):
        self.quota['codex'] = None
        code, result = self.run_guard()
        self.assertEqual(code, 3)
        self.assertNotEqual(result['verdict'], 'OK')

    def test_requested_provider_only_no_runtime_fallback(self):
        self.quota['claude'] = None
        code, result = self.run_guard(provider='codex')
        self.assertEqual(code, 0)
        self.assertEqual(result['provider_scope'], ['codex'])
        self.assertEqual(self.run_guard(provider='claude')[0], 3)

    def test_reported_exhausted_short_window_blocks_even_with_weekly_remaining(self):
        self.quota['codex']['five_hour_pct'] = 100
        code, result = self.run_guard(provider='codex')
        self.assertEqual(code, 3)
        self.assertEqual(result['verdict'], 'STOP')

    def test_unknown_stale_future_or_credit_measurement_blocks(self):
        for field, value in (('measured_at', '2026-10-20T11:54:59Z'),
                             ('measured_at', '2026-10-20T12:01:00Z'),
                             ('paid_credits', None), ('paid_credits', True),
                             ('used_pct', True), ('used_pct', 101)):
            with self.subTest(field=field, value=value):
                old = self.quota['codex'][field]
                self.quota['codex'][field] = value
                self.assertEqual(self.run_guard()[0], 3)
                self.quota['codex'][field] = old

    def test_missing_empty_or_unfinished_ledger_blocks(self):
        self.assertEqual(self.run_guard(rows=False)[0], 3)
        self.rows = []
        self.assertEqual(self.run_guard()[0], 3)
        self.rows = [dict(at=AT, studio='roblox', runId='open', phase='start')]
        self.assertEqual(self.run_guard()[0], 3)

    def test_duplicate_regression_and_reset_crossing_block(self):
        for mode in ('duplicate', 'regression', 'reset'):
            with self.subTest(mode=mode):
                original = json.loads(json.dumps(self.rows))
                if mode == 'duplicate':
                    self.rows.append(self.rows[-1])
                elif mode == 'regression':
                    self.rows[-1]['codex_pct'] = 9
                else:
                    self.rows[-1]['codex_resets_at'] = 'other'
                self.assertEqual(self.run_guard()[0], 3)
                self.rows = original

    def test_share_reserve_missing_cap_and_no_round_down(self):
        self.budget['studios']['roblox']['codex_weekly_share_pct'] = None
        self.assertEqual(self.run_guard()[0], 3)
        self.budget['studios']['roblox']['codex_weekly_share_pct'] = 1
        self.assertEqual(self.run_guard()[0], 3)
        self.budget['studios']['roblox']['codex_weekly_share_pct'] = 30
        self.rows[-1]['codex_pct'] = 10.94
        self.budget['studios']['roblox']['codex_weekly_share_pct'] = 0.92
        self.assertEqual(self.run_guard()[0], 3)
        self.budget['studios']['roblox']['codex_weekly_share_pct'] = 30
        self.quota['codex']['used_pct'] = 85
        self.assertEqual(self.run_guard()[0], 3)

    def test_corrupt_ledger_is_unknown_not_zero(self):
        self.run_guard()
        (self.root / 'ledger/quota.jsonl').write_text('{broken')
        code, result = self.run_guard(rows=False)
        self.assertEqual(code, 3)
        self.assertIsNone(result['usage']['codex']['used_pct_of_plan'])

    def run_quota(self, windows):
        shutil.copyfile(SOURCE / 'quota.mjs', self.root / 'scripts/quota.mjs')
        sessions = self.root / 'codex/sessions'
        sessions.mkdir(parents=True, exist_ok=True)
        event = {'timestamp': AT, 'payload': {'rate_limits': {'limit_id': 'codex',
            'primary': windows[0], 'secondary': windows[1], 'credits': {'has_credits': False}}}}
        (sessions / 'fixture.jsonl').write_text(json.dumps(event))
        boot = self.root / 'quota-boot.mjs'
        boot.write_text("Date.now=()=>Date.parse('" + AT + "'); const q=await import('./scripts/quota.mjs'); console.log(JSON.stringify(q.codexQuota()));")
        env = dict(os.environ, CODEX_HOME=str(self.root / 'codex'), USERPROFILE=str(self.root),
                   HABBLAUD_USAGE_DIR=str(self.root / 'claude-empty'))
        done = subprocess.run(['node', str(boot)], env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_short_window_cannot_substitute_weekly(self):
        short = {'window_minutes': 300, 'used_percent': 1, 'resets_at': 1792670400}
        self.assertIsNone(self.run_quota((short, None)))

    def test_explicit_weekly_window_is_used(self):
        short = {'window_minutes': 300, 'used_percent': 1, 'resets_at': 1792670400}
        week = dict(short, window_minutes=10080, used_percent=44)
        result = self.run_quota((short, week))
        self.assertEqual(result['used_pct'], 44)
        self.assertEqual(result['five_hour_pct'], 1)

    def test_claude_account_ambiguity_and_missing_measurement(self):
        shutil.copyfile(SOURCE / 'quota.mjs', self.root / 'scripts/quota.mjs')
        usage = self.root / 'claude'
        usage.mkdir()
        record = {'seven_day': {'utilization': 20, 'resets_at': 1792670400}, 'fetchedAt': 1792497600}
        (usage / 'a.json').write_text(json.dumps(record))
        boot = self.root / 'claude-boot.mjs'
        boot.write_text("Date.now=()=>Date.parse('" + AT + "'); const q=await import('./scripts/quota.mjs'); console.log(JSON.stringify(q.claudeQuota()));")
        env = dict(os.environ, CODEX_HOME=str(self.root / 'empty'), USERPROFILE=str(self.root),
                   HABBLAUD_USAGE_DIR=str(usage))
        def run():
            result = subprocess.run(['node', str(boot)], env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertEqual(run()['used_pct'], 20)
        (usage / 'b.json').write_text(json.dumps(record))
        self.assertIsNone(run())
        (usage / 'b.json').unlink()
        del record['fetchedAt']
        (usage / 'a.json').write_text(json.dumps(record))
        self.assertIsNone(run())


if __name__ == '__main__':
    unittest.main()

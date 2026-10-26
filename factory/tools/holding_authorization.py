"""Explicit first-window installation, never a guessed historical zero."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

from executor_policy import PolicyError, exclusive, load_policy


def initialize(hq, policy_source, quota, authorization):
    sample = quota.get('codex')
    now = time.time()
    try:
        measured = datetime.fromisoformat(sample['measured_at'].replace('Z', '+00:00')).timestamp()
        reset = datetime.fromisoformat(sample['resets_at'].replace('Z', '+00:00')).timestamp()
        used = sample['used_pct']
        if (type(used) not in (int, float) or not 0 <= used < 84
                or not 0 <= now - measured <= 300 or reset <= now
                or sample['paid_credits'] is not False or not sample.get('source')
                or sample.get('five_hour_pct', 0) is not None and sample.get('five_hour_pct', 0) >= 100):
            raise ValueError('quota not available for the authorized small window')
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        raise PolicyError('fresh subscription measurement required for initialization') from exc
    if not isinstance(authorization, str) or not authorization.strip():
        raise PolicyError('explicit operator authorization required')
    policy = load_policy(policy_source)
    if policy['model'] != 'gpt-6-luna' or policy['effort'] != 'low' or policy['allowed_models'] != ['gpt-6-luna']:
        raise PolicyError('central economic model changed; explicit review required, no fallback')
    policy.update(paused=False, authorized_calls=2, authorized_tokens=20000)
    policy['quota'].update(remaining_percent=100-used, measured_at=measured,
                           source=sample['source'], minimum_percent=max(15, 100-used-1))
    ident = 'roblox-' + uuid.uuid4().hex
    baseline = dict(schema=2, phase='baseline', studio='roblox', provider='codex', runId=ident,
                    at=datetime.now(timezone.utc).isoformat(), measured_at=sample['measured_at'],
                    used_pct=used, resets_at=sample['resets_at'], share_pct=1,
                    historical_usage_pct=None, authorized_calls=2, authorized_tokens=20000,
                    authorization=authorization)
    line = json.dumps(baseline, separators=(',', ':'), ensure_ascii=True)
    policy['holding_window'] = dict(id=ident, authorization=authorization, share_pct=1,
        baseline_sha256=hashlib.sha256(line.encode()).hexdigest())
    ledger = hq / 'ledger/quota.jsonl'
    runtime = hq / 'studios/roblox/executor-runtime.json'
    with exclusive(hq / 'runtime/roblox-factory'):
        if ledger.exists() or runtime.exists():
            raise PolicyError('existing accounting/authorization preserved; no automatic reset')
        ledger.parent.mkdir(parents=True, exist_ok=True)
        runtime.parent.mkdir(parents=True, exist_ok=True)
        # A crash between files blocks instead of pretending initialization succeeded.
        with ledger.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(line + '\n'); stream.flush(); os.fsync(stream.fileno())
        with runtime.open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(policy, stream, indent=2); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
    return {'window': ident, 'authorized_calls': 2, 'authorized_tokens': 20000,
            'authorized_share_pct': 1, 'historical_usage_pct': None}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hq', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--authorization', required=True)
    args = parser.parse_args(argv)
    try:
        result = subprocess.run(['node', str(args.hq / 'scripts/quota.mjs')], capture_output=True,
                                text=True, check=True, timeout=30)
        print(json.dumps(initialize(args.hq, args.policy, json.loads(result.stdout), args.authorization), indent=2))
        return 0
    except (PolicyError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({'initialized': False, 'reason': str(exc)}, indent=2))
        return 3


if __name__ == '__main__':
    sys.exit(main())

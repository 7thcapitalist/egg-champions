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

from executor_policy import Ledger, PolicyError, exclusive, load_policy

CONTROL_REPO = Path(__file__).resolve().parents[2]


def executor_usage():
    """Calls/tokens already in this checkout's executor ledger (the caps there are cumulative)."""
    common = subprocess.run(['git', '-C', str(CONTROL_REPO), 'rev-parse', '--git-common-dir'],
                            capture_output=True, text=True, check=True).stdout.strip()
    ledger = Ledger((CONTROL_REPO / common).resolve() / 'factory-executor')
    rows = ledger.read() if ledger.path.exists() else []
    starts = [r for r in rows if r['event'] == 'started']
    tokens = sum(r['usage']['total_tokens'] for r in rows if r['event'] == 'finished')
    return len(starts), tokens


def window_allowance(previous, share_pct):
    """Calls/tokens for a share of the week, scaled from the previous authorized window
    (tokens per % point and tokens per call), never a fixed guess."""
    prev_share = previous.get('holding_window', {}).get('share_pct')
    prev_tokens, prev_calls = previous.get('authorized_tokens'), previous.get('authorized_calls')
    if (type(prev_share) not in (int, float) or prev_share <= 0
            or type(prev_tokens) is not int or type(prev_calls) is not int or prev_calls <= 0 or prev_tokens <= 0):
        raise PolicyError('previous window has no usable token/call ratio; explicit review required')
    tokens = int(share_pct * prev_tokens / prev_share)
    calls = -(-tokens * prev_calls // prev_tokens)
    return calls, tokens


def initialize(hq, policy_source, quota, authorization, share_pct=1, new_window=False):
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
    budget_path = hq / 'budget.json'
    # Without budget.json only the original 1% first window is allowed.
    cap = (json.loads(budget_path.read_text(encoding='utf-8'))['studios']['roblox']['codex_weekly_share_pct']
           if budget_path.exists() else 1)
    if type(share_pct) not in (int, float) or not 0 < share_pct <= cap:
        raise PolicyError('share_pct must be within budget.json roblox codex share (%s)' % cap)
    if share_pct == 1 and not new_window:
        calls, tokens = 2, 20000  # original first window
    else:
        calls, tokens = window_allowance(policy, share_pct)
    used_calls, used_tokens = executor_usage()
    calls, tokens = min(1000, used_calls + calls), used_tokens + tokens
    policy.update(paused=False, authorized_calls=calls, authorized_tokens=tokens)
    policy['quota'].update(remaining_percent=100-used, measured_at=measured,
                           source=sample['source'], minimum_percent=max(15, 100-used-share_pct))
    ident = 'roblox-' + uuid.uuid4().hex
    baseline = dict(schema=2, phase='baseline', studio='roblox', provider='codex', runId=ident,
                    at=datetime.now(timezone.utc).isoformat(), measured_at=sample['measured_at'],
                    used_pct=used, resets_at=sample['resets_at'], share_pct=share_pct,
                    historical_usage_pct=None, authorized_calls=calls, authorized_tokens=tokens,
                    authorization=authorization)
    line = json.dumps(baseline, separators=(',', ':'), ensure_ascii=True)
    policy['holding_window'] = dict(id=ident, authorization=authorization, share_pct=share_pct,
        baseline_sha256=hashlib.sha256(line.encode()).hexdigest())
    ledger = hq / 'ledger/quota.jsonl'
    runtime = hq / 'studios/roblox/executor-runtime.json'
    with exclusive(hq / 'runtime/roblox-factory'):
        archived = None
        if new_window:
            # New window: the old accounting is kept (renamed, never deleted) and the runtime replaced.
            if not runtime.exists():
                raise PolicyError('--new-window needs the current authorization to replace')
            if ledger.exists():
                old = json.loads(runtime.read_text(encoding='utf-8')).get('holding_window', {}).get('id') or 'unknown'
                archived = ledger.with_name('quota-%s.jsonl' % old)
                if archived.exists():
                    raise PolicyError('archive %s already exists; explicit review required' % archived.name)
                os.replace(ledger, archived)
        elif ledger.exists() or runtime.exists():
            raise PolicyError('existing accounting/authorization preserved; no automatic reset')
        ledger.parent.mkdir(parents=True, exist_ok=True)
        runtime.parent.mkdir(parents=True, exist_ok=True)
        # A crash between files blocks instead of pretending initialization succeeded.
        with ledger.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(line + '\n'); stream.flush(); os.fsync(stream.fileno())
        temp = runtime.with_name(runtime.name + '.tmp')
        with temp.open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(policy, stream, indent=2); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
        os.replace(temp, runtime)
    return {'window': ident, 'authorized_calls': calls, 'authorized_tokens': tokens,
            'authorized_share_pct': share_pct, 'historical_usage_pct': None,
            'archived_ledger': archived and archived.name}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hq', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--authorization', required=True)
    parser.add_argument('--share-pct', type=float, default=1,
                        help='%% of the weekly Codex plan for this window (<= budget.json roblox share)')
    parser.add_argument('--new-window', action='store_true',
                        help='replace the current authorization; the old quota ledger is archived, not deleted')
    args = parser.parse_args(argv)
    share = int(args.share_pct) if args.share_pct == int(args.share_pct) else args.share_pct
    try:
        result = subprocess.run(['node', str(args.hq / 'scripts/quota.mjs')], capture_output=True,
                                text=True, check=True, timeout=30)
        print(json.dumps(initialize(args.hq, args.policy, json.loads(result.stdout), args.authorization,
                                    share, args.new_window), indent=2))
        return 0
    except (PolicyError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({'initialized': False, 'reason': str(exc)}, indent=2))
        return 3


if __name__ == '__main__':
    sys.exit(main())

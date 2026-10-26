"""Paperclip bridge for one built-stage task. Inspection is the default.

Does not alter authorization or select another model/runtime. Execution, when
explicitly requested, delegates to the existing protected factory. Never point
it at the user's active checkout. No Paperclip API calls or automatic dispatch.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from types import SimpleNamespace

from executor_policy import Ledger, PolicyError, exclusive, load_policy
import gate
import run_factory

CONTROL_REPO = Path(__file__).resolve().parents[2]


def git(game, *args):
    result = subprocess.run(['git', *args], cwd=game, capture_output=True,
                            text=True, timeout=15, check=True)
    return result.stdout.strip()


def guard(hq, *args):
    result = subprocess.run(['node', str(hq / 'scripts/guard.mjs'), *args],
                            capture_output=True, text=True, timeout=15)
    if args[0] == 'check':
        try:
            data = json.loads(result.stdout)
        except (ValueError, TypeError):
            raise PolicyError('holding guard returned no valid measurement')
        if (result.returncode != 0 or data.get('verdict') != 'OK'
                or data.get('provider_scope') != ['codex']):
            raise PolicyError('holding budget blocked: ' + str(data.get('reasons', 'unknown')))
    elif result.returncode != 0:
        raise PolicyError('holding measurement could not be recorded; stop for review')
    return data if args[0] == 'check' else None


def runtime_policy(hq, fallback):
    path = hq / 'studios/roblox/executor-runtime.json'
    if not path.exists():
        raise PolicyError('holding authorization unavailable; no legacy-policy fallback')
    policy = load_policy(path)
    report = guard(hq, 'check', 'roblox', 'codex')
    sample = report['quota']['codex']
    policy['quota'].update(remaining_percent=100-sample['used_pct'],
        measured_at=datetime.fromisoformat(sample['measured_at'].replace('Z', '+00:00')).timestamp(),
        source=sample['source'])
    return policy


class ProtectedRun(run_factory.Run):
    """Reuse the executor; prohibit destructive rollback in holding worktrees."""
    def __init__(self, args, hq):
        self.hq = hq
        super().__init__(args)

    def policy(self):
        return runtime_policy(self.hq, CONTROL_REPO)

    def role_instructions(self, agent):
        return super().role_instructions(agent) + (
            '\nHolding restrictions: no Studio interaction, publishing, uploads, purchases, '
            'nested AI/factory launches or credentials. Never run git reset/clean/stash. '
            'Manual/live checks remain pending; never invent evidence or tick them.')

    def revert_to(self, base):
        self.preserve_partial = True
        raise run_factory.Stop('partial work preserved for review; destructive rollback disabled')

    def guard(self, base, stage, brief=None):
        if self.git('rev-parse', 'HEAD').stdout.strip() != base:
            self.preserve_partial = True
            raise run_factory.Stop('unexpected commit preserved for human review; no reset')
        return super().guard(base, stage, brief)


def execute_factory(game, hq):
    if any(os.environ.get(k) for k in ('PAPERCLIP_API_KEY', 'ROBLOX_API_KEY', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY')):
        raise PolicyError('model worker must not receive publishing, Paperclip or paid API credentials')
    args = SimpleNamespace(game_dir=str(game), max_tasks=1, task_minutes=10, attempts=2,
        push=False, agent_cmd=None, finish=None, unblock=None, no_push=True)
    return ProtectedRun(args, hq).execute()


def inspect(game, hq, workspaces, task):
    game, hq, workspaces = game.resolve(), hq.resolve(), workspaces.resolve()
    root = Path(git(game, 'rev-parse', '--show-toplevel')).resolve()
    if root == workspaces or not root.is_relative_to(workspaces):
        raise PolicyError('manager must use its own checkout below the declared workspace root')
    if not game.is_relative_to(root / 'games'):
        raise PolicyError('game must stay inside the isolated checkout games directory')
    if not git(game, 'branch', '--show-current').startswith('hq/'):
        raise PolicyError('manager execution requires its own hq/ branch')
    if git(game, 'status', '--porcelain'):
        raise PolicyError('dirty checkout preserved; do not clean, stash or overwrite')
    stages = json.loads((game / 'state.json').read_text(encoding='utf-8'))['stages']
    next_stage = next((s for s in stages if s.get('status') != 'passed'), None)
    if not next_stage or next_stage.get('id') != 'built' or next_stage.get('status') == 'blocked':
        raise PolicyError('bridge only accepts unblocked built-stage work')
    tasks, error = gate.load_tasks(game)
    if error:
        raise PolicyError(error)
    statuses = {t['id']: t['status'] for t in tasks}
    if any(t['status'] == 'blocked' for t in tasks):
        raise PolicyError('blocked task requires human review, never automatic unblock')
    eligible = next((t for t in tasks if t['status'] == 'pending'
                     and all(statuses.get(d) == 'done' for d in t['depends_on'])), None)
    if not eligible or eligible['id'] != task:
        raise PolicyError('requested task is not the next dependency-ready factory task')
    policy = runtime_policy(hq, root)
    common = (root / git(game, 'rev-parse', '--git-common-dir')).resolve()
    canonical_common = (CONTROL_REPO / git(CONTROL_REPO, 'rev-parse', '--git-common-dir')).resolve()
    if common != canonical_common:
        raise PolicyError('independent clone refused: attempts and authorization require the same Git common ledger')
    controls = common / 'factory-executor'
    if (controls / 'executor.lock').exists():
        raise PolicyError('duplicate execution or stale lock; never remove it automatically')
    Ledger(controls).admit(policy, game.relative_to(root).as_posix() + ':task-' + task)
    return {'admitted': True, 'task': task, 'root': str(root),
            'model': policy['model'], 'effort': policy['effort'],
            'scope': 'one built-stage task; no publication or push'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True, type=Path)
    parser.add_argument('--hq', required=True, type=Path)
    parser.add_argument('--workspaces', required=True, type=Path)
    parser.add_argument('--task', required=True)
    parser.add_argument('--execute', action='store_true', help='explicit opt-in; default is read-only')
    args = parser.parse_args(argv)
    try:
        if not args.execute:
            print(json.dumps(inspect(args.game, args.hq, args.workspaces, args.task), indent=2))
            return 0
        # All bridge runs share one holding lock, including independent clones.
        # Existing executor also takes its repository-wide lock and rechecks policy.
        with exclusive(args.hq / 'runtime/roblox-factory'):
            inspect(args.game, args.hq, args.workspaces, args.task)
            run_id = 'factory-' + uuid.uuid4().hex
            guard(args.hq, 'record', 'roblox', 'start', run_id)
            try:
                return execute_factory(args.game, args.hq)
            finally:
                guard(args.hq, 'record', 'roblox', 'end', run_id)
    except (PolicyError, OSError, ValueError, KeyError, TypeError, AttributeError,
            subprocess.SubprocessError) as exc:
        print(json.dumps({'admitted': False, 'reason': str(exc)}, indent=2))
        return 3


if __name__ == '__main__':
    sys.exit(main())

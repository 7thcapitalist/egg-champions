"""Deterministic Paperclip adapters. Only engineer may enter protected generation."""
import argparse
import contextlib
import io
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import urllib.request

import feature_research
import gate
import holding_worker
import release_readiness

API = 'http://localhost:3100/api'


def issues(company):
    headers = {}
    token = os.environ.get('PAPERCLIP_API_KEY')
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(API + '/companies/' + company + '/issues', headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        data = json.load(response)
    if not isinstance(data, list):
        raise ValueError('issue list unavailable')
    return data


def model_environment():
    # The model does not receive Paperclip bearer tokens or publishing/API keys.
    allowed = ('PATH', 'PATHEXT', 'SystemRoot', 'SYSTEMROOT', 'COMSPEC', 'USERPROFILE',
               'HOME', 'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP',
               'CODEX_HOME', 'LANG', 'PYTHONIOENCODING')
    return {key: os.environ[key] for key in allowed if key in os.environ}


def invoke_worker(args, task):
    command = [sys.executable, '-B', str(Path(__file__).with_name('holding_worker.py')),
        '--game', str(args.worker_game), '--hq', str(args.hq),
        '--workspaces', str(args.workspaces), '--task', task, '--execute']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=model_environment(), cwd=Path(__file__).resolve().parents[2],
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    try:
        out, err = process.communicate(timeout=3600)
    except subprocess.TimeoutExpired:
        holding_worker.run_factory.Run.kill_tree(process)
        process.communicate(timeout=15)
        return {'status': 'blocked', 'reason': 'worker timed out; child tree stopped'}
    except Exception:
        holding_worker.run_factory.Run.kill_tree(process)
        return {'status': 'blocked', 'reason': 'worker output unavailable; inspect shared ledger'}
    return {'status': 'finished' if process.returncode == 0 else 'blocked',
            'exit_code': process.returncode, 'summary': (out or err)[-1500:]}


def evaluate(args):
    game = args.game.resolve()
    result = {'role': args.role, 'model_calls_requested': 0, 'publication': 'disabled'}
    if args.role == 'director':
        result.update(status='checked', release_errors={stage: release_readiness.check(game, stage)
            for stage in ('worlds', 'playtested', 'published_test')})
        result['worker_setup'] = {'directory_exists': args.worker_game.is_dir(),
            'note': 'missing/dirty/worktree/task state blocks generation; no clone fallback'}
        try:
            result['admission'] = holding_worker.guard(args.hq, 'check', 'roblox', 'codex')
        except Exception as exc:
            result['admission'] = {'status': 'blocked', 'reason': str(exc)}
        return result
    if args.role == 'analyst':
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = gate.gate_economy_tuned(game)
        result.update(status='checked', economy_gate_exit=code, summary=output.getvalue()[-1000:])
        return result
    if args.role == 'research':
        research = json.loads((game / 'design/feature-research.json').read_text(encoding='utf-8'))
        result.update(status='checked', errors=feature_research.check(game, research),
                      scope='existing evidence validation', current_trends='unknown; no new research performed')
        return result
    # Generation is admitted only for the queued code pipeline assigned to this agent.
    agent_id = os.environ.get('PAPERCLIP_AGENT_ID')
    if not agent_id:
        result.update(status='blocked', reason='Paperclip agent identity missing')
        return result
    queued = [row for row in issues(args.company) if row.get('assigneeAgentId') == agent_id
              and row.get('status') in ('todo', 'in_progress')]
    if not queued:
        result.update(status='blocked', reason='no queued code task assigned; external test tasks are not AI jobs')
        return result
    tasks, error = gate.load_tasks(game)
    if error:
        raise ValueError(error)
    if any(task['status'] in ('running', 'blocked') for task in tasks):
        result.update(status='blocked', reason='active/blocked source task preserved; no duplicate generation')
        return result
    statuses = {task['id']: task['status'] for task in tasks}
    task = next((task for task in tasks if task['status'] == 'pending'
                 and all(statuses.get(dep) in gate.CODE_DONE for dep in task['depends_on'])), None)
    if task is None:
        result.update(status='blocked', reason='no dependency-ready code task')
        return result
    # The Paperclip issue for exactly this factory task ("Tarefa <id>: ...") must be assigned to this agent.
    assigned = [row for row in queued if re.match(r'Tarefa %s\b' % re.escape(task['id']), row.get('title') or '')]
    if not assigned:
        result.update(status='blocked', task=task['id'],
                      reason='no queued Paperclip issue "Tarefa %s" assigned; external test tasks are not AI jobs' % task['id'])
        return result
    result['issue'] = assigned[0].get('identifier')
    # This is read-only and fails before spawning a model/worker if setup is incomplete.
    holding_worker.inspect(args.worker_game, args.hq, args.workspaces, task['id'])
    result['worker'] = invoke_worker(args, task['id'])
    result.update(status=result['worker']['status'], task=task['id'],
                  model_calls_requested=None)  # actual CLI calls live in the shared executor journal
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--role', required=True, choices=('director','analyst','research','engineer'))
    parser.add_argument('--game', required=True, type=Path)
    parser.add_argument('--worker-game', required=True, type=Path)
    parser.add_argument('--hq', required=True, type=Path)
    parser.add_argument('--workspaces', required=True, type=Path)
    parser.add_argument('--company', required=True)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(evaluate(args), ensure_ascii=False, indent=2))
    except Exception as exc:
        # A blocked job is a completed script check, not a transient transport failure
        # for Paperclip to retry repeatedly. Real model attempts remain in the ledger.
        print(json.dumps({'role': args.role, 'status': 'blocked', 'reason': str(exc),
                          'model_calls_requested': 0, 'publication': 'disabled'}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())

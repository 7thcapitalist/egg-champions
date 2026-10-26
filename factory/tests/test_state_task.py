"""state.py task: awaiting_windows only from running/blocked, never back to pending."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'factory/tools'))
import gate
import state


class TaskStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        (self.game / 'tasks').mkdir()
        self.index = self.game / 'tasks' / 'index.json'
        self.index.write_text(json.dumps({'tasks': [
            {'id': '50', 'file': '50.md', 'depends_on': [], 'status': 'running'},
            {'id': '51', 'file': '51.md', 'depends_on': ['50'], 'status': 'pending'},
            {'id': '52', 'file': '52.md', 'depends_on': [], 'status': 'done'}]}))

    def status(self, task_id):
        return {t['id']: t['status'] for t in json.loads(self.index.read_text())['tasks']}[task_id]

    def test_running_task_becomes_awaiting_windows_and_counts_as_code_done(self):
        self.assertEqual(state.main(['task', str(self.game), '50', 'awaiting_windows']), 0)
        self.assertEqual(self.status('50'), 'awaiting_windows')
        self.assertIn(self.status('50'), gate.CODE_DONE)
        self.assertEqual(state.main(['task', str(self.game), '50', 'awaiting_windows']), 0)

    def test_pending_or_done_tasks_are_refused_and_unknown_status_rejected(self):
        self.assertEqual(state.main(['task', str(self.game), '51', 'awaiting_windows']), 2)
        self.assertEqual(state.main(['task', str(self.game), '52', 'awaiting_windows']), 2)
        self.assertEqual(state.main(['task', str(self.game), '99', 'awaiting_windows']), 2)
        with self.assertRaises(SystemExit):
            state.main(['task', str(self.game), '50', 'pending'])
        self.assertEqual((self.status('51'), self.status('52'), self.status('50')), ('pending', 'done', 'running'))


if __name__ == '__main__':
    unittest.main()

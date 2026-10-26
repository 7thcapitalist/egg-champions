"""A report with good time pacing cannot hide missing or failed progression."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("gate", Path(__file__).parents[1] / "tools/gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class EconomyGateTests(unittest.TestCase):
    def check_report(self, rebirth_rows, worlds=None):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parents[2]) as folder:
            game = Path(folder)
            (game / "config").mkdir()
            (game / "tuning").mkdir()
            (game / "config/worlds.json").write_text(json.dumps(worlds if worlds is not None else [{"index":1},{"index":2},{"index":3}]))
            rows = [(t, "MET") for t in gate.TIME_TARGETS] + rebirth_rows
            text = "## Current numbers against the targets\n\n| Target | Wanted | Median | Verdict |\n| --- | --- | --- | --- |\n"
            text += "\n".join("| %s | target | measured | %s |" % row for row in rows)
            text += "\n\n## Predicted result\n| Rebirths at gym 3 | 5 | 5 | MET |\n"
            (game / "tuning/report.md").write_text(text)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = gate.gate_economy_tuned(game)
            return result, output.getvalue()

    def test_all_targets_pass(self):
        self.assertEqual(self.check_report([("Rebirths at gym %d" % i,"MET") for i in (1,2,3)])[0], 0)

    def test_final_rebirth_miss_fails_even_with_all_time_targets_met(self):
        result, output = self.check_report([("Rebirths at gym 1","MET"),("Rebirths at gym 2","MET"),("Rebirths at gym 3","MISSED, 2 too many")])
        self.assertEqual(result, 1)
        self.assertIn("Rebirths at gym 3 is MISSED", output)

    def test_missing_or_ambiguous_verdict_fails(self):
        self.assertEqual(self.check_report([])[0], 1)
        self.assertEqual(self.check_report([("Rebirths at gym %d" % i,"MET provisionally") for i in (1,2,3)])[0], 1)

    def test_new_world_requires_another_target(self):
        rows = [("Rebirths at gym %d" % i,"MET") for i in (1,2,3)]
        result, output = self.check_report(rows, [{"index":i} for i in (1,2,3,4)])
        self.assertEqual(result, 1)
        self.assertIn("Rebirths at gym 4", output)

    def test_invalid_worlds_cannot_drop_targets(self):
        for worlds in ([], [{"index":True}], [{"index":1},{"index":1}], {}):
            with self.subTest(worlds=worlds):
                self.assertEqual(self.check_report([], worlds)[0], 1)


if __name__ == "__main__":
    unittest.main()

"""Research validation uses temporary fixtures, never executor files or AI."""
import copy
import json
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import feature_research as research
import gate


class ResearchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2])
        self.addCleanup(self.tmp.cleanup)
        self.game = Path(self.tmp.name)
        (self.game / "tasks").mkdir()
        (self.game / "tasks/index.json").write_text(json.dumps({"tasks": [
            {"id": "1", "file": "one.md", "status": "done", "depends_on": []}]}))
        (self.game / "tasks/one.md").write_text("collection-trail")
        self.data = {"version": 1, "sources": [{
            "id": "source", "url": "https://example.com/official", "available": True,
            "kind": "official_update", "checked_at": "2026-10-20",
            "observation": "description", "limitations": "not measured"}],
            "features": [{"id": "collection-trail", "title": "Trail", "decision": "adopt",
                "approved": True, "rationale": "Existing progress", "adaptation": "Original UI",
                "source_ids": ["source"], "changes_economy": False,
                "changes_persistence": False, "task_id": "1", "scope_paths": ["src/ui"],
                "build": ["show sets"], "automated_checks": ["pure tests"],
                "engine_checks": ["mobile screenshot"]}]}

    def check(self):
        return research.check(self.game, self.data, today=date(2026, 10, 20))

    def test_valid_and_read_only(self):
        before = copy.deepcopy(self.data)
        self.assertEqual(self.check(), [])
        self.assertEqual(self.data, before)

    def test_stale_future_and_unavailable(self):
        for value in ("2026-10-05", "2026-10-21"):
            self.data["sources"][0]["checked_at"] = value
            self.assertTrue(self.check())
        self.data["sources"][0]["checked_at"] = "2026-10-20"
        self.data["sources"][0]["available"] = False
        self.assertTrue(self.check())

    def test_missing_evidence_or_task_binding(self):
        self.data["features"][0]["source_ids"] = ["unknown"]
        self.assertTrue(self.check())
        self.data["features"][0]["source_ids"] = ["source"]
        (self.game / "tasks/one.md").write_text("other feature")
        self.assertTrue(self.check())

    def test_approval_and_impact_contract(self):
        feature = self.data["features"][0]
        feature["approved"] = False
        self.assertTrue(self.check())
        feature["approved"] = True
        feature["changes_economy"] = True
        self.assertTrue(self.check())
        feature["design_contract"] = "missing.md"
        self.assertTrue(self.check())
        (self.game / "contract.md").write_text("reviewed contract")
        feature["design_contract"] = "contract.md"
        self.assertEqual(self.check(), [])

    def test_path_escape_and_duplicate(self):
        self.data["features"][0]["scope_paths"] = ["../outside"]
        self.assertTrue(self.check())
        self.data["features"][0]["scope_paths"] = ["src/ui"]
        self.data["features"].append(copy.deepcopy(self.data["features"][0]))
        self.assertTrue(self.check())

    def test_rank_requires_matching_snapshot(self):
        source = self.data["sources"][0]
        source.update(rank=1, evidence="snapshot.txt", evidence_sha256="wrong")
        (self.game / "snapshot.txt").write_text("chart")
        self.assertTrue(self.check())
        source["kind"] = "charts_snapshot"
        source["evidence_sha256"] = research.hashlib.sha256(b"chart").hexdigest()
        self.assertEqual(self.check(), [])
        (self.game / "snapshot.txt").write_text("changed")
        self.assertTrue(self.check())

    def test_plan_no_overwrite_or_registration(self):
        before = {p: p.read_bytes() for p in self.game.rglob("*") if p.is_file()}
        output = self.game / "proposal"
        manifest = research.plan(self.game, self.data, output, today=date(2026, 10, 20))
        self.assertEqual(manifest["status"], "proposal-only")
        self.assertTrue((output / "collection-trail.md").is_file())
        with self.assertRaises(FileExistsError):
            research.plan(self.game, self.data, output, today=date(2026, 10, 20))
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)
        with self.assertRaises(ValueError):
            research.plan(self.game, self.data, self.game.parent, today=date(2026, 10, 20))

    def test_gate_integration_optional_and_fail_closed(self):
        self.assertEqual(gate.gate_planned(self.game), 0)
        (self.game / "design").mkdir()
        (self.game / "design/feature-research.json").write_text('{"version":999}')
        self.assertEqual(gate.gate_planned(self.game), 1)

    def test_invalid_shapes_fail_closed(self):
        for bad in (None, [], {}, {"version": 1, "sources": [], "features": []}):
            self.assertTrue(research.check(self.game, bad))


if __name__ == "__main__":
    unittest.main()

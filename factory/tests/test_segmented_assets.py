"""Segmented asset data must preserve poses and verify every mesh piece."""
import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_models
import verify_assets
import gate


class SegmentedAssets(unittest.TestCase):
    def setUp(self):
        self.piece = {"name": "body", "mesh_id": 123, "texture_id": 456,
                      "size": [2, 3, 4], "cframe": [0, 1, 2, 1, 0, 0, 0, 1, 0, 0, 0, 1]}
        self.entry = {"id": "pet", "kind": "pet", "mesh_asset_id": 123,
                      "texture_asset_id": 456, "height_studs": 5, "parts": [self.piece]}

    def build(self, entry):
        return build_models.build(json.dumps({"entries": [entry]}).encode(), ["pet"], [])

    def test_pose_survives_build(self):
        table, errors = self.build(self.entry)
        self.assertFalse(errors)
        self.assertEqual(table["entries"][0]["parts"], [self.piece])

    def test_invalid_transforms_and_duplicate_names_rejected(self):
        for field, value in [("size", [0, 1, 1]), ("cframe", [0] * 11),
                             ("cframe", [float("nan")] * 12), ("mesh_id", 0)]:
            entry = copy.deepcopy(self.entry)
            entry["parts"][0][field] = value
            self.assertTrue(self.build(entry)[1], field)
        entry = copy.deepcopy(self.entry)
        entry["parts"].append(copy.deepcopy(self.piece))
        self.assertTrue(self.build(entry)[1])

    def test_missing_or_wrong_piece_cannot_pass(self):
        table, _ = self.build(self.entry)
        good = {"id": "pet", "parts": [{"name": "body", "mesh_id": 123,
                "texture_id": 456, "mesh_ok": True, "mesh_size": [2, 3, 4],
                "texture_status": "Success"}]}
        self.assertTrue(verify_assets.checked_results(table, [good])[0]["ok"])
        self.assertTrue(gate.verified_model(good, table["entries"][0]))
        self.assertFalse(verify_assets.checked_results(table, [])[0]["ok"])
        wrong = copy.deepcopy(good)
        wrong["parts"][0]["mesh_id"] = 999
        self.assertFalse(verify_assets.checked_results(table, [wrong])[0]["ok"])
        failed = copy.deepcopy(good)
        failed["parts"][0]["texture_status"] = "Failure"
        self.assertFalse(verify_assets.checked_results(table, [failed])[0]["ok"])
        self.assertFalse(gate.verified_model(failed, table["entries"][0]))
        incomplete = copy.deepcopy(good)
        incomplete["parts"] = []
        self.assertFalse(gate.verified_model(incomplete, table["entries"][0]))
        self.assertFalse(gate.verified_model(wrong, table["entries"][0]))


if __name__ == "__main__":
    unittest.main()

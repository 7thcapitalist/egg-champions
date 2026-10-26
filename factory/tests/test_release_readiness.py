"""Synthetic evidence tests the release validator, never certifies a game."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import beta_checks as beta
import quality_review
import release_readiness as release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.tmp.cleanup)
        self.game = Path(self.tmp.name)
        for directory in ("src", "config", "tuning", "release"):
            (self.game / directory).mkdir()
        for name in ("spec.md", "default.project.json", "tuning/gyms.json"):
            (self.game / name).write_text("synthetic")
        self.worlds = [{"id": "w" + str(i), "index": i} for i in (1, 2, 3)]
        (self.game / "config/worlds.json").write_text(json.dumps(self.worlds))
        (self.game / "config/passes.json").write_text(json.dumps([{"id": "pass"}]))
        (self.game / "roblox.json").write_text(json.dumps({"test": {"place_id": 123}}))
        (self.game / "build.rbxl").write_bytes(b"synthetic build, not Roblox evidence")
        self.digest = hashlib.sha256((self.game / "build.rbxl").read_bytes()).hexdigest()
        self.manifest = {"schema": 1, "source_sha256": release.source_hash(self.game),
                         "build": {"file": "build.rbxl", "sha256": self.digest}}
        (self.game / "release/evidence.txt").write_text("synthetic test observations")
        evidence = {"file": "evidence.txt", "sha256": hashlib.sha256((self.game / "release/evidence.txt").read_bytes()).hexdigest()}
        self.write("visual", {})
        self.write("traversal", {"worlds": [{"id": w["id"], "arrival_reviewed": True, "routes_passed": True} for w in self.worlds]})
        self.write("mobile", {"cases": [dict(id=key, status="passed", evidence=evidence,
            requested=beta.REQUESTED_VIEWPORTS.get(key, [390, 844]), effective=[390, 748],
            device="synthetic", input_verified=True, physical_touch=True, text_readable=True,
            controls_reachable=True, actions={action: "passed" for action in beta.MOBILE_ACTIONS}) for key in beta.MOBILE_CASES]})
        self.write("multiplayer", {"mode": "real-clients", "subjects": ["a", "b"],
            "cases": [dict(id=key, status="passed", evidence=evidence) for key in beta.MULTIPLAYER_CASES]})
        self.write("slow_network", {"environment": "published-client", "physical_device": True,
            "impairment_method": "synthetic fixture", "added_latency_ms": 200, "bandwidth_kbps": 128,
            "hatch": "passed", "battle": "passed", "reconnect": "passed"})
        self.write("natural_progression", {"place_id": 123, "place_version": 1,
            "environment": "published-client", "seeded": False, "owned_passes": [],
            "gyms": [{"id": "w2", "status": "passed", "duration_seconds": 100},
                     {"id": "w3", "status": "passed", "duration_seconds": 200}]})
        profile = {key: {} for key in beta.PROFILE_FIELDS}
        profile.update(version=5, coins=12, pets=[{"uid": "a", "petId": "synthetic"}],
                       team=["a"], rebirths=0, playSeconds=10, tutorialStep=4)
        before = {"subject": "a", "build_sha256": self.digest, "place_id": 123,
            "place_version": 1, "session_id": "one", "capture_kind": "server",
            "captured_at": "2026-10-20T12:00:00Z", "storage_mode": "datastore",
            "release_confirmed": True, "profile": profile}
        event = {key: before[key] for key in ("subject", "build_sha256", "place_id", "place_version", "session_id")}
        event.update(released=True, saved=True, storage_mode="datastore", captured_at="2026-10-20T12:01:00Z")
        path = self.game / "release/release-event.json"
        path.write_text(json.dumps(event))
        before["release_evidence"] = {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        after = copy.deepcopy(before)
        after.update(session_id="two", captured_at="2026-10-20T12:05:00Z")
        self.write("save_before", before)
        self.write("save_after", after)
        self.write("publication", {"place_id": 123, "place_version": 1, "sources_reopened_match": True})
        self.write("passes", {"place_id": 123, "place_version": 1, "passes": [
            {"id": "pass", "purchase_completion": "passed", "ownership_effect": "passed"}]})
        self.persist()

    def write(self, key, data):
        data = copy.deepcopy(data)
        data["build_sha256"] = self.digest
        path = self.game / ("release/" + key + ".json")
        path.write_text(json.dumps(data))
        self.manifest[key] = {"file": path.relative_to(self.game).as_posix(),
                              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        return data

    def load(self, key):
        return json.loads((self.game / self.manifest[key]["file"]).read_text())

    def persist(self):
        (self.game / "release/manifest.json").write_text(json.dumps(self.manifest))

    def check(self, stage):
        # Aesthetic judgment is covered by quality_review's separate suite.
        with patch.object(quality_review, "check", return_value=[]):
            return release.check(self.game, stage)

    def test_bound_complete_synthetic_bundle(self):
        for stage in ("worlds", "playtested", "published_test"):
            self.assertEqual(self.check(stage), [])

    def test_missing_manifest_blocks_all_gates(self):
        (self.game / "release/manifest.json").unlink()
        for stage in ("worlds", "playtested", "published_test"):
            self.assertTrue(self.check(stage))

    def test_tuning_changes_make_evidence_stale(self):
        (self.game / "tuning/gyms.json").write_text("changed leaders")
        self.assertTrue(self.check("worlds"))

    def test_no_visual_approval_from_build_or_fixture(self):
        with patch.object(quality_review, "check", return_value=["composition below 4"]):
            self.assertIn("visual: composition below 4", release.check(self.game, "worlds"))

    def test_unknown_worlds_and_mobile_do_not_pass(self):
        data = self.load("traversal")
        data["worlds"].pop()
        self.write("traversal", data)
        self.persist()
        self.assertTrue(self.check("worlds"))

    def test_unknown_disconnect_blocks_playtest(self):
        data = self.load("multiplayer")
        data["cases"][-2]["status"] = "unknown"
        self.write("multiplayer", data)
        self.persist()
        self.assertEqual(self.check("worlds"), [])
        self.assertTrue(self.check("playtested"))

    def test_unknown_or_nonphysical_slow_network_blocks(self):
        data = self.load("slow_network")
        for key, value in (("physical_device", False), ("added_latency_ms", None),
                           ("added_latency_ms", True), ("bandwidth_kbps", float("inf")),
                           ("reconnect", "unknown"), ("impairment_method", "")):
            changed = dict(data)
            changed[key] = value
            self.write("slow_network", changed)
            self.persist()
            self.assertTrue(any("slow-network" in e for e in self.check("playtested")))

    def test_temporary_profile_and_missing_purchase_block_publication(self):
        data = self.load("save_after")
        data["storage_mode"] = "temporary"
        self.write("save_after", data)
        self.persist()
        self.assertTrue(any("saves:" in e for e in self.check("published_test")))
        data["storage_mode"] = "datastore"
        self.write("save_after", data)
        data = self.load("passes")
        data["passes"][0]["purchase_completion"] = "unknown"
        self.write("passes", data)
        self.persist()
        self.assertTrue(any("purchase" in e for e in self.check("published_test")))

    def test_build_mismatch_path_escape_and_changed_evidence_block(self):
        data = self.load("mobile")
        data["build_sha256"] = "0" * 64
        path = self.game / self.manifest["mobile"]["file"]
        path.write_text(json.dumps(data))
        self.manifest["mobile"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.persist()
        self.assertTrue(any("another build" in e for e in self.check("playtested")))
        path = self.game / self.manifest["mobile"]["file"]
        path.write_text("changed")
        self.assertTrue(self.check("playtested"))
        self.manifest["build"]["file"] = "../outside"
        self.persist()
        self.assertTrue(self.check("worlds"))


if __name__ == "__main__":
    unittest.main()

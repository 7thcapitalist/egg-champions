"""Beta evidence rejects unknowns and simulator-only persistence claims."""
import copy
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import beta_checks as beta
import build_beta


class BetaChecksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[2])
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.before = {"subject": "tester-a", "build_sha256": "a" * 64,
            "place_id": 123, "place_version": 1, "session_id": "server-a",
            "capture_kind": "server", "captured_at": "2026-10-20T12:00:00Z",
            "storage_mode": "datastore", "release_confirmed": True,
            "profile": {"version": 5, "coins": 100, "pets": [
                {"uid": "a", "petId": "leafpup"}, {"uid": "b", "petId": "puddlet", "variant": "shiny"}],
                "team": ["b", "a"], "index": {"leafpup": {"normal": True}}, "badges": {},
                "rebirths": 0, "gymsBeaten": {}, "feesPaid": {}, "gymRetryAt": {},
                "playSeconds": 10, "tutorialStep": 4}}
        self.after = copy.deepcopy(self.before)
        self.after.update(session_id="server-b", captured_at="2026-10-20T12:05:00Z")
        self.after["profile"]["playSeconds"] = 20
        self.before["release_event"] = {key: self.before[key] for key in
            ("subject", "session_id", "place_id", "place_version", "build_sha256")}
        self.before["release_event"].update(released=True, saved=True, storage_mode="datastore",
                                            captured_at="2026-10-20T12:02:00Z")
        (self.root / "evidence.txt").write_text("synthetic test evidence")
        self.evidence = {"file": "evidence.txt", "sha256": hashlib.sha256(
            (self.root / "evidence.txt").read_bytes()).hexdigest()}

    def test_exact_roundtrip_and_monotonic_time(self):
        before = copy.deepcopy(self.before)
        self.assertEqual(beta.saves(self.before, self.after)["status"], "passed")
        self.assertEqual(self.before, before)
        self.after["profile"]["playSeconds"] = 9
        self.assertEqual(beta.saves(self.before, self.after)["fields"]["playSeconds"], "failed")

    def test_offline_coins_require_bound_release_and_exact_server_receipt(self):
        from datetime import datetime
        stamp = lambda text: datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
        at = stamp(self.before["release_event"]["captured_at"])
        snapshot = {"at": at, "rate": 2}
        self.before["release_event"].update(offline_snapshot=snapshot, saved_coins=100)
        self.before["offline_max_seconds"] = self.after["offline_max_seconds"] = 7200
        self.after["offline_reward"] = {"source": snapshot, "at": at+180,
            "seconds": 180, "coins": 360, "jobId": "server-b"}
        self.after["profile"]["coins"] = 460
        self.assertEqual(beta.saves(self.before, self.after)["status"], "passed")
        for key, value in (("coins", 361), ("seconds", 179), ("jobId", "server-c"), ("at", at+181)):
            altered = copy.deepcopy(self.after)
            altered["offline_reward"][key] = value
            self.assertEqual(beta.saves(self.before, altered)["status"], "blocked")
        del self.before["release_event"]["offline_snapshot"]
        self.assertEqual(beta.saves(self.before, self.after)["status"], "blocked")

    def test_inventory_variants_balances_and_order_are_not_normalized(self):
        for change in (lambda p: p["pets"].pop(), lambda p: p["pets"][1].update(variant="golden"),
                       lambda p: p.update(coins=99), lambda p: p["team"].reverse(),
                       lambda p: p["feesPaid"].update(green_meadow=True),
                       lambda p: p["gymRetryAt"].update(green_meadow=123)):
            with self.subTest(change=change):
                after = copy.deepcopy(self.after)
                change(after["profile"])
                self.assertEqual(beta.saves(self.before, after)["status"], "blocked")

    def test_temporary_unknown_version_and_identity_fail_closed(self):
        for key, value in (("storage_mode", "temporary"), ("capture_kind", "client"),
                ("place_id", 0), ("place_version", 2), ("subject", "other"),
                ("session_id", "server-a"), ("captured_at", None), ("build_sha256", None)):
            after = copy.deepcopy(self.after)
            after[key] = value
            self.assertEqual(beta.saves(self.before, after)["status"], "blocked")

    def test_missing_field_and_schema_change_are_unknown(self):
        del self.after["profile"]["coins"]
        result = beta.saves(self.before, self.after)
        self.assertEqual(result["fields"]["coins"], "unknown")
        self.assertEqual(result["status"], "blocked")

    def test_no_release_confirmation_or_unknown_profile_version(self):
        self.before["release_confirmed"] = False
        self.assertEqual(beta.saves(self.before, self.after)["status"], "blocked")
        self.before["release_confirmed"] = True
        self.after["profile"]["version"] = self.before["profile"]["version"] = 6
        self.assertEqual(beta.saves(self.before, self.after)["status"], "blocked")

    def test_release_must_match_subject_session_and_time(self):
        for key, value in (("subject", "other"), ("saved", False), ("released", False),
                           ("storage_mode", "temporary"), ("captured_at", "2026-10-19T00:00:00Z")):
            before = copy.deepcopy(self.before)
            before["release_event"][key] = value
            self.assertEqual(beta.saves(before, self.after)["status"], "blocked")

    def test_cli_binds_release_file_and_rejects_changed_evidence(self):
        release = self.root / "release.json"
        release.write_text(json.dumps(self.before["release_event"]))
        before = copy.deepcopy(self.before)
        before["release_evidence"] = {"file": "release.json", "sha256": hashlib.sha256(release.read_bytes()).hexdigest()}
        (self.root / "before.json").write_text(json.dumps(before))
        (self.root / "after.json").write_text(json.dumps(self.after))
        args = ["beta_checks.py", "saves", str(self.root / "before.json"), str(self.root / "after.json")]
        with patch.object(sys, "argv", args), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(beta.main(), 0)
            release.write_text("changed")
            self.assertEqual(beta.main(), 1)
    def mobile(self):
        return {"build_sha256": "a" * 64, "cases": [dict(id=key, status="passed",
            requested=beta.REQUESTED_VIEWPORTS.get(key, [390, 844]), effective=[390, 748],
            device="test device", input_verified=True, physical_touch=True,
            text_readable=True, controls_reachable=True, evidence=self.evidence,
            actions={action: "passed" for action in beta.MOBILE_ACTIONS}) for key in beta.MOBILE_CASES]}

    def test_mobile_requires_touch_actions_and_effective_dimensions(self):
        data = self.mobile()
        self.assertEqual(beta.matrix(data, self.root, "mobile")["status"], "passed")
        data["cases"][-1]["physical_touch"] = False
        self.assertEqual(beta.matrix(data, self.root, "mobile")["status"], "blocked")
        data = self.mobile()
        del data["cases"][1]["effective"]
        data["cases"][0]["actions"]["resize"] = "unknown"
        self.assertEqual(beta.matrix(data, self.root, "mobile")["status"], "blocked")

    def test_changed_or_escaped_evidence_and_duplicate_cases_fail(self):
        data = self.mobile()
        (self.root / "evidence.txt").write_text("changed")
        self.assertEqual(beta.matrix(data, self.root, "mobile")["status"], "blocked")
        self.assertFalse(beta.evidence(self.root, {"file": "../outside", "sha256": "x"}))
        data["cases"].append(data["cases"][0])
        with self.assertRaises(ValueError):
            beta.matrix(data, self.root, "mobile")

    def test_multiplayer_needs_real_clients_and_two_subjects(self):
        data = {"build_sha256": "a" * 64, "subjects": ["a", "b"], "mode": "real-clients",
                "cases": [dict(id=key, status="passed", evidence=self.evidence)
                          for key in beta.MULTIPLAYER_CASES]}
        self.assertEqual(beta.matrix(data, self.root, "multiplayer")["status"], "passed")
        data["mode"] = "server-callback-fixture"
        self.assertEqual(beta.matrix(data, self.root, "multiplayer")["status"], "blocked")
        data["mode"] = "real-clients"
        data["subjects"] = ["a", "a"]
        self.assertEqual(beta.matrix(data, self.root, "multiplayer")["status"], "blocked")

    def test_beta_builder_is_separate_and_refuses_overwrite(self):
        project = {"tree": {"ServerScriptService": {"Server": {"$path": "src/server"}},
                            "ReplicatedStorage": {}}}
        target = self.root / "default.project.json"
        target.write_text(json.dumps(project))
        before = target.read_bytes()
        out = self.root / "build/beta"
        with patch.object(build_beta.shutil, "which", return_value="rojo"), \
                patch.object(build_beta.subprocess, "run") as command:
            build_beta.build(self.root, out)
            args = command.call_args.args[0]
            self.assertEqual(args[1], "build")
            self.assertEqual(command.call_args.kwargs["timeout"], 120)
            generated = json.loads((out / "beta.project.json").read_text())
            server = generated["tree"]["ServerScriptService"]
            self.assertTrue(server["$attributes"]["BetaQA"])
            self.assertTrue(server["BetaSnapshot"]["$properties"]["Disabled"])
            with self.assertRaises(FileExistsError):
                build_beta.build(self.root, out)
            self.assertEqual(command.call_count, 1)
            with self.assertRaises(ValueError):
                build_beta.build(self.root, self.root.parent)
        self.assertEqual(target.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()

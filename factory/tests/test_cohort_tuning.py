"""Cohort margin is explicit, validated, and cannot change the goalposts."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import random
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "factory/tools"))
import parse_spec
import simulate_economy as economy
import validate_config


class CohortTuningTests(unittest.TestCase):
    def setUp(self):
        self.spec = (ROOT / "games/egg-champions/spec.md").read_text(encoding="utf-8")
        self.cfg = parse_spec.parse(self.spec)

    def test_training_rates_follow_each_config_without_mutating_other_games(self):
        configured = copy.deepcopy(self.cfg)
        configured["constants"].update(training_hits_per_tick=6, training_tick_seconds=2)
        self.assertEqual(economy.training_rates(economy.Game(configured)), [3, 1.5])
        legacy = copy.deepcopy(self.cfg)
        del legacy["constants"]["training_hits_per_tick"]
        self.assertEqual(economy.training_rates(economy.Game(legacy)), economy.SIM["click_rates"])
        self.assertEqual(economy.training_rates(economy.Game(self.cfg)), [16, 8])

    def test_cached_forecast_preserves_seeded_player_decisions_and_rewards(self):
        gyms = json.loads((ROOT / "games/egg-champions/tuning/gyms.json").read_text())["gyms"]
        for floors in ((0, 0), (.65, .85)):
            config = copy.deepcopy(self.cfg)
            config["constants"].update(legacy_epic_floor=floors[0], legacy_legendary_floor=floors[1])
            game = economy.Game(config)
            for seed, cps in ((1, 8), (7, 16), (42, 16)):
                baseline = economy.simulate_player(game, gyms, cps, random.Random(seed), 144000, reuse_calculations=False)
                cached = economy.simulate_player(game, gyms, cps, random.Random(seed), 144000)
                self.assertEqual(cached, baseline)

    def test_parser_reads_margin_and_legacy_defaults_to_one(self):
        self.assertEqual([w["gym"]["cohort_power_factor"] for w in self.cfg["worlds"]], [1, 1, .8])
        lines = []
        inside = False
        for line in self.spec.splitlines():
            if line.startswith("| World |"):
                inside = True
            elif inside and not line.startswith("|"):
                inside = False
            if inside:
                line = "|".join(line.split("|")[:-2]) + "|"
            lines.append(line)
        old = parse_spec.parse("\n".join(lines))
        self.assertTrue(all(w["gym"]["cohort_power_factor"] == 1 for w in old["worlds"]))

    def test_margin_changes_only_final_leader_not_targets_pets_or_fees(self):
        baseline = copy.deepcopy(self.cfg)
        baseline["worlds"][-1]["gym"]["cohort_power_factor"] = 1
        def rate(game, team, leaders, rebirths, count, seed):
            return 1.0 if leaders[0]["hp"] <= 500 else 0.0
        with patch.object(economy, "win_rate", side_effect=rate):
            old = economy.tune_gyms(economy.Game(baseline), 1)
            new = economy.tune_gyms(economy.Game(self.cfg), 1)
        self.assertEqual(old[:2], new[:2])
        self.assertEqual(new[2]["reference_power"], old[2]["power"])
        self.assertEqual(new[2]["power"], round(old[2]["power"] * .8, 3))
        self.assertLess(new[2]["leader_team"][0]["hp"], old[2]["leader_team"][0]["hp"])
        self.assertEqual(new[2]["target_rebirths"], 5)
        self.assertEqual(new[2]["fee"], old[2]["fee"])
        self.assertEqual(new[2]["reference_team"], old[2]["reference_team"])

    def test_invalid_factors_fail_in_validator_and_tuner(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            folder = Path(temp)
            for name, data in self.cfg.items():
                (folder / (name + ".json")).write_text(json.dumps(data), encoding="utf-8")
            for factor in (0, -1, 1.1, True, "0.8", float("nan"), float("inf")):
                cfg = copy.deepcopy(self.cfg)
                cfg["worlds"][0]["gym"]["cohort_power_factor"] = factor
                (folder / "worlds.json").write_text(json.dumps(cfg["worlds"]), encoding="utf-8")
                self.assertTrue(any("cohort power" in e for e in validate_config.validate(folder)))
                with self.assertRaises(ValueError):
                    economy.tune_gyms(economy.Game(cfg), 1)


if __name__ == "__main__":
    unittest.main()

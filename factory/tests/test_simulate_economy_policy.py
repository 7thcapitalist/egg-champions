"""The simulated player fights as soon as the gym fee can be paid."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("sim", Path(__file__).parents[1] / "tools/simulate_economy.py")
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)


class WantsFarmTests(unittest.TestCase):
    def test_coins_below_fee_keep_farming(self):
        self.assertTrue(sim.wants_farm(False, 99, 100))

    def test_enough_coins_go_to_the_gym(self):
        self.assertFalse(sim.wants_farm(False, 100, 100))
        self.assertFalse(sim.wants_farm(False, 500, 100))

    def test_fee_already_paid_after_a_loss_fights_again(self):
        self.assertFalse(sim.wants_farm(True, 0, 100))
        self.assertFalse(sim.wants_farm(True, 500, 100))


if __name__ == "__main__":
    unittest.main()

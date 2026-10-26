"""Regression for the removed world-wide input capture; physical tests remain required."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class WorldInputTests(unittest.TestCase):
    def test_training_has_no_fullscreen_click_capture(self):
        source=(ROOT/"games/egg-champions/src/client/UI/Main.luau").read_text()
        self.assertNotIn('Name = "ClickLayer"', source)
        self.assertNotIn('ClickLayer', source)
        self.assertNotIn(':FireServer(', source)
        self.assertNotIn('ContextActionService', source)

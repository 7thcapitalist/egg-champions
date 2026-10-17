import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("quality_review", Path(__file__).parents[1] / "tools/quality_review.py")
quality = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quality)

class QualityReviewTests(unittest.TestCase):
    def test_requires_current_complete_review_and_local_evidence(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parents[2]) as folder:
            game = Path(folder)
            (game / "src").mkdir()
            code = game / "src/main.luau"
            code.write_text("return 1")
            (game / "shot.jpg").write_bytes(b"evidence")
            review = dict(source_sha256=quality.source_hash(game), reviewer="Tester", date="2026-10-16", environment="Studio", limitations="Emulator only", viewports=["desktop", "mobile"], categories={key:dict(score=4, observation="Inspected in engine", evidence=["shot.jpg"]) for key in quality.CATEGORIES})
            self.assertEqual(quality.check(game, review), [])
            (game / "assets").mkdir()
            (game / "assets/models.json").write_text('{}')
            self.assertTrue(any("stale" in s for s in quality.check(game, review)))
            review["source_sha256"] = quality.source_hash(game)
            review["viewports"] = ["desktop", "other"]
            self.assertTrue(any("mobile" in s for s in quality.check(game, review)))
            review["categories"]["models"]["score"] = 3
            self.assertTrue(any("score" in s for s in quality.check(game, review)))
            review["categories"]["models"]["evidence"] = ["../outside.jpg"]
            self.assertTrue(any("evidence outside" in s for s in quality.check(game, review)))
            code.write_text("return 2")
            self.assertTrue(any("stale" in s for s in quality.check(game, review)))

if __name__ == "__main__":
    unittest.main()

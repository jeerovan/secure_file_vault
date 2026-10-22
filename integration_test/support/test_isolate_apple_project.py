"""Verify native fixtures cannot reuse a manual app's container identity."""

import hashlib
from pathlib import Path
import re
import shutil
import unittest

import isolate_apple_project


class AppleFixtureIdentityTest(unittest.TestCase):
    def test_each_fixture_has_its_own_identity_and_preserves_source(self):
        root = Path(__file__).resolve().parents[2]
        originals = [
            root / "ios/Runner.xcodeproj/project.pbxproj",
            root / "macos/Runner/Configs/AppInfo.xcconfig",
            root / "macos/Runner/DebugProfile.entitlements",
            root / "macos/Runner/Release.entitlements",
        ]
        hashes = [hashlib.sha256(path.read_bytes()).digest() for path in originals]
        identities = []
        for _ in range(2):
            project = isolate_apple_project.prepare()
            self.addCleanup(shutil.rmtree, project)
            config = (project / "macos/Runner/Configs/AppInfo.xcconfig").read_text()
            bundle = re.search(r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)", config, re.M)[1]
            self.assertRegex(
                bundle,
                r"^com\.jeerovan\.fife\.localtest\.fixture\.run[a-f0-9]{32}$",
            )
            identities.append(bundle)
            self.assertIn("PRODUCT_NAME = FiFe Native Test", config)
            ios = (project / "ios/Runner.xcodeproj/project.pbxproj").read_text()
            self.assertEqual(ios.count(f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"), 3)
            for name in ("DebugProfile.entitlements", "Release.entitlements"):
                self.assertIn(bundle, (project / "macos/Runner" / name).read_text())
        self.assertNotEqual(*identities)
        self.assertEqual(hashes, [hashlib.sha256(path.read_bytes()).digest() for path in originals])


if __name__ == "__main__":
    unittest.main()

import plistlib
from pathlib import Path
import tempfile
import unittest

from verify_sdk import require_ios_sdk, verify_ipa_info


class TestIOSSDK(unittest.TestCase):
    def test_old_runner_sdk_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "iOS SDK 27 or later"):
            require_ios_sdk("26.5")
        self.assertEqual(require_ios_sdk("27.2"), "27.2")
        self.assertEqual(require_ios_sdk("28.0"), "28.0")

    def test_upload_requires_new_device_sdk_in_signed_binary_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            info = Path(directory) / "Info.plist"
            info.write_bytes(plistlib.dumps({"DTSDKName": "iphoneos27.1"}, fmt=plistlib.FMT_BINARY))
            self.assertEqual(verify_ipa_info(info), "27.1")
            for bad_sdk in ("iphoneos26.5", "iphonesimulator27.1", "", None):
                with self.subTest(bad_sdk=bad_sdk):
                    value = {"DTSDKName": bad_sdk} if bad_sdk is not None else {}
                    info.write_bytes(plistlib.dumps(value))
                    with self.assertRaises(ValueError):
                        verify_ipa_info(info)

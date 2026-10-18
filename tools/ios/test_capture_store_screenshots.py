"""Cross-platform checks for the screenshot capture coordinator (no Mac needed)."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import capture_store_screenshots as capture


class ScreenshotWorkflowTests(unittest.TestCase):
    def test_selects_latest_available_ios_runtime(self):
        runtimes = {
            "runtimes": [
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-25-4",
                    "version": "25.4",
                    "isAvailable": True,
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                    "version": "26.0",
                    "isAvailable": True,
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                    "version": "27.0",
                    "isAvailable": False,
                },
            ]
        }
        with patch.object(capture, "cmd", return_value=json.dumps(runtimes)):
            self.assertEqual(
                capture.choose_ios_runtime(),
                "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
            )

    def test_requires_an_exact_device_type(self):
        types = {
            "devicetypes": [
                {"name": "iPhone 16 Pro", "identifier": "iphone-type"},
                {"name": "iPad Pro 13-inch (M4)", "identifier": "ipad-type"},
            ]
        }
        with patch.object(capture, "cmd", return_value=json.dumps(types)):
            for name, identifier in (
                ("iPhone 16 Pro", "iphone-type"),
                ("iPad Pro 13-inch (M4)", "ipad-type"),
            ):
                self.assertEqual(
                    capture.device_type((name,)), (identifier, name)
                )
            with self.assertRaisesRegex(RuntimeError, "Missing exact-size"):
                capture.device_type(("iPad 11-inch",))

    def test_reads_sips_pixel_dimensions(self):
        output = (
            "/tmp/app.jpg\n"
            "  pixelWidth: 1206\n"
            "  pixelHeight: 2622\n"
        )
        with patch.object(capture, "cmd", return_value=output):
            self.assertEqual(capture.dimensions(Path("/tmp/app.jpg")), (1206, 2622))

    def test_requires_page_ready_marker_to_match(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / capture.MARKER
            marker.write_text("ready:town\n", encoding="utf-8")
            capture.await_rendered_page(marker, "town")
            with self.assertRaisesRegex(RuntimeError, "Unexpected screenshot status"):
                capture.await_rendered_page(marker, "missions")


if __name__ == "__main__":
    unittest.main()

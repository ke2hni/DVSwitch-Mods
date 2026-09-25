#!/usr/bin/env python3
"""Check dark-theme contrast for current and legacy Buttons DMR labels."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "dvswitch-dark-mode.sh").read_text()
MATCH = re.search(r"<<'CSS'\n(.*?)^CSS$", SOURCE, re.MULTILINE | re.DOTALL)
assert MATCH, "theme CSS template is missing"
CSS = MATCH.group(1)


class DarkModeDmrRoomLabelTest(unittest.TestCase):
    def test_dark_and_auto_dark_modes_override_inline_black(self):
        self.assertIn("body.theme-dark .dvs-dmr-room-label", CSS)
        self.assertIn("body.theme-auto.dvs-prefers-dark .dvs-dmr-room-label", CSS)
        self.assertIn("color: #e5e7eb !important;", CSS)

    def test_legacy_buttons_markup_remains_readable_during_upgrade(self):
        self.assertIn('td[style*="background: #ffffed"] > span[style*="color:#b5651d"] > span[style*="color:#000000"]', CSS)


if __name__ == "__main__":
    unittest.main()

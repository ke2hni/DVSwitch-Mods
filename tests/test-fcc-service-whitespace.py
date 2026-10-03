#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Ensure the FCC checker ignores only trailing blank lines in its service unit."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
start = source.index("unit_file_matches() {")
end = source.index("\n}\n\nupdater_release_state()", start) + 2
function = source[start:end]

with tempfile.TemporaryDirectory(prefix="fcc-unit-whitespace-") as directory:
    root = Path(directory)
    expected = root / "expected.service"
    installed = root / "installed.service"
    expected.write_text("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/true\n")

    def matches(contents: str) -> bool:
        installed.write_text(contents)
        result = subprocess.run(
            ["bash", "-c", function + '\nunit_file_matches "$1" "$2"', "test", str(expected), str(installed)],
            check=False,
        )
        return result.returncode == 0

    assert matches("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/true\n\n"), "trailing blank line should be ignored"
    assert not matches("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/false\n"), "meaningful unit change was ignored"
    assert not matches("[Unit]\nDescription=Test\n\n[Service]\nExecStart=/bin/true\n"), "interior blank-line difference was ignored"

print("PASS: FCC systemd service comparison ignores only trailing blank lines")

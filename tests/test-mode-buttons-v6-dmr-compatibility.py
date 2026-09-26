#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Ensure DVSwitch-Mods recognizes the current Mode Buttons DMR card."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DMR = (ROOT / "mod-dmr-friendly-names.sh").read_text()
YSF = (ROOT / "repair-ysf-dashboard-null.sh").read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    current_marker = "// DVSwitch-Mode-Buttons: standalone DMR Master display v6"
    require(f'BUTTONS_MARKER="{current_marker}"' in DMR,
            "DMR friendly-name check does not recognize the Mode Buttons v6 card")
    require("buttons_markers = tuple(" in YSF and "range(1, 7)" in YSF,
            "YSF dashboard repair does not recognize supported Mode Buttons DMR card markers")
    require("dvsButtonsDmrMasterDisplay($dmrMasterHost, $abinfo)" in DMR and
            "dvsButtonsDmrMasterHeading($dmrMasterHost, $abinfo)" in DMR,
            "DMR friendly-name check does not validate the shared card entry points")
    print("PASS: DVSwitch-Mods accepts the standalone Mode Buttons v6 DMR card")


if __name__ == "__main__":
    main()

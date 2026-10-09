#!/usr/bin/env python3
# Version: 1.0.0
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
    current_marker = "// DVSwitch-Mode-Buttons: standalone DMR Master display v9"
    require(f'BUTTONS_MARKER="{current_marker}"' in DMR,
            "DMR friendly-name check does not recognize the Mode Buttons v9 card")
    previous_marker = "// DVSwitch-Mode-Buttons: standalone DMR Master display v8"
    older_marker = "// DVSwitch-Mode-Buttons: standalone DMR Master display v7"
    require(f'BUTTONS_PREVIOUS_MARKER="{previous_marker}"' in DMR and
            f'BUTTONS_OLDER_MARKER="{older_marker}"' in DMR and
            "Previous Buttons v7 is still structurally valid" in DMR,
            "Mods blocks installation when an older separately owned Buttons card is installed first")
    require("buttons_markers = tuple(" in YSF and "range(1, 10)" in YSF,
            "YSF dashboard repair does not recognize supported Mode Buttons DMR card markers")
    require("dvsButtonsDmrMasterDisplay($dmrMasterHost, $abinfo)" in DMR and
            "dvsButtonsDmrMasterHeading($dmrMasterHost, $abinfo)" in DMR,
            "DMR friendly-name check does not validate the shared card entry points")
    require("standalone DMR Master display v[1-9]" in YSF,
            "YSF installed-state check does not recognize the Mode Buttons v9 card")
    require("function dvsButtonsDmrCurrentMode(\\$abinfo, \\$selectedModeFile = null)" in DMR,
            "DMR friendly-name check does not validate the v9 selected-mode resolver")
    print("PASS: DVSwitch-Mods accepts the standalone Mode Buttons v9 DMR card")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Static regression checks for DMR/Mode-Buttons YSF dashboard compatibility."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "repair-ysf-dashboard-null.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    text = INSTALLER.read_text()
    require('SCRIPT_VERSION="1.0.6"' in text, "YSF repair version was not advanced")
    require('DMR_V7_STATUS_HASH="70cc3f29e06d1b5b1bc6cee6a605c9936f72b939f70fad7597dc73cbe8aefc87"' in text,
            "valid unmodified DMR-v7 status hash is missing")
    require('DMR_V7_YSF_STATUS_HASH="4a7c3ca33091eba398ec0517d5ee69fb383c5889621e60fda8745c737a3655c5"' in text,
            "expected repaired DMR-v7/YSF status hash is missing")
    require('os.environ["DVS_DMR_V7_STATUS_HASH"]' in text,
            "DMR-v7 base hash is not accepted by the structural patcher")
    require("dmr_v7_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v7'" in text,
            "installed-state verification does not count the DMR-v7 marker")
    require('dmr_v8_count -eq 1 && $buttons_v5_count -eq 1' in text,
            "combined DMR-v8 and Mode Buttons-v5 state is not explicitly accepted")
    require('dvswitch_mods_marker_count -eq 1 && $buttons_v5_count -eq 0' in text,
            "single DVSwitch-Mods marker without a Mode Buttons marker is not accepted")
    print("PASS: YSF repair accepts the valid combined DMR-v8 and Mode Buttons-v5 state")


if __name__ == "__main__":
    main()

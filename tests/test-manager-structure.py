#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Static safety and coverage checks for the two public managers."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "manage-dvswitch-mods.sh"
MMDVM = ROOT / "manage-mmdvm-spacing.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    master = MASTER.read_text()
    mmdvm = MMDVM.read_text()

    children = (
        "manage-mmdvm-spacing.sh",
        "repair-dvswitch-txt-updater.sh",
        "repair-p25-audio-announcement.sh",
        "repair-p25-dashboard.sh",
        "mod-p25-nxdn-json.sh",
        "mod-p25-nxdn-friendly-names.sh",
        "mod-dstar-tx-ref.sh",
        "mod-dmr-friendly-names.sh",
        "repair-ysf-dashboard-null.sh",
        "mod-dashboard-fcc-first-names.sh",
        "mod-dashboard-targets.sh",
    )
    for name in children:
        path = ROOT / name
        require(path.is_file(), f"missing managed component: {name}")
        require(path.read_bytes().startswith(b"#!"),
                f"managed component lacks the expected shell entry point: {name}")
        require(name in master, f"manager does not reference component: {name}")

    for name in (
        "repair-mmdvm-spacing.sh",
        "repair-mmdvm-spacing-armhf.sh",
        "repair-mmdvm-spacing-x86.sh",
    ):
        require(name in mmdvm, f"MMDVM manager does not reference: {name}")

    require('UNINSTALL_ACTION="--uninstall"' in master,
            "MMDVM/FCC complete-uninstall action is unavailable")
    require("strict reverse" in master,
            "reverse-order uninstall safety notice is missing")
    require("last_state_line" in master and "remove_last_state_line" in master,
            "recorded LIFO uninstall implementation is missing")
    require("component_is_recorded" in master and "continuing from the next unrecorded component" in master,
            "safe interrupted-install resume behavior is missing")
    require("check_all" in master and "PLAIN-LANGUAGE SUMMARY" in master,
            "complete check-all reporting is missing")
    require("Failed or blocked:" in master and "Required installation order" in master,
            "plain-language failure or ordering summary is missing")
    require('"$CHILD_SCRIPT" --check' in master,
            "child compatibility checks are not enforced")
    require("record_install" in master and "POST-INSTALL CHECK" in master,
            "reversible state recording or post-install validation is missing")
    require("Refusing symbolic-link" in master and "flock -n" in master,
            "state-file link or concurrency protection is missing")
    require("ensure_databases" in master and '"$DVSWITCH_COMMAND" update' in master,
            "required post-JSON database update is missing")
    require("DATABASE_MIN_INTERVAL=3600" in master and "less than one hour ago" in master,
            "one-hour database update guard is missing")
    require("last-database-update" in master and "stat -c '%Y'" in master,
            "database update timestamp protection is missing")
    require(master.index('mv -fT -- "$temporary" "$DATABASE_UPDATE_STAMP"') <
            master.index('"$DVSWITCH_COMMAND" update'),
            "rate-limit attempt timestamp must be saved before downloading")
    for name in ("NXDNHosts.json", "P25Hosts.json", "TGList_BM.txt", "TGList_TGIF.txt", "YSFHosts.txt"):
        require(name in master, f"required managed database is missing: {name}")
    require("--uninstall BACKUP-NAME" in mmdvm,
            "MMDVM backup-driven uninstall interface is missing")
    require("Unsupported MMDVM_Bridge architecture" in mmdvm,
            "unknown architectures are not rejected")

    print("PASS: unified manager structure and safety checks")


if __name__ == "__main__":
    main()

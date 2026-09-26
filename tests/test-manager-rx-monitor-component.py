#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Check RX Monitor and STFU follow the manager's standard component flow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "manage-dvswitch-mods.sh"
INSTALLER = ROOT / "mod-dashboard-rx-monitor-left.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    manager = MANAGER.read_text()
    installer = INSTALLER.read_text()
    require(INSTALLER.is_file() and INSTALLER.stat().st_mode & 0o111,
            "RX Monitor installer is missing or not executable")
    component_list = manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0]
    require(component_list.rstrip().endswith("dashboard-stfu-status\n    dashboard-rx-monitor-left"),
            "STFU and RX Monitor are not appended to the standard component order")
    require('Choose an option [0/1/2/3]:' in manager and '"4) Install STFU status cards' not in manager
            and '"5) Move RX Monitor' not in manager,
            "STFU or RX Monitor was incorrectly added as a dedicated menu option")
    require("1) initialize_state; install_requested all ;;" in manager,
            "standard menu install does not process the complete component list")
    require('dashboard-stfu-status) CHILD_SCRIPT="$SCRIPT_DIR/mod-dashboard-stfu-status.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-stfu-status"; UNINSTALL_ACTION="--uninstall"' in manager,
            "STFU manager install/uninstall mapping or protected backup root is incorrect")
    require('dashboard-rx-monitor-left) CHILD_SCRIPT="$SCRIPT_DIR/mod-dashboard-rx-monitor-left.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-rx-monitor-left"; UNINSTALL_ACTION="--uninstall"' in manager,
            "manager uninstall mapping or protected backup root is incorrect")
    print("PASS: STFU and RX Monitor use the standard manager install and reverse-order uninstall flow")


if __name__ == "__main__":
    main()

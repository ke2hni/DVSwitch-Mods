#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Verify Install All rechecks and upgrades a manager-recorded component."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


with tempfile.TemporaryDirectory(
    prefix="dvswitch-manager-upgrade-", dir=ROOT.parent
) as temp:
    sandbox = Path(temp)
    manager_dir = sandbox / "manager"
    state_dir = sandbox / "state"
    backup_root = sandbox / "backups"
    fake_bin = sandbox / "bin"
    manager_dir.mkdir()
    state_dir.mkdir()
    backup_root.mkdir()
    fake_bin.mkdir()

    manager_text = (ROOT / "manage-dvswitch-mods.sh").read_text(encoding="utf-8")
    manager_text = manager_text.replace(
        'readonly STATE_DIR="/var/lib/dvswitch-mods/manager"',
        f'readonly STATE_DIR="{state_dir}"',
        1,
    )
    manager_text = re.sub(
        r"readonly -a COMPONENTS=\(.*?\n\)",
        'readonly -a COMPONENTS=(\n    dashboard-fcc-first-names\n)',
        manager_text,
        count=1,
        flags=re.S,
    )
    manager_text = re.sub(
        r"ensure_build_dependencies\(\) \{.*?\n\}",
        "ensure_build_dependencies() { return 0; }",
        manager_text,
        count=1,
        flags=re.S,
    )
    manager_text = re.sub(
        r"initialize_state\(\) \{.*?\n\}\n\npreflight_recorded_backups\(\)",
        '''initialize_state() {
    mkdir -p "$STATE_DIR"
    [[ -e "$STATE_FILE" ]] || : > "$STATE_FILE"
    [[ -e "$LOCK_FILE" ]] || : > "$LOCK_FILE"
    exec 9>"$LOCK_FILE"
    flock -n 9
}

preflight_recorded_backups()''',
        manager_text,
        count=1,
        flags=re.S,
    )
    manager_text = manager_text.replace(
        'BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"',
        f'BACKUP_ROOT="{backup_root}"',
        1,
    )
    manager = manager_dir / "manage-dvswitch-mods.sh"
    manager.write_text(manager_text, encoding="utf-8")
    manager.chmod(0o755)

    original_backup = "install-original"
    (backup_root / original_backup).mkdir()
    state_file = state_dir / "active-installs.tsv"
    state_file.write_text(
        f"dashboard-fcc-first-names\tmod-dashboard-fcc-first-names.sh\t{backup_root}\t{original_backup}\t--uninstall\n",
        encoding="utf-8",
    )

    version_file = sandbox / "installed-version"
    version_file.write_text("old\n", encoding="utf-8")
    call_log = sandbox / "installer-calls.log"
    fake_installer = manager_dir / "mod-dashboard-fcc-first-names.sh"
    fake_installer.write_text(
        "#!/bin/bash\n"
        "set -euo pipefail\n"
        f"version_file={str(version_file)!r}\n"
        f"backup_root={str(backup_root)!r}\n"
        f"call_log={str(call_log)!r}\n"
        "case \"${1:-}\" in\n"
        "  --check) echo check >> \"$call_log\"; if [[ $(<\"$version_file\") == old ]]; then echo 'MODIFICATION READY: upgrade available'; else echo 'ALREADY MODIFIED: current'; fi ;;\n"
        "  --install)\n"
        "    echo install >> \"$call_log\"\n"
        "    if [[ $(<\"$version_file\") == old ]]; then\n"
        "      mkdir -p \"$backup_root/install-upgrade\"\n"
        "      printf 'new\\n' > \"$version_file\"\n"
        "    fi\n"
        "    ;;\n"
        "  *) exit 2 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    fake_installer.chmod(0o755)

    fake_chown = fake_bin / "chown"
    fake_chown.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    fake_chown.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env['PATH']}"

    first = subprocess.run(
        ["bash", str(manager), "--install", "all"],
        env=env,
        text=True,
        capture_output=True,
    )
    require(first.returncode == 0, "recorded-component upgrade failed: " + first.stderr)
    require("MODIFICATION READY: upgrade available" in first.stdout,
            "manager did not run the component check for a recorded installation")
    require("POST-INSTALL CHECK" in first.stdout,
            "manager did not verify the upgraded component")
    require(version_file.read_text(encoding="utf-8").strip() == "new",
            "recorded component's installer was not run")
    record = state_file.read_text(encoding="utf-8").strip().split("\t")
    require(record[3] == "install-upgrade", "active manager backup record was not replaced")
    require((backup_root / original_backup).is_dir(), "previous backup was unexpectedly deleted")
    require(call_log.read_text(encoding="utf-8").splitlines() == ["check", "install", "check"],
            "expected check, install, then post-install check calls were not made")

    second = subprocess.run(
        ["bash", str(manager), "--install", "all"],
        env=env,
        text=True,
        capture_output=True,
    )
    require(second.returncode == 0, "idempotent second Install All failed: " + second.stderr)
    require("installer created no new backup" in second.stdout,
            "manager did not retain the record for an already-current component")
    require(state_file.read_text(encoding="utf-8").strip().split("\t")[3] == "install-upgrade",
            "idempotent run changed the active backup record")
    require(call_log.read_text(encoding="utf-8").splitlines() == [
        "check", "install", "check", "check", "install"
    ], "second Install All did not recheck and run the current component installer")

print("PASS: Install All checks and upgrades recorded components, then remains idempotent")

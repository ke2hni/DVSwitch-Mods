#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Test systemd whitespace and the prior FCC timer interval explicitly."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
start = source.index("unit_file_matches() {")
end = source.index("\n}\n\nupdater_release_state()", start) + 2
functions = source[start:end]
release_start = source.index("updater_release_state() {")
release_end = source.index("\n}\n\nverify_updater_components()", release_start) + 2
release_state_function = source[release_start:release_end]
transaction_start = source.index("transaction_library_supported() {")
transaction_end = source.index("\n}\n\nupdater_release_state()", transaction_start) + 2
transaction_support_function = source[transaction_start:transaction_end]
assert 'unit_file_matches "$SERVICE_SOURCE" "$SERVICE_TARGET"' in source, "service unit must use whitespace-tolerant comparison"
assert source.count('timer_file_matches_supported "$TIMER_SOURCE" "$TIMER_TARGET"') == 1, "previous-release validation must accept the supported prior timer"
assert 'unit_file_matches "$TIMER_SOURCE" "$TIMER_TARGET"' in source, "current timer detection must remain exact apart from trailing whitespace"
assert 'cmp -s "$TIMER_SOURCE" "$TIMER_TARGET"' not in source, "strict timer comparison remains"
assert 'cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die' not in source, "transaction helper still has a byte-for-byte version gate"

with tempfile.TemporaryDirectory(prefix="fcc-unit-whitespace-") as directory:
    root = Path(directory)
    expected = root / "expected.service"
    installed = root / "installed.service"
    expected.write_text("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/true\n")

    def matches(contents: str) -> bool:
        installed.write_text(contents)
        result = subprocess.run(
            ["bash", "-c", functions + '\nunit_file_matches "$1" "$2"', "test", str(expected), str(installed)],
            check=False,
        )
        return result.returncode == 0

    assert matches("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/true\n\n"), "trailing blank line should be ignored"
    assert not matches("[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/false\n"), "meaningful unit change was ignored"
    assert not matches("[Unit]\nDescription=Test\n\n[Service]\nExecStart=/bin/true\n"), "interior blank-line difference was ignored"

    expected_timer = root / "expected.timer"
    installed_timer = root / "installed.timer"
    timer_text = "[Timer]\nOnCalendar=Mon *-*-* 00:00:00\nPersistent=true\nRandomizedDelaySec=6h\nUnit=dvswitch-fcc-first-names-update.service\n"
    expected_timer.write_text(timer_text)

    def timer_matches(contents: str) -> bool:
        installed_timer.write_text(contents)
        result = subprocess.run(
            ["bash", "-c", functions + '\ntimer_file_matches_supported "$1" "$2"', "test", str(expected_timer), str(installed_timer)],
            check=False,
        )
        return result.returncode == 0

    assert timer_matches(timer_text), "current 6h timer should match"
    assert timer_matches(timer_text.replace("RandomizedDelaySec=6h", "RandomizedDelaySec=96h") + "\n"), "known 96h previous timer should be recognized despite trailing blank line"
    assert not timer_matches(timer_text.replace("RandomizedDelaySec=6h", "RandomizedDelaySec=24h")), "unsupported timer interval was accepted"

    # Exercise the actual updater_release_state branch using isolated files and
    # stub only platform state (updater state, installed patcher recognition,
    # and systemctl). The known prior interval must return upgradeable.
    update_files = {name: root / name for name in (
        "updater", "builder", "patcher", "transaction", "service-source",
        "service-target", "timer-source", "timer-target",
    )}
    update_files["updater"].write_text("updater\n")
    update_files["builder"].write_text("builder\n")
    update_files["patcher"].write_text("patcher\n")
    transaction_source = """dvsm_transaction_begin() { :; }
dvsm_backup_file() { :; }
dvsm_install_candidate() { :; }
dvsm_transaction_rollback() { :; }
"""
    update_files["transaction"].write_text(transaction_source + "# current source\n")
    transaction_target = root / "transaction-installed"
    transaction_target.write_text(transaction_source + "# compatible prior build\n")
    update_files["service-source"].write_text("[Service]\nExecStart=/bin/true\n")
    update_files["service-target"].write_text("[Service]\nExecStart=/bin/true\n\n")
    update_files["timer-source"].write_text(timer_text)
    update_files["timer-target"].write_text(timer_text.replace("RandomizedDelaySec=6h", "RandomizedDelaySec=96h"))
    for name in ("updater", "builder", "patcher", "transaction", "service-source", "service-target", "timer-source", "timer-target"):
        update_files[name].chmod(0o755 if name == "updater" else 0o644)
    transaction_target.chmod(0o644)

    harness = functions + """
die() { printf '%s\\n' "$*" >&2; exit 1; }
systemctl() { return 0; }
updater_state() { printf 'present'; }
patcher_structure_supported() { return 0; }
""" + transaction_support_function + "\n" + release_state_function + "\nupdater_release_state\n"
    env = {
        "UPDATER_TARGET": str(update_files["updater"]),
        "BUILDER_TARGET": str(update_files["builder"]),
        "PATCHER_TARGET": str(update_files["patcher"]),
        "TRANSACTION_TARGET": str(transaction_target),
        "SERVICE_TARGET": str(update_files["service-target"]),
        "TIMER_TARGET": str(update_files["timer-target"]),
        "UPDATER_SOURCE": str(update_files["updater"]),
        "BUILDER": str(update_files["builder"]),
        "PATCHER": str(update_files["patcher"]),
        "TRANSACTION_LIBRARY": str(update_files["transaction"]),
        "SERVICE_SOURCE": str(update_files["service-source"]),
        "TIMER_SOURCE": str(update_files["timer-source"]),
        "TIMER_UNIT": "test.timer",
    }
    result = subprocess.run(["bash", "-c", harness], env=env, text=True, capture_output=True)
    assert result.returncode == 0 and result.stdout.strip() == "upgradeable", (
        "96h prior timer should make updater upgradeable, "
        f"got rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    update_files["timer-target"].write_text(timer_text.replace("RandomizedDelaySec=6h", "RandomizedDelaySec=24h"))
    result = subprocess.run(["bash", "-c", harness], env=env, text=True, capture_output=True)
    assert result.returncode != 0 and "does not match the supported previous release" in result.stderr, "unexpected timer setting should still be rejected"

print("PASS: FCC service whitespace and current/previous timer release-state tests")

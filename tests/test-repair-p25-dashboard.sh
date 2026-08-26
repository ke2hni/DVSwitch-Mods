#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPAIR="$REPO_ROOT/repair-p25-dashboard.sh"
readonly PATCHER="$REPO_ROOT/lib/patch_p25_dashboard.py"
readonly PATCHER_TEST="$REPO_ROOT/tests/test-p25-dashboard-patcher.py"
readonly TRANSACTION_LIBRARY="$REPO_ROOT/lib/transaction.sh"
readonly TARGET="/usr/share/dvswitch/include/functions.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/p25-dashboard"

fail() { printf 'TEST FAILURE: %s\n' "$1" >&2; exit 1; }

for file in "$REPAIR" "$PATCHER" "$PATCHER_TEST" "$TRANSACTION_LIBRARY"; do [[ -f "$file" && ! -L "$file" ]] || fail "required regular file is missing: $file"; done
bash -n "$REPAIR" || fail "repair installer failed shell syntax validation"
python3 -m py_compile "$PATCHER" "$PATCHER_TEST" || fail "Python syntax validation failed"
python3 "$PATCHER_TEST" || fail "patcher unit tests failed"

grep -Fq 'SPDX-License-Identifier: MIT' "$REPAIR" || fail "installer MIT SPDX identifier is missing"
grep -Fq 'SPDX-License-Identifier: MIT' "$PATCHER" || fail "patcher MIT SPDX identifier is missing"
grep -Fq '/usr/share/dvswitch/include/functions.php' "$REPAIR" || fail "fixed dashboard target is missing"
grep -Fq '/var/backups/dvswitch-mods/p25-dashboard' "$REPAIR" || fail "dedicated backup root is missing"
grep -Fq 'lib/transaction.sh' "$REPAIR" || fail "transaction library reference is missing"

help_output=$(bash "$REPAIR" --help)
grep -Fq 'P25 dashboard compatibility repair 0.4.0-dev' <<<"$help_output" || fail "installer version is missing"
for option in --check --dry-run --install --restore; do grep -Fq -- "$option" "$REPAIR" || fail "option missing: $option"; done

for forbidden in status.php P25Hosts.json NXDNHosts.json formatReflectorLink ceil dvswitch.sh MMDVM_Bridge; do if grep -Fq "$forbidden" "$REPAIR" "$PATCHER"; then fail "unrelated stage reference found: $forbidden"; fi; done

if [[ ${EUID:-$(id -u)} -eq 0 && -f "$TARGET" && ! -L "$TARGET" ]]; then
    before_hash=$(sha256sum "$TARGET")
    before_metadata=$(stat -c '%u:%g:%a:%s' "$TARGET")
    if [[ -d "$BACKUP_ROOT" ]]; then before_backups=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'install-*' | wc -l); else before_backups=0; fi
    "$REPAIR" --check
    [[ "$before_hash" == "$(sha256sum "$TARGET")" ]] || fail "--check changed the live target"
    [[ "$before_metadata" == "$(stat -c '%u:%g:%a:%s' "$TARGET")" ]] || fail "--check changed live metadata"
    if [[ -d "$BACKUP_ROOT" ]]; then after_backups=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'install-*' | wc -l); else after_backups=0; fi
    [[ "$before_backups" == "$after_backups" ]] || fail "--check created a backup"
elif [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf 'SKIP: live dashboard target is not installed in this test environment.\n'
else
    printf 'SKIP: live --check test requires root; run this test with sudo on each test node.\n'
fi

printf 'PASS: standalone P25 dashboard compatibility repair tests\n'

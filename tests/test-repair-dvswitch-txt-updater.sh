#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPAIR="$REPO_ROOT/repair-dvswitch-txt-updater.sh"
readonly PATCHER="$REPO_ROOT/lib/patch_dvswitch_txt_updater.py"
readonly PATCHER_TEST="$REPO_ROOT/tests/test-dvswitch-txt-updater-patcher.py"
readonly TRANSACTION_LIBRARY="$REPO_ROOT/lib/transaction.sh"
readonly TARGET="/opt/MMDVM_Bridge/dvswitch.sh"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/txt-updater"

fail() { printf 'TEST FAILURE: %s\n' "$1" >&2; exit 1; }

for file in "$REPAIR" "$PATCHER" "$PATCHER_TEST" "$TRANSACTION_LIBRARY"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
    [[ ! -L "$file" ]] || fail "required file is a symbolic link: $file"
done

bash -n "$REPAIR" || fail "repair installer failed shell syntax validation"
python3 -m py_compile "$PATCHER" "$PATCHER_TEST" || fail "Python syntax validation failed"
python3 "$PATCHER_TEST" || fail "patcher unit tests failed"

grep -Fq 'SPDX-License-Identifier: MIT' "$REPAIR" || fail "installer MIT SPDX identifier is missing"
grep -Fq 'SPDX-License-Identifier: MIT' "$PATCHER" || fail "patcher MIT SPDX identifier is missing"
grep -Fq '/opt/MMDVM_Bridge/dvswitch.sh' "$REPAIR" || fail "fixed installed target is missing"
grep -Fq 'lib/patch_dvswitch_txt_updater.py' "$REPAIR" || fail "TXT updater patcher reference is missing"
grep -Fq 'lib/transaction.sh' "$REPAIR" || fail "transaction library reference is missing"
grep -Fq '/var/backups/dvswitch-mods/txt-updater' "$REPAIR" || fail "dedicated backup root is missing"

help_output=$(bash "$REPAIR" --help)
grep -Fq 'DVSwitch TXT updater repair 0.4.0-dev' <<<"$help_output" || fail "installer version is missing"
grep -Fq 'Usage:' <<<"$help_output" || fail "usage text is missing"
for option in --check --dry-run --install --restore; do
    grep -Fq -- "$option" "$REPAIR" || fail "option missing: $option"
done

set +e
no_argument_output=$(bash "$REPAIR" 2>&1)
no_argument_status=$?
unknown_output=$(bash "$REPAIR" --not-a-real-option 2>&1)
unknown_status=$?
set -e
[[ $no_argument_status -eq 2 ]] || fail "no-argument status is not 2"
grep -Fq 'Usage:' <<<"$no_argument_output" || fail "no-argument usage is missing"
[[ $unknown_status -eq 1 ]] || fail "unknown-option status is not 1"
grep -Fq 'ERROR: Unknown option:' <<<"$unknown_output" || fail "unknown-option error is missing"

for forbidden in functions.php status.php P25Hosts.json NXDNHosts.json patch_p25_nxdn.py patch_mmdvm_binary.py formatReflectorLink; do
    if grep -Fq "$forbidden" "$REPAIR" "$PATCHER"; then
        fail "unrelated stage reference found: $forbidden"
    fi
done

for required in 'mktemp "${MMDVM_DIR}/.${_name}.download.XXXXXX"' 'chown --reference="${_live}"' 'chmod --reference="${_live}"' 'mv -f -- "${_candidate}" "${_live}"'; do
    grep -Fq "$required" "$PATCHER" || fail "safe updater operation is missing: $required"
done

if [[ ${EUID:-$(id -u)} -eq 0 && -f "$TARGET" && ! -L "$TARGET" ]]; then
    before_hash=$(sha256sum "$TARGET")
    before_metadata=$(stat -c '%u:%g:%a:%s' "$TARGET")
    if [[ -d "$BACKUP_ROOT" ]]; then
        before_backups=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'install-*' | wc -l)
    else
        before_backups=0
    fi

    "$REPAIR" --check

    [[ "$before_hash" == "$(sha256sum "$TARGET")" ]] || fail "--check changed the live target"
    [[ "$before_metadata" == "$(stat -c '%u:%g:%a:%s' "$TARGET")" ]] || fail "--check changed live metadata"
    if [[ -d "$BACKUP_ROOT" ]]; then
        after_backups=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'install-*' | wc -l)
    else
        after_backups=0
    fi
    [[ "$before_backups" == "$after_backups" ]] || fail "--check created a backup"
elif [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf 'SKIP: live DVSwitch target is not installed in this test environment.\n'
else
    printf 'SKIP: live --check test requires root; run this test with sudo on pi5test.\n'
fi

printf 'PASS: standalone DVSwitch TXT updater repair tests\n'

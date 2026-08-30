#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/transaction.sh
. "$REPO_ROOT/lib/transaction.sh"

fail() {
    printf 'TEST FAILURE: %s\n' "$1" >&2
    exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TARGET_DIR="$TEST_ROOT/targets"
BACKUP_ROOT="$TEST_ROOT/backups"
mkdir -p "$TARGET_DIR"
printf 'original content\n' > "$TARGET_DIR/functions.test"
chmod 0640 "$TARGET_DIR/functions.test"
printf 'replacement content\n' > "$TEST_ROOT/candidate.test"

dvsm_transaction_begin "$BACKUP_ROOT"
[[ $(stat -c '%a' "$BACKUP_ROOT") == 700 ]] || fail "backup root is not mode 700"
[[ $(stat -c '%a' "$DVSM_TRANSACTION_DIR") == 700 ]] || fail "backup set is not mode 700"

dvsm_backup_file "$TARGET_DIR/functions.test"
dvsm_record_absent_file "$TARGET_DIR/new-json.test"
[[ ${#DVSM_TRANSACTION_TARGETS[@]} -eq 2 ]] || fail "targets were not recorded"
[[ -f ${DVSM_TRANSACTION_BACKUPS[0]} ]] || fail "backup file is missing"
[[ $(stat -c '%a' "${DVSM_TRANSACTION_BACKUPS[0]}") == 640 ]] || fail "backup mode was not preserved"

dvsm_install_candidate "$TEST_ROOT/candidate.test" "$TARGET_DIR/functions.test"
dvsm_install_new_candidate "$TEST_ROOT/candidate.test" "$TARGET_DIR/new-json.test" "$(id -u)" "$(id -g)" 0644
grep -Fqx 'replacement content' "$TARGET_DIR/functions.test" || fail "candidate was not installed"
[[ $(stat -c '%a' "$TARGET_DIR/functions.test") == 640 ]] || fail "target mode changed during installation"
[[ -f "$TARGET_DIR/new-json.test" ]] || fail "new candidate was not installed"

dvsm_transaction_rollback
grep -Fqx 'original content' "$TARGET_DIR/functions.test" || fail "rollback did not restore content"
[[ $(stat -c '%a' "$TARGET_DIR/functions.test") == 640 ]] || fail "rollback did not restore mode"
[[ ! -e "$TARGET_DIR/new-json.test" ]] || fail "rollback did not remove newly created file"

printf 'changed again\n' > "$TARGET_DIR/functions.test"
printf 'unexpected\n' > "$TARGET_DIR/new-json.test"
dvsm_restore_backup_set "$DVSM_TRANSACTION_DIR"
grep -Fqx 'original content' "$TARGET_DIR/functions.test" || fail "named restore did not restore content"
[[ ! -e "$TARGET_DIR/new-json.test" ]] || fail "named restore did not remove newly created file"

ln -s "$TARGET_DIR/functions.test" "$TARGET_DIR/link.test"
if dvsm_require_regular_target "$TARGET_DIR/link.test" >/dev/null 2>&1; then
    fail "symbolic-link target was accepted"
fi

if dvsm_backup_file "$TARGET_DIR/functions.test" >/dev/null 2>&1; then
    fail "duplicate backup was accepted"
fi

printf 'Transaction tests passed.\n'

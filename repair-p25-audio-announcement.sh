#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repair P25Gateway remote-command voice announcements using the locally
# installed upstream source tree. No upstream source or binary is distributed.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.2.2-test"
readonly TARGET="/opt/P25Gateway/P25Gateway"
readonly SOURCE_URL="https://github.com/g4klx/P25Clients.git"
readonly SOURCE_COMMIT="99b3c15b33a4d16b632cb2393695a74c76c66da7"
readonly SERVICE="p25gateway.service"
readonly DASHBOARD="https://127.0.0.1/dvswitch/"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/p25-audio-announcement"
readonly STOCK_BINARY_HASH="51b1b2ed197d6be35c425a87e35b84fcbf765a4151739b2afd1523bb29334e7b"
readonly STOCK_GATEWAY_CPP_HASH="1902b5f09dfe6ef3969ca1a21486d36762e3ff7e9f3a56af6aca3166a7c75785"
readonly STOCK_VOICE_CPP_HASH="e0f2e1abca81461a45d56b1cc22f189929fe1c3b9219055259da910006de68c0"
readonly STOCK_VERSION_H_HASH="ca51c1fb4b789f68f0f629b1f4ed8be9bd6615e4859761e4202a5411ce9536b8"
readonly STOCK_MAKEFILE_HASH="b803cac0f066a5bb815389c74fd79de54cf4ac58ae7ecf866cfa8aee8b04e6f5"
readonly PATCHED_VERSION="P25Gateway version 20201105-p25voice2"

WORK_DIR=""
BACKUP_DIR=""
INSTALL_ACTIVE=0

die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
usage() { printf 'P25 audio-announcement repair %s\nUsage: sudo %s {--check|--install|--restore BACKUP_NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
hash_of() { sha256sum "$1" | awk '{print $1}'; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }

rollback() {
    [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/P25Gateway" ]] || return 1
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .p25-audio-rollback.XXXXXX)
    cp -a -- "$BACKUP_DIR/P25Gateway" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    systemctl try-restart "$SERVICE" >/dev/null 2>&1 || true
}

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'FAIL: error near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 ]]; then
        rollback && printf 'PASS: automatic rollback restored the original P25Gateway.\n' >&2 || printf 'FAIL: automatic rollback failed; use the protected backup.\n' >&2
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }

current_version() { "$TARGET" -v 2>&1 | head -n 1; }

version_is_patched() {
    [[ "$1" == "$PATCHED_VERSION" || "$1" == "$PATCHED_VERSION git #"* ]]
}

check_source_hashes() {
    local directory=$1
    [[ $(hash_of "$directory/P25Gateway.cpp") == "$STOCK_GATEWAY_CPP_HASH" ]] || die "Unsupported P25Gateway.cpp."
    [[ $(hash_of "$directory/Voice.cpp") == "$STOCK_VOICE_CPP_HASH" ]] || die "Unsupported Voice.cpp."
    [[ $(hash_of "$directory/Version.h") == "$STOCK_VERSION_H_HASH" ]] || die "Unsupported Version.h."
    [[ $(hash_of "$directory/Makefile") == "$STOCK_MAKEFILE_HASH" ]] || die "Unsupported Makefile."
}

preflight() {
    require_root
    for command in awk bash chmod chown cmp cp curl date file git grep install make mktemp mv python3 readelf rm sha256sum stat strings systemctl; do require_command "$command"; done
    [[ $(dpkg --print-architecture) == arm64 ]] || die "Only Debian arm64 is supported."
    [[ $(uname -m) == aarch64 ]] || die "Only an AArch64 kernel is supported."
    require_regular "$TARGET"
    systemctl cat "$SERVICE" >/dev/null
}

state() {
    local binary_hash version
    binary_hash=$(hash_of "$TARGET")
    version=$(current_version)
    if version_is_patched "$version"; then
        printf 'PATCHED\n'
    elif [[ "$binary_hash" == "$STOCK_BINARY_HASH" && "$version" == "P25Gateway version 20201105" ]]; then
        printf 'STOCK\n'
    else
        printf 'UNSUPPORTED\n'
    fi
}

patch_sources() {
    P25_BUILD_DIR="$WORK_DIR/build" python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["P25_BUILD_DIR"])
gateway = root / "P25Gateway.cpp"
voice = root / "Voice.cpp"
version = root / "Version.h"

g = gateway.read_text()
old_g = """\t\t\t\t\t\tif (voice != NULL) {\n\t\t\t\t\t\t\tif (currentAddrLen == 0U)\n\t\t\t\t\t\t\t\tvoice->unlinked();\n\t\t\t\t\t\t\telse\n\t\t\t\t\t\t\t\tvoice->linkedTo(currentTG);\n\t\t\t\t\t\t}\n"""
new_g = """\t\t\t\t\t\tif (voice != NULL) {\n\t\t\t\t\t\t\tif (currentAddrLen == 0U)\n\t\t\t\t\t\t\t\tvoice->unlinked();\n\t\t\t\t\t\t\telse\n\t\t\t\t\t\t\t\tvoice->linkedTo(currentTG);\n\t\t\t\t\t\t\tvoice->eof();\n\t\t\t\t\t\t}\n"""
if g.count(old_g) != 1:
    raise SystemExit("remote-command voice block is unsupported or ambiguous")
gateway.write_text(g.replace(old_g, new_g, 1))

v = voice.read_text()
replacements = (
    ("const unsigned int SILENCE_LENGTH = 4U;", "const unsigned int LEADING_SILENCE_LENGTH = 40U;\nconst unsigned int TRAILING_SILENCE_LENGTH = 4U;"),
    ("m_voiceLength += SILENCE_LENGTH * IMBE_LENGTH;\n\tm_voiceLength += SILENCE_LENGTH * IMBE_LENGTH;", "m_voiceLength += LEADING_SILENCE_LENGTH * IMBE_LENGTH;\n\tm_voiceLength += TRAILING_SILENCE_LENGTH * IMBE_LENGTH;"),
    ("unsigned int pos = SILENCE_LENGTH * IMBE_LENGTH;", "unsigned int pos = LEADING_SILENCE_LENGTH * IMBE_LENGTH;"),
)
for old, new in replacements:
    if v.count(old) != 1:
        raise SystemExit("voice silence pattern is unsupported or ambiguous")
    v = v.replace(old, new, 1)
voice.write_text(v)

vh = version.read_text()
old_version = 'const char* VERSION = "20201105";'
if vh.count(old_version) != 1:
    raise SystemExit("Version.h is unsupported")
version.write_text(vh.replace(old_version, 'const char* VERSION = "20201105-p25voice2";', 1))
PY
}

prepare_candidate() {
    local candidate_version
    WORK_DIR=$(mktemp -d /tmp/dvswitch-p25-audio.XXXXXX)
    git clone --quiet --no-checkout "$SOURCE_URL" "$WORK_DIR/source"
    git -C "$WORK_DIR/source" checkout --quiet --detach "$SOURCE_COMMIT"
    [[ $(git -C "$WORK_DIR/source" rev-parse HEAD) == "$SOURCE_COMMIT" ]] || die "Pinned source commit validation failed."
    mv -- "$WORK_DIR/source/P25Gateway" "$WORK_DIR/build"
    check_source_hashes "$WORK_DIR/build"
    patch_sources
    make -C "$WORK_DIR/build" clean >/dev/null
    make -C "$WORK_DIR/build" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" >/dev/null
    require_regular "$WORK_DIR/build/P25Gateway"
    file -b "$WORK_DIR/build/P25Gateway" | grep -q 'ELF 64-bit.*ARM aarch64' || die "Built candidate is not an AArch64 ELF executable."
    candidate_version=$(strings "$WORK_DIR/build/P25Gateway" | grep -Fx '20201105-p25voice2' | head -n 1)
    [[ "$candidate_version" == '20201105-p25voice2' ]] || die "Built candidate version marker is incorrect."
    printf 'Candidate version marker: %s\n' "$candidate_version"
    grep -qF 'voice->eof();' "$WORK_DIR/build/P25Gateway.cpp" || die "Immediate-announcement source validation failed."
    grep -qF 'LEADING_SILENCE_LENGTH = 40U' "$WORK_DIR/build/Voice.cpp" || die "800 ms lead-in source validation failed."
}

health_check() {
    systemctl is-active --quiet "$SERVICE" || die "$SERVICE is not active."
    systemctl is-active --quiet mmdvm_bridge.service || die "mmdvm_bridge.service is not active."
    systemctl is-active --quiet analog_bridge.service || die "analog_bridge.service is not active."
    [[ $(curl -ksS -o /dev/null -w '%{http_code}' "$DASHBOARD") == 200 ]] || die "DVSwitch dashboard did not return HTTPS 200."
}

run_check() {
    preflight
    case $(state) in
        PATCHED) printf 'PASS: P25 audio-announcement repair is already installed. No files changed.\n' ;;
        STOCK) prepare_candidate; printf 'PASS: exact stock P25Gateway and pinned source are compatible. Candidate built successfully. No installed files changed.\n' ;;
        *) die "Installed P25Gateway is neither the supported stock binary nor this repair." ;;
    esac
}

run_install() {
    preflight
    if [[ $(state) == PATCHED ]]; then
        health_check
        printf 'PASS: P25 audio-announcement repair is already installed. No unnecessary backup created.\n'
        return
    fi
    [[ $(state) == STOCK ]] || die "Unsupported installed P25Gateway."
    prepare_candidate

    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    local timestamp counter=0
    timestamp=$(date +%Y%m%d-%H%M%S)
    BACKUP_DIR="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$BACKUP_DIR" ]]; do counter=$((counter + 1)); BACKUP_DIR="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$BACKUP_DIR"
    cp -a -- "$TARGET" "$BACKUP_DIR/P25Gateway"
    printf '%s  P25Gateway\n' "$(hash_of "$BACKUP_DIR/P25Gateway")" > "$BACKUP_DIR/SHA256SUMS"
    chmod 0600 "$BACKUP_DIR/SHA256SUMS"

    INSTALL_ACTIVE=1
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .p25-audio-install.XXXXXX)
    cp -- "$WORK_DIR/build/P25Gateway" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    systemctl stop "$SERVICE"
    mv -fT -- "$temporary" "$TARGET"
    version_is_patched "$(current_version)" || die "Installed version validation failed: $(current_version)"
    systemctl start "$SERVICE"
    sleep 2
    health_check
    INSTALL_ACTIVE=0
    printf 'PASS: P25 immediate announcement and 800 ms lead-in repair installed atomically.\nBackup: %s\nInstalled SHA-256: %s\n' "$BACKUP_DIR" "$(hash_of "$TARGET")"
}

run_restore() {
    local name=$1 directory temporary
    preflight
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Backup not found: $name"
    require_regular "$directory/P25Gateway"
    (cd "$directory" && sha256sum -c SHA256SUMS >/dev/null) || die "Backup checksum validation failed."
    systemctl stop "$SERVICE"
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .p25-audio-restore.XXXXXX)
    cp -a -- "$directory/P25Gateway" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    systemctl start "$SERVICE"
    sleep 2
    health_check
    printf 'PASS: P25Gateway restored from %s.\nRestored SHA-256: %s\n' "$name" "$(hash_of "$TARGET")"
}

main() {
    case "${1:-}" in
        --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check ;;
        --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install ;;
        --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2" ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}

main "$@"

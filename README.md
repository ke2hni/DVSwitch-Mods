# DVSwitch-Mods

Tested repairs and optional modifications for current DVSwitch installations.

This repository patches files already installed on a DVSwitch system. It does not distribute upstream DVSwitch executables, PHP files, packages, or firmware.

## Supported test systems

The current scripts were validated on fresh default ASL3/DVSwitch installations:

- Raspberry Pi 4, Debian 12 Bookworm, ARM64
- Raspberry Pi 5, Debian 13 Trixie, ARM64

Exact compatibility checks in each script prevent unsupported installed files from being changed.

## Repairs

Repairs correct confirmed defects in the installed DVSwitch software.

| Script | Purpose | Status |
| --- | --- | --- |
| `repair-mmdvm-spacing.sh` | Corrects malformed P25 and five-digit YSF remote-command spacing in `MMDVM_Bridge` | Completed and tested |
| `repair-dvswitch-txt-updater.sh` | Repairs and validates DVSwitch TXT database downloads with atomic replacement | Completed and tested |
| `repair-p25-dashboard.sh` | Recognizes P25Gateway `Switched to reflector` and `Statically linked to reflector` link-status messages | Completed and tested |
| `repair-ysf-dashboard-null.sh` | Corrects case-sensitive YSF room matching and prevents a literal null fallback | Completed and tested |

## Optional modifications

Modifications add optional behavior and are separate from repairs.

| Script | Purpose | Status |
| --- | --- | --- |
| `mod-p25-nxdn-json.sh` | Adds validated P25 and NXDN JSON database downloads | Completed and tested |
| `mod-p25-nxdn-friendly-names.sh` | Displays P25 and NXDN reflector names with sponsor and numeric fallbacks | Completed and tested |
| `mod-dstar-tx-ref.sh` | Adds D-Star Tx TG/Ref and reflector/module display | Completed and tested |
| `mod-dmr-friendly-names.sh` | Displays BrandMeister, TGIF, and STFU talkgroup names and retains DMR state | Completed and tested |

## Script operation

Run scripts from the repository directory. Use `--check` before installation.

```bash
sudo ./SCRIPT_NAME.sh --check
sudo ./SCRIPT_NAME.sh --install
sudo ./SCRIPT_NAME.sh --restore BACKUP_NAME
```

Each script performs compatibility checks, creates protected timestamped backups outside live directories, replaces files atomically, validates its results, preserves installed metadata and user-selected values, rolls back automatically on failure, supports named restoration, and avoids unnecessary backups when already installed.

Backups are stored below:

```text
/var/backups/dvswitch-mods/
```

Use the exact backup name printed by a successful installation, such as `install-YYYYMMDD-HHMMSS`.

## Recommended order

Apply only the scripts you need. Where all current repairs and modifications are wanted, use this order:

1. `repair-mmdvm-spacing.sh`
2. `repair-dvswitch-txt-updater.sh`
3. `repair-p25-dashboard.sh`
4. `mod-p25-nxdn-json.sh`
5. `mod-p25-nxdn-friendly-names.sh`
6. `mod-dstar-tx-ref.sh`
7. `mod-dmr-friendly-names.sh`
8. `repair-ysf-dashboard-null.sh`

The order matters because later dashboard scripts recognize the hashes produced by earlier completed scripts.

## Repository contents

The repository contains only the completed repair and modification scripts, their currently required shared implementation files, licensing information, and basic Git configuration files.

The paused INI compatibility project and obsolete development tests and notes are intentionally excluded.

## Safety and scope

- Test on a non-production system first.
- Do not bypass a compatibility failure.
- Do not copy patched binaries or complete upstream files between systems.
- Use `--restore` with the named backup if a change must be reversed.
- These scripts are not affiliated with or endorsed by the upstream DVSwitch project.

## License

Repository-authored code is licensed under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

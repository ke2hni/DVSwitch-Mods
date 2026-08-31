# DVSwitch-Mods

Tested repairs and optional modifications for current DVSwitch installations.

This repository patches files already installed on a DVSwitch system. It does not distribute upstream DVSwitch executables, PHP files, packages, or firmware.

## Supported systems

The scripts have been validated on fresh default ASL3/DVSwitch installations:

- Raspberry Pi 4, Debian 12 Bookworm, ARM64
- Raspberry Pi 5, Debian 13 Trixie, ARM64

Each script rejects unsupported operating systems, installed-file versions, or ambiguous file structures before installation. `repair-p25-audio-announcement.sh` additionally requires ARM64, Internet access during its pinned source build, and the exact supported stock P25Gateway binary.

## Repairs

Repairs correct confirmed defects in installed DVSwitch software.

| Script | Version | Purpose | Status |
| --- | ---: | --- | --- |
| `repair-mmdvm-spacing.sh` | 1.0.0 | Corrects malformed P25 and five-digit YSF remote-command spacing in `MMDVM_Bridge` | Completed and tested |
| `repair-dvswitch-txt-updater.sh` | 1.0.0 | Repairs and validates DVSwitch TXT database downloads with atomic replacement | Completed and tested |
| `repair-p25-audio-announcement.sh` | 1.0.0 | Repairs immediate P25 remote voice announcements and adds an 800 ms silent lead-in | Completed and tested |
| `repair-p25-dashboard.sh` | 1.1.0 | Recognizes P25Gateway remote-command and static-startup link messages | Completed and tested |
| `repair-ysf-dashboard-null.sh` | 1.0.3 | Corrects case-sensitive YSF room matching and prevents a literal `null` fallback | Completed and tested |

## Optional modifications

Modifications add optional behavior and are separate from repairs.

| Script | Version | Purpose | Status |
| --- | ---: | --- | --- |
| `mod-p25-nxdn-json.sh` | 1.1.0 | Adds validated P25 and NXDN JSON database downloads | Completed and tested |
| `mod-p25-nxdn-friendly-names.sh` | 1.1.4 | Displays P25 and NXDN reflector names with sponsor and numeric fallbacks | Completed and tested |
| `mod-dstar-tx-ref.sh` | 1.0.4 | Adds D-Star Tx TG/Ref and reflector/module display | Completed and tested |
| `mod-dmr-friendly-names.sh` | 1.4.1 | Displays BrandMeister, TGIF, and STFU talkgroup names, removes saved foreign-mode pollution behind TGIF placeholder 9, blocks stale cross-mode talkgroups, wraps long names, and preserves DMR status across an empty UTC-day log | Completed and tested |

## Script operation

Run scripts from the repository directory and use `--check` before installation:

```bash
sudo ./SCRIPT_NAME.sh --check
sudo ./SCRIPT_NAME.sh --install
sudo ./SCRIPT_NAME.sh --restore BACKUP_NAME
```

Each script provides exact compatibility checks, protected timestamped backups outside live directories, atomic replacement, changed-file validation, automatic installation rollback, named restoration, idempotency, and no unnecessary backup when already installed. Installers preserve the existing owner, group, and permission mode of replaced files; protected backups retain the original files for exact restoration.

Backups are stored below:

```text
/var/backups/dvswitch-mods/
```

Use the exact backup name printed by a successful installation, such as `install-YYYYMMDD-HHMMSS`.

## Dependencies

| Script | Required prior state |
| --- | --- |
| `repair-mmdvm-spacing.sh` | Independent |
| `repair-dvswitch-txt-updater.sh` | Independent |
| `repair-p25-audio-announcement.sh` | Independent; ARM64 and Internet access required |
| `repair-p25-dashboard.sh` | Independent of the optional dashboard modifications |
| `mod-p25-nxdn-json.sh` | `repair-dvswitch-txt-updater.sh` |
| `mod-p25-nxdn-friendly-names.sh` | `repair-p25-dashboard.sh`, `mod-p25-nxdn-json.sh`, and valid P25/NXDN JSON files |
| `mod-dstar-tx-ref.sh` | `mod-p25-nxdn-friendly-names.sh` |
| `mod-dmr-friendly-names.sh` | `mod-dstar-tx-ref.sh` and valid BrandMeister/TGIF lists |
| `repair-ysf-dashboard-null.sh` | `mod-dmr-friendly-names.sh` and a valid YSF host list |

The dashboard scripts intentionally validate the completed state produced by their prerequisites. They are not interchangeable or safely reorderable. Their compatibility checks also recognize the fully completed dashboard chain, including the DMR v4 transition protection, v5 log-status repair, and v6 TGIF placeholder cleanup, so every script can be rechecked safely after all nine stages are installed.

## Complete installation order

When every repair and modification is wanted, use this order:

1. `repair-mmdvm-spacing.sh`
2. `repair-dvswitch-txt-updater.sh`
3. `repair-p25-audio-announcement.sh`
4. `repair-p25-dashboard.sh`
5. `mod-p25-nxdn-json.sh`
6. `mod-p25-nxdn-friendly-names.sh`
7. `mod-dstar-tx-ref.sh`
8. `mod-dmr-friendly-names.sh`
9. `repair-ysf-dashboard-null.sh`

The three independent repairs may be performed separately when their corresponding defects apply. Follow the dependency table before selecting anything from the dashboard or database chain.

## Repository contents

- Top-level executable repair and modification scripts are the public commands.
- `lib/` contains shared transaction and narrowly scoped patching logic.
- `LICENSE` covers repository-authored code.
- `THIRD_PARTY_NOTICES.md` describes upstream ownership and license boundaries.

The paused INI compatibility project and obsolete development files are intentionally excluded.

## Safety and scope

- Test on a non-production system first.
- Do not bypass a compatibility failure.
- Do not copy patched binaries or complete upstream files between systems.
- Use `--restore` with the named backup if a change must be reversed.
- These scripts are not affiliated with or endorsed by the upstream DVSwitch project.

## License

Repository-authored code is licensed under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

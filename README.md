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
| `repair-ysf-dashboard-null.sh` | 1.0.4 | Corrects case-sensitive YSF room matching, prevents a literal `null` fallback, and recognizes the completed DMR v7 dashboard checksum | Completed and tested |

## Optional modifications

Modifications add optional behavior and are separate from repairs.

| Script | Version | Purpose | Status |
| --- | ---: | --- | --- |
| `mod-p25-nxdn-json.sh` | 1.1.0 | Adds validated P25 and NXDN JSON database downloads | Completed and tested |
| `mod-p25-nxdn-friendly-names.sh` | 1.1.5 | Displays P25 and NXDN reflector names with sponsor and numeric fallbacks; recognizes the completed DMR v7 dashboard checksum | Completed and tested |
| `mod-dstar-tx-ref.sh` | 1.0.5 | Adds D-Star Tx TG/Ref and reflector/module display; recognizes the completed DMR v7 dashboard checksum | Completed and tested |
| `mod-dmr-friendly-names.sh` | 1.5.0 | Displays dynamic `DMR BM Master` and `DMR TGIF Master` headings plus BrandMeister, TGIF, and STFU talkgroup names; retains the last DMR network outside DMR mode; removes saved foreign-mode pollution behind TGIF placeholder 9; blocks stale cross-mode talkgroups; wraps long names; and preserves DMR status across an empty UTC-day log | Completed and tested |
| `mod-dashboard-fcc-first-names.sh` | 1.2.1 | Adds FCC first names, resolves displayed seven-digit DMR IDs to callsigns, installs a self-contained weekly database updater, and validates the cleaned Target display | Testing |
| `mod-dashboard-targets.sh` | 1.1.4 | Replaces raw activity targets with row-specific friendly talkgroup, reflector, Group Call, General Call, and GPS/Data labels plus a compact legend | Testing |

## Script operation

Run scripts from the repository directory and use `--check` before installation:

```bash
sudo ./SCRIPT_NAME.sh --check
sudo ./SCRIPT_NAME.sh --install
sudo ./SCRIPT_NAME.sh --restore BACKUP_NAME
```

`mod-dashboard-fcc-first-names.sh` installs a self-contained systemd updater that remains available if the cloned repository is deleted. Each activation is randomized between Monday 00:00 and Friday 00:00 local time using a 96-hour delay window, and a missed update runs after startup. The timer never downloads unless the exact supported FCC Name dashboard modification, helper, database, ownership, and permissions are installed.

Gateway and Local Activity entries containing an exact seven-digit DMR ID are resolved through DVSwitch's maintained `/var/lib/mmdvm/DMRIds.dat`. A unique valid match replaces the displayed number with its callsign, after which the existing FCC lookup supplies the first name. Missing, malformed, or ambiguous mappings retain the original value and display `---` rather than guessing.

`mod-dashboard-targets.sh` formats every history row only from the destination captured for that reception. It never assigns the node's current room, reflector, network, or talkgroup to older rows. P25, NXDN, and unambiguous DMR destinations display as `Friendly Name (TG number)`; D-Star reflector routes display the reflector and module; YSF voice and data display as `Group Call` and `GPS/Data`; and D-Star `CQCQCQ` without a recorded reflector displays as `General Call`. Unknown or ambiguous targets retain their original value.

Manual updating remains available through either command:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --update
sudo /usr/local/sbin/dvswitch-fcc-first-names-update
```

Remove only the automatic updater while preserving the Name columns, helper, and working database with:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --remove-updater
sudo /usr/local/sbin/dvswitch-fcc-first-names-update --remove-updater
```

The removal creates a protected backup. A later `--install` safely reinstalls the updater without downloading or rebuilding an already valid database.

Completely remove the Name modification, database, and automatic updater by supplying the original installation backup printed when the modification was first installed:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --uninstall install-YYYYMMDD-HHMMSS
```

The uninstaller first verifies that the named backup contains supported original `lh.php` and `localtx.php` files. It then creates a new safety backup of the complete current installation before restoring the original dashboard and removing the FCC-specific installed files. An update-only or updater-only backup is rejected.

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
| `mod-dashboard-fcc-first-names.sh` | Independent of the nine-stage chain; Internet access is required for the initial database build and weekly/manual updates |
| `mod-dashboard-targets.sh` | `mod-dashboard-fcc-first-names.sh` v1.2.1; valid P25/NXDN JSON and BrandMeister/TGIF lists provide friendly names |

The dashboard scripts intentionally validate the completed state produced by their prerequisites. They are not interchangeable or safely reorderable. Their compatibility checks also recognize the fully completed dashboard chain, including the DMR v4 transition protection, v5 log-status repair, v6 TGIF placeholder cleanup, and v7 BM/TGIF network heading, so every script can be rechecked safely after all nine stages are installed.

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
10. `mod-dashboard-fcc-first-names.sh` (optional and independent after the dashboard baseline is established)
11. `mod-dashboard-targets.sh` (optional; install after the FCC activity-column modification)

The three independent repairs may be performed separately when their corresponding defects apply. Follow the dependency table before selecting anything from the dashboard or database chain.

## Repository contents

- Top-level executable repair and modification scripts are the public commands.
- `lib/` contains shared transaction and narrowly scoped patching logic.
- `systemd/` contains the FCC first-name weekly updater service and timer installed by `mod-dashboard-fcc-first-names.sh`.
- `LICENSE` covers repository-authored code.
- `THIRD_PARTY_NOTICES.md` describes upstream ownership and license boundaries.

The paused INI compatibility project and obsolete development files are intentionally excluded.

## Safety and scope

- Test on a non-production system first.
- Do not bypass a compatibility failure.
- Do not copy patched binaries or complete upstream files between systems.
- Use `--restore` with the named backup if a change must be reversed.
- These scripts are not affiliated with or endorsed by the upstream DVSwitch project.

## FCC first-name updater safety

The installed updater and its private support files are located at:

```text
/usr/local/sbin/dvswitch-fcc-first-names-update
/usr/local/lib/dvswitch-mods/build_fcc_first_names.py
/usr/local/lib/dvswitch-mods/patch_dashboard_first_names.py
/usr/local/lib/dvswitch-mods/transaction.sh
/etc/systemd/system/dvswitch-fcc-first-names-update.service
/etc/systemd/system/dvswitch-fcc-first-names-update.timer
```

Version 1.2.1 FCC component SHA256 values:

| Component | SHA256 |
| --- | --- |
| `mod-dashboard-fcc-first-names.sh` | `bd07ae57da57975cf8905766cdea940a5d4b6dad3feac923959ab83db9d5a4c3` |
| Installed updater | `ff2c45c1e0258a13ed1b819dae6cbc9a99e0be2b7d8d7fb73aa13faeaba426dd` |
| Installed builder | `d4831315dfdd133174a415fe288c6c3c8d49852336a0dcc196b4b0a2130e4ae2` |
| Installed dashboard patcher | `80ba8c7e998a596ef43a138ab678457b1a5afce61cb1a2396099fac735ef9a4d` |
| Installed transaction helper | `13d743d6065f88888725a1aefe98c8d4ad957974ec5cd991a52ff20ac44a6532` |
| systemd service | `78c0b1da92560f27aae8db1faa3630498055c3e48663f709f9217463c7eb0267` |
| systemd timer | `28e8ec01752c230132848f5891a504194b1dadd6035580b355ad49dee5d05cf3` |
| Dashboard lookup helper | `7481c7099b9f7c4f58691052b71535bbe602774e8c0c6f5856341af22c1d09d9` |

Version 1.1.4 Target-display component SHA256 values:

| Component | SHA256 |
| --- | --- |
| `mod-dashboard-targets.sh` | `55a42ac5e30cb4b5536f14e491f3c3a4820f56a028c9db13314292f32cf8225e` |
| Dashboard patcher | `35156d7121707f2053109e0d8ca1461a0fe9035e15ac52bf989293de6a842604` |
| Dashboard helper | `de7bafe302c5a992a7e63f5d68d12f12968614e23ce07fa4457e481be0843cbb` |

Every update downloads the FCC weekly Amateur Radio Service archive into a private workspace below `/var/lib/mmdvm`, never `/tmp` or `/var/tmp`. The complete archive is integrity-checked, its exact FCC file set and declared record counts are verified, and the replacement database is built and validated before the installed database is touched. The updater reports record count, byte size, and SHA256. An identical database creates no backup and is not replaced. A changed database receives a protected timestamped backup and atomic replacement. Download, ZIP, extraction, build, validation, checksum, ownership, permission, or installation failure returns a nonzero status and preserves the last known-good database. The archive and entire workspace are removed after success or failure.

Inspect the schedule and recent update log with:

```bash
systemctl list-timers dvswitch-fcc-first-names-update.timer
sudo journalctl -u dvswitch-fcc-first-names-update.service -n 100 --no-pager
```

## License

Repository-authored code is licensed under the MIT License. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

<img width="1600" height="900" alt="Screenshot 2026-09-02 195516" src="https://github.com/user-attachments/assets/1b9a319b-c6e2-49b7-a001-5e3519560408" />

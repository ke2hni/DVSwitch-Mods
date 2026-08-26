# DVSwitch TXT Database Updater Repair

## Classification

This is a **repair stage**, not a dashboard or database-format modification.
It repairs the existing TXT database update behavior in the locally installed
DVSwitch script while retaining the stock file paths and formats.

Stage 2 is developed, installed, tested, backed up, and restored independently
from every other DVSwitch-Mods stage.

## Installed target

The standalone installer transforms only this existing local file:

```text
/opt/MMDVM_Bridge/dvswitch.sh
```

The repository does not contain or redistribute the complete upstream script.
`lib/patch_dvswitch_txt_updater.py` applies independently written structural
changes to a temporary copy of the user's installed file.

## Problem repaired

The stock updater downloads directly over live database files and validates
them only afterward. A failed, empty, malformed, truncated, or unexpected
response can therefore destroy a last-known-good database.

The stock Pi-Star YSF validation also expects obsolete content, and the stock
Pi-Star TGIF database URL no longer supplies the required file.

## Repaired TXT databases

| Live file | Source | Validation |
| --- | --- | --- |
| `NXDNHosts.txt` | DVRef/RefCheck | Native routing records, realistic size/count, known reflector |
| `P25Hosts.txt` | DVRef/RefCheck | Native routing records and realistic size/count |
| `YSFHosts.txt` | DVRef/RefCheck | Native semicolon-delimited reflector records and realistic size/count |
| `TGList_TGIF.txt` | Official TGIF CSV API | Converted to the existing four-field DVSwitch format; count and known-TG checks |
| `TGList_BM.txt` | Official BrandMeister v2 API | Converted to the existing four-field DVSwitch format; count and known-TG checks |
| `DCS_Hosts.txt` | Pi-Star | Native DCS records and realistic size/count |
| `DPlus_Hosts.txt` | Pi-Star | Native REF records and realistic size/count |
| `DExtra_Hosts.txt` | Pi-Star | Native XRF records and realistic size/count |
| `XLXHosts.txt` | DVRef/RefCheck | Native semicolon-delimited XLX records and realistic size/count |

The existing generic Pi-Star updater remains available for `FCSRooms.txt` and
`APRS_Hosts.txt`, but it is routed through the same safe temporary-download and
validation path. Their sources and file formats are not changed.

RefCheck requests use this required user agent:

```text
DVSwitch
```

## Transaction and file safety

The repaired runtime updater:

- creates temporary files in `/var/lib/mmdvm` with `mktemp`;
- downloads only to temporary files;
- rejects HTTP failures, empty responses, HTML/error pages, malformed data,
  implausibly small datasets, and missing sanity-check records;
- converts API data only into separate temporary candidates;
- preserves the last-known-good live file after any failure;
- preserves the owner and mode of an existing live database;
- creates a previously missing database as `root:root` mode `0644`; and
- atomically renames a validated candidate over the live file.

The standalone installer:

- requires a regular, non-symlink installed target;
- patches and validates a temporary copy;
- preserves target ownership and mode;
- installs the candidate atomically;
- creates a timestamped root-protected backup;
- automatically rolls back after an installation failure;
- supports explicit restore; and
- is idempotent and creates no unnecessary backup when already repaired.

Backups are stored under:

```text
/var/backups/dvswitch-mods/txt-updater
```

## Explicit exclusions

This stage does not:

- patch the `MMDVM_Bridge` executable;
- modify dashboard PHP;
- repair the P25 dashboard log parser;
- repair the PHP 8 `ceil()` issue;
- download `P25Hosts.json` or `NXDNHosts.json`;
- add friendly reflector names;
- change P25 or NXDN TXT routing formats;
- update user-ID, subscriber-ID, NXDN subscriber, or DMR master databases;
- install DVS Mode Switcher; or
- run the combined DVSwitch-Mods installer.

## Standalone files

```text
repair-dvswitch-txt-updater.sh
lib/patch_dvswitch_txt_updater.py
tests/test-dvswitch-txt-updater-patcher.py
tests/test-repair-dvswitch-txt-updater.sh
```

## Validation order

Run each command separately and stop after any failure:

```bash
python3 tests/test-dvswitch-txt-updater-patcher.py
```

```bash
sudo tests/test-repair-dvswitch-txt-updater.sh
```

```bash
sudo ./repair-dvswitch-txt-updater.sh --check
```

```bash
sudo ./repair-dvswitch-txt-updater.sh --dry-run
```

Installation is performed only after all preceding tests pass:

```bash
sudo ./repair-dvswitch-txt-updater.sh --install
```

The repaired live updater is then exercised separately:

```bash
sudo /opt/MMDVM_Bridge/dvswitch.sh update
```

Backup, metadata, valid downloads, failed downloads, malformed downloads,
last-known-good preservation, atomic replacement, idempotent reinstall,
explicit restore, and automatic rollback must all be verified before Stage 2
is approved.

## Restore

List available Stage 2 backup names:

```bash
sudo find /var/backups/dvswitch-mods/txt-updater -mindepth 1 -maxdepth 1 -type d -name 'install-*' -printf '%f\n' | sort
```

Restore one exact backup name:

```bash
sudo ./repair-dvswitch-txt-updater.sh --restore install-YYYYMMDD-HHMMSS
```

## Licensing scope

The installer, structural patcher, tests, and this documentation are
independently written and MIT licensed. DVSwitch and its installed files remain
the property of their respective copyright holders and remain subject to their
upstream licensing terms. See `THIRD_PARTY_NOTICES.md`.

This repository's approach is practical compliance work and is not a guarantee
against legal claims.

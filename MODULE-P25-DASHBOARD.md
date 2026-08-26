# Stage 3: P25 Dashboard Compatibility Repair

Status: standalone development candidate; Raspberry Pi 4 and Raspberry Pi 5 validation pending.

## Scope

This repair changes only the locally installed
`/usr/share/dvswitch/include/functions.php` file. It makes the stock DVSwitch
Dashboard recognize the P25Gateway remote-command message:

```text
Switched to reflector <number> by remote command
```

The repair adds `Switched` to both P25Gateway log filters and returns the same
`Linked to ... TG <number>` representation already used by the stock P25
dashboard parser.

## Exclusions

This stage does not modify `status.php`, NXDN behavior, the PHP 8 duration
handling, friendly names, JSON databases, TXT databases, gateway binaries, or
the Stage 1 and Stage 2 repairs.

## Safety

The installer requires Debian 12 or 13, a regular non-symlink target, valid PHP
syntax, exactly two supported P25 log-filter anchors, and exactly one supported
P25 parser anchor. Missing, duplicate, mixed, partially repaired, or ambiguous
states fail without changing the installed file.

Installation patches a temporary copy, validates it, creates a timestamped
mode-0700 protected backup, atomically replaces the installed file while
preserving ownership and mode, and automatically rolls back on an installation
or validation failure. Reinstallation is idempotent and does not create an
unnecessary backup.

## Commands

```bash
sudo ./repair-p25-dashboard.sh --check
sudo ./repair-p25-dashboard.sh --dry-run
sudo ./repair-p25-dashboard.sh --install
sudo ./repair-p25-dashboard.sh --restore BACKUP-NAME
```

Backups are stored below:

```text
/var/backups/dvswitch-mods/p25-dashboard
```

## Licensing

The installer, patcher, tests, and documentation are independently written and
MIT licensed. No complete upstream DVSwitch Dashboard file is included.

# Changelog

## Unreleased

### Stage 2 — standalone DVSwitch TXT updater repair

- Add `repair-dvswitch-txt-updater.sh` as a standalone installer for the
  locally installed `/opt/MMDVM_Bridge/dvswitch.sh`.
- Add `lib/patch_dvswitch_txt_updater.py` with strict structural-anchor and
  mixed-state rejection.
- Download TXT databases into same-directory `mktemp` files and replace live
  files only after validation.
- Preserve last-known-good databases after HTTP, empty, HTML, malformed,
  truncated, conversion, or validation failures.
- Preserve existing database ownership and mode; create missing databases as
  `root:root` mode `0644`.
- Repair YSF, TGIF, P25, NXDN, BrandMeister, DCS, DPlus, DExtra, and XLX update
  behavior while retaining existing TXT paths and formats.
- Route the existing FCS and APRS calls through the safe generic updater without
  changing their sources or formats.
- Add isolated patcher and installer tests covering syntax, idempotency,
  missing/duplicate/mixed anchors, stage isolation, metadata operations, and a
  read-only live check.
- Add `MODULE-DVSWITCH-TXT-UPDATER.md` with scope, safety, validation, restore,
  and licensing details.
- Keep JSON databases, dashboard parsing, PHP compatibility, and friendly-name
  behavior outside Stage 2.

### Development workflow

- Separate repairs from modifications and require every stage to pass
  independently before rebuilding or running the combined installer.
- Mark the old `0.3.0-rc2` combined installer as development history that must
  not be run during standalone-stage validation.

## 0.3.0-rc2 - 2026-08-25

- Include `Switched` in both current-day and previous-day P25Gateway dashboard log filters.
- Preserve the NXDN log filters unchanged.
- Add regression coverage proving remote-command events reach the P25 parser.

## 0.3.0-rc1 - 2026-08-25

- Add strict fixed-length local MMDVM_Bridge transformations for P25 `TalkGroup %d` and five-digit YSF `Link... %05d` commands.
- Reject unsupported, missing, or ambiguous binary patterns and preserve binary size.
- Add P25 dashboard parsing for `Switched to reflector <number>` remote-command log entries.
- Enforce MMDVM compatibility installation before dashboard and JSON modules.
- Include the MMDVM binary in the same protected transaction and automatic rollback.
- Restart `mmdvm_bridge.service` after successful installation or restore.
- Add binary-patcher, dependency-order, idempotency, and malformed-input regression tests.

## 0.2.0-rc2 - 2026-08-24

- Use RefCheck's accepted `DVSwitch` HTTP user-agent for installer JSON downloads.
- Add a regression test preventing reintroduction of an unsupported user-agent.

## 0.2.0-rc1 - 2026-08-24

- Added friendly P25 and NXDN reflector names with `name`, `sponsor`, and numeric fallback order.
- Added validated P25/NXDN RefCheck JSON downloads and persistent updater integration.
- Added read-only preflight and dry-run modes.
- Added protected timestamped backups, atomic installation, automatic rollback, and named restore.
- Added idempotency, malformed-input, symlink, metadata-preservation, and repository-compliance tests.
- Added safeguards preventing complete upstream files and compiled binaries from entering the repository.

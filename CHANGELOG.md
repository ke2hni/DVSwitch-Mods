# Changelog

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

# DVSwitch Mods

Unofficial, independently developed repair and modification tools for an
existing DVSwitch installation.

## Project status

This project is under staged development and is not ready for production use.

The old `0.3.0-rc2` combined installer remains development history. Do not run
`install-dvswitch-mods.sh` until every standalone repair and modification stage
has passed and the combined installer has been rebuilt and retested.

## Important notice

This project is not affiliated with, endorsed by, or maintained by the
DVSwitch project or its contributors.

This repository does not distribute DVSwitch executables, complete upstream
source files, patched binaries, DEBs, or package contents. Its independently
written tools create temporary candidates from files already installed on the
user's system and apply narrow local transformations.

DVSwitch and its original components remain the property of their respective
copyright holders and are governed by their respective licenses and
permissions. See `THIRD_PARTY_NOTICES.md`.

## License

The independently written installers, patchers, validation logic,
documentation, tests, and original support code are licensed under the MIT
License. This license does not grant rights to DVSwitch software or other
third-party components.

This is practical compliance work and is not a guarantee against legal claims.

## Staged development model

Repairs restore intended stock behavior. Modifications add new data or display
behavior. Each stage must have its own installer or patcher, tests,
documentation, protected backup, rollback, restore, idempotency, and validation
before it can enter the combined installer.

| Stage | Classification | Status |
| --- | --- | --- |
| 1. MMDVM command spacing | Repair | Standalone Raspberry Pi 4 and Pi 5 validation passed |
| 2. Stock TXT updater | Repair | Standalone development and validation in progress |
| 3. P25 dashboard compatibility | Repair | Pending |
| 4. PHP 8 dashboard guard | Repair | Pending |
| 5. P25/NXDN JSON databases | Modification | Pending separation and validation |
| 6. Friendly P25/NXDN names | Modification | Pending separation and validation |
| 7. Combined installer | Integration | Blocked until every standalone stage passes |

## Stage 1: MMDVM command-spacing repair

Stage 1 locally repairs two fixed-length command strings in the installed
`MMDVM_Bridge` executable:

- P25 `TalkGroup%d` becomes `TalkGroup %d`.
- Five-digit YSF `Link%c%c%c%05d` becomes `Link%c%c%c %05d`.

The standalone files are:

```text
repair-mmdvm-spacing.sh
lib/patch_mmdvm_binary.py
tests/test-repair-mmdvm-spacing.sh
tests/test-mmdvm-binary-patcher.py
MODULE-MMDVM-COMPATIBILITY.md
```

## Stage 2: TXT database updater repair

Stage 2 locally repairs `/opt/MMDVM_Bridge/dvswitch.sh` so existing TXT
talkgroup and reflector databases are downloaded to temporary files, validated,
and atomically installed without destroying last-known-good data.

It repairs YSF, TGIF, P25, NXDN, BrandMeister, and D-Star update behavior while
retaining the existing TXT paths and formats. It does not add JSON databases or
change the dashboard.

The standalone files are:

```text
repair-dvswitch-txt-updater.sh
lib/patch_dvswitch_txt_updater.py
tests/test-dvswitch-txt-updater-patcher.py
tests/test-repair-dvswitch-txt-updater.sh
MODULE-DVSWITCH-TXT-UPDATER.md
```

See `MODULE-DVSWITCH-TXT-UPDATER.md` for sources, safety behavior, exclusions,
validation order, and restore instructions.

## Development safety rules

- Test standalone stages only on designated non-production nodes.
- Apply and validate one layer at a time.
- Do not combine repairs and modifications during development.
- Do not run the combined installer until every standalone stage passes.
- Review the reported protected backup before proceeding to the next stage.
- Never commit credentials, private configuration, complete upstream files, or
  compiled third-party binaries.

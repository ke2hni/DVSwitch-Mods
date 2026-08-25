# DVSwitch Mods

Unofficial, independently developed installer for applying local compatibility and dashboard modifications to an existing DVSwitch installation.

## Project status

This project is under development and is not ready for production use.

## Important notice

This project is not affiliated with, endorsed by, or maintained by the DVSwitch project or its contributors.

This repository does not distribute DVSwitch executables or complete upstream DVSwitch source files. It applies narrowly scoped modifications to files already installed on the user’s system.

DVSwitch and its original components remain the property of their respective copyright holders and are governed by their respective licenses and permissions.

## License

The independently written installer, validation logic, documentation, and original patching code in this repository are licensed under the MIT License. This license does not grant rights to DVSwitch software or other third-party components.

## P25/NXDN release candidate

Version `0.2.0-rc2` adds friendly P25 and NXDN reflector labels using separately downloaded RefCheck JSON databases. Lookup order is `name`, `sponsor`, then `TG <number>`.

The repository does not contain complete DVSwitch files. The installer creates temporary candidates from files already installed on the local system and applies narrowly scoped transformations.

### Safety workflow

Run only on a non-production test node during release-candidate testing:

```bash
sudo ./install-dvswitch-mods.sh --check
```

```bash
sudo ./install-dvswitch-mods.sh --dry-run
```

After reviewing the dry-run output:

```bash
sudo ./install-dvswitch-mods.sh --install
```

The installer reports the protected backup name. Restore it with:

```bash
sudo ./install-dvswitch-mods.sh --restore install-YYYYMMDD-HHMMSS
```

Backups are stored under `/var/backups/dvswitch-mods` with mode `0700`. Existing ownership and permissions are preserved. Candidate and live syntax, JSON structure, and known reflector data are validated. An installation failure triggers automatic rollback.

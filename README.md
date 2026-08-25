# DVSwitch Mods

Unofficial, independently developed installer for applying local compatibility and dashboard modifications to an existing DVSwitch installation.

## Project status

This project is under development and is not ready for production use.

## Important notice

This project is not affiliated with, endorsed by, or maintained by the DVSwitch project or its contributors.

This repository does not distribute DVSwitch executables or complete upstream DVSwitch source files. It creates temporary candidates from software already installed on the user's system and applies narrowly scoped, fixed-length transformations and text modifications.

DVSwitch and its original components remain the property of their respective copyright holders and are governed by their respective licenses and permissions.

## License

The independently written installer, validation logic, documentation, tests, and original patching code are licensed under the MIT License. This license does not grant rights to DVSwitch software or other third-party components.

## Release candidate 0.3.0-rc1

The installer applies and validates modules in dependency order:

1. Local MMDVM_Bridge P25 remote-command spacing compatibility.
2. Local MMDVM_Bridge five-digit YSF link-command spacing compatibility.
3. P25 dashboard parsing for `Switched to reflector <number>`.
4. Friendly P25/NXDN reflector labels using RefCheck JSON data.
5. Persistent validated P25/NXDN JSON updater integration.

Friendly-name lookup order is `name`, `sponsor`, then `TG <number>`.

## Safety workflow

Use a non-production test node during release-candidate testing:

```bash
sudo ./install-dvswitch-mods.sh --check
sudo ./install-dvswitch-mods.sh --dry-run
sudo ./install-dvswitch-mods.sh --install
```

Restore the protected backup reported by the installer with:

```bash
sudo ./install-dvswitch-mods.sh --restore install-YYYYMMDD-HHMMSS
```

Backups are stored under `/var/backups/dvswitch-mods` with mode `0700`. Existing ownership and permissions are preserved. The MMDVM binary is transformed first, but all targets participate in one transaction; any later failure restores every original target.

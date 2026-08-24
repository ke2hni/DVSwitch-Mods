# File placement

Copy the contents of this bundle into the top level of the `DVSwitch-Mods` repository while preserving the included directories.

```text
DVSwitch-Mods/
├── .github/
│   └── workflows/
│       └── compliance.yml
├── tests/
│   ├── check-repository-compliance.sh
│   ├── test-installer.sh
│   └── test-p25-nxdn-patcher.py
├── lib/
│   └── patch_p25_nxdn.py
├── .gitignore
├── CONTRIBUTING.md
├── MODULE-P25-NXDN.md
├── THIRD_PARTY_NOTICES.md
└── install-dvswitch-mods.sh
```

Keep the repository's existing `README.md`, `LICENSE`, and `.gitattributes` files.

The installer is currently a read-only preflight framework. It does not install or modify anything yet.

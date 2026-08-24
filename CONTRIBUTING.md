# Contributing

Contributions are welcome when they comply with the repository's licensing and redistribution rules.

## Permitted contributions

- Independently written installer logic
- Validation and rollback logic
- Tests
- Documentation
- Narrowly scoped transformations applied to software already installed on a user's system
- Original code licensed under the repository's MIT License

## Prohibited contributions

Do not submit:

- DVSwitch executables or other compiled third-party binaries
- Complete or substantially complete DVSwitch source files
- Complete stock DVSwitch configuration files
- Files copied from an installed DVSwitch system
- Third-party artwork or documentation without confirmed redistribution permission
- Credentials, passwords, callsigns, radio IDs, hostnames, or other personal configuration
- Code with an incompatible or unidentified license

## Patch requirements

A modification must:

1. Operate only on files already installed on the user's system.
2. Verify that the target file and expected structure are supported.
3. Create a timestamped backup before modification.
4. Preserve ownership, permissions, and existing copyright or license notices.
5. Validate the result.
6. Automatically restore the original file if installation or validation fails.
7. Be tested on a non-production system before release.

## Licensing

By contributing original material, contributors agree to license that material under the repository's MIT License.

Third-party material remains governed by its original license and must not be added unless redistribution permission has been confirmed and documented.

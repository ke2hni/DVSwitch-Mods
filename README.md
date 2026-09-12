<div align="center">

# 🛠️ DVSwitch-Mods

### Tested repairs and optional dashboard improvements for DVSwitch

![Platform](https://img.shields.io/badge/platform-DVSwitch-24527a)
![Debian](https://img.shields.io/badge/tested-Debian%2012%20%7C%2013-a80030)
![Architectures](https://img.shields.io/badge/MMDVM-ARM64%20%7C%20AMD64%20%7C%20i386-blue)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

> [!IMPORTANT]
> These scripts repair or modify files already installed by DVSwitch. They do
> not distribute DVSwitch executables, packages, PHP files, or firmware.

**[Quick start](#-quick-start--install-everything) · [Repairs](#-repairs) ·
[Modifications](#-optional-modifications) · [Removal](#️-status-backups-and-removal) ·
[Safety](#️-safety-rules)**

---

## 📡 What this repository does

DVSwitch-Mods provides two types of changes:

- **Repairs** correct confirmed problems in DVSwitch, including malformed P25
  and YSF commands, database downloads, P25 announcements, and dashboard link
  detection.
- **Modifications** add optional dashboard features such as friendly reflector
  and talkgroup names, D-Star reflector details, FCC first names, and cleaner
  activity targets.

Every installer checks compatibility before changing anything, creates a
protected backup, installs atomically, validates the result, and rolls back
automatically if installation fails.

---

## 🚀 Quick start — install everything

### 1. Download the complete repository

Run this from your home directory:

```bash
cd ~ && git clone https://github.com/ke2hni/DVSwitch-Mods.git && cd DVSwitch-Mods
```

Already downloaded it? Update it instead:

```bash
cd ~/DVSwitch-Mods && git pull --ff-only
```

You can also download one ZIP containing the entire repository from the
green **Code** button on GitHub or use the
**[direct ZIP download](https://github.com/ke2hni/DVSwitch-Mods/archive/refs/heads/main.zip)**.
Do not download the scripts individually.

### 2. Use the installer menu

Run the manager without arguments:

```bash
sudo ./manage-dvswitch-mods.sh
```

The menu provides three installation choices:

1. **Standard DVSwitch repairs and modifications** — runs the complete
   dependency-ordered installation and records its reversible backups.
2. **Dark Mode** — launches the standalone dashboard theme installer. It adds
   the Auto/Light/Dark selector and creates its own protected and per-run
   backups.
3. **Widescreen Display Layout** — launches the standalone responsive-layout
   installer. It creates its own protected and per-run backups.

The Dark Mode and Display Layout installers do not require the standard
component chain. For a complete dashboard setup, run option 1 first, then
option 2, then option 3. Option 0 exits without changing anything.

The standalone installers can also be run directly:

```bash
sudo ./dvswitch-dark-mode.sh apply
sudo ./dvswitch-display-layout.sh apply
```

### 3. Check the complete standard installation

```bash
sudo ./manage-dvswitch-mods.sh --check all
```

On a fresh DVSwitch installation, the first check normally reports early
components as ready and later components as blocked by prerequisites. It checks
everything, changes nothing, and prints the correct installation order.

### 4. Install or update every applicable standard repair and modification

```bash
sudo ./manage-dvswitch-mods.sh --install all
```

The manager installs components in the required order, selects the correct
MMDVM repair for the installed architecture, skips components that do not
apply, records every backup, and resumes safely if an installation is
interrupted. It is upgrade-aware: manager records do not cause components to
be skipped. Each component's current `--check` and `--install` logic decides
whether it is current, needs a newer compatible repository update, or must be
refused as unsupported or customized.

When a newer compatible version is available, the manager creates a new
protected backup and replaces that component's active manager record. When the
installed version is current, the component remains idempotent and no new
backup is created.

### 5. Verify the completed standard installation

```bash
sudo ./manage-dvswitch-mods.sh --check all
```

A completed installation should end with no failed or blocked components.

---

## 🔧 Repairs

Repairs may be installed individually. Always run `--check` first.

### MMDVM P25 and YSF spacing repair

**What it fixes:** Corrects malformed remote commands so MMDVM_Bridge sends
`TalkGroup 10200` to P25Gateway and `LinkYSF 44444` to YSFGateway.

**Prerequisite:** None. The manager detects the installed architecture and
selects exactly one repair.

```bash
sudo ./manage-mmdvm-spacing.sh --check
sudo ./manage-mmdvm-spacing.sh --install
```

Supported completed repairs:

- ARM64: `repair-mmdvm-spacing.sh`
- AMD64 or i386: `repair-mmdvm-spacing-x86.sh`

The separate ARMHF testing release is documented near the bottom of this page.

### DVSwitch database updater repair

**What it fixes:** Validates TXT database downloads before atomically replacing
working files, preventing empty or damaged downloads from being installed.

**Prerequisite:** None. This repair must be installed before
`mod-p25-nxdn-json.sh`.

```bash
sudo ./repair-dvswitch-txt-updater.sh --check
sudo ./repair-dvswitch-txt-updater.sh --install
```

### P25 audio-announcement repair

**What it fixes:** Makes P25 remote voice announcements begin immediately and
adds an 800 ms silent lead-in so the start of the announcement is not clipped.

**Prerequisite:** ARM64 or AMD64, Internet access during the pinned source
build, and P25Gateway version `20201105`.

```bash
sudo ./repair-p25-audio-announcement.sh --check
sudo ./repair-p25-audio-announcement.sh --install
```

### P25 dashboard repair

**What it fixes:** Allows the dashboard to recognize P25Gateway remote-command
and static-startup reflector messages.

**Prerequisite:** None. Install it before the P25/NXDN friendly-name
modification.

```bash
sudo ./repair-p25-dashboard.sh --check
sudo ./repair-p25-dashboard.sh --install
```

### YSF dashboard null repair

**What it fixes:** Uses case-insensitive YSF room matching and prevents the
dashboard from displaying a literal `null` instead of the linked room name.

**Prerequisite:** `mod-dmr-friendly-names.sh` and a valid `YSFHosts.txt`.

```bash
sudo ./repair-ysf-dashboard-null.sh --check
sudo ./repair-ysf-dashboard-null.sh --install
```

---

## ✨ Optional modifications

These features are included by `--install all`, or they can be installed
individually in the order shown below.

### 1. P25 and NXDN JSON databases

**What it adds:** Validated P25 and NXDN JSON downloads for dashboard-friendly
reflector information.

**Required first:** `repair-dvswitch-txt-updater.sh`.

```bash
sudo ./mod-p25-nxdn-json.sh --check
sudo ./mod-p25-nxdn-json.sh --install
```

### 2. P25 and NXDN friendly names

**What it adds:** P25 and NXDN reflector names with sponsor and numeric
fallbacks on the dashboard.

**Required first:** `repair-p25-dashboard.sh`, `mod-p25-nxdn-json.sh`, and valid
P25/NXDN JSON files.

```bash
sudo ./mod-p25-nxdn-friendly-names.sh --check
sudo ./mod-p25-nxdn-friendly-names.sh --install
```

### 3. D-Star Tx TG/Ref display

**What it adds:** D-Star transmit talkgroup/reference information and the
reflector module on the dashboard.

**Required first:** `mod-p25-nxdn-friendly-names.sh`.

```bash
sudo ./mod-dstar-tx-ref.sh --check
sudo ./mod-dstar-tx-ref.sh --install
```

### 4. DMR friendly names

**What it adds:** Dynamic `DMR BM Master` and `DMR TGIF Master` headings,
BrandMeister/TGIF/STFU talkgroup names, saved network state, long-name wrapping,
and protection against stale cross-mode talkgroups. Blank BrandMeister names
and valid reflector entries are accepted because they are normal records in
the published list; unnamed entries simply have no friendly name to display.

**Required first:** `mod-dstar-tx-ref.sh` and valid BrandMeister and TGIF lists.

```bash
sudo ./mod-dmr-friendly-names.sh --check
sudo ./mod-dmr-friendly-names.sh --install
```

After this modification, install the YSF dashboard null repair described in
the Repairs section.

### 5. Worldwide DMR/FCC names

**What it adds:** A Name column to Gateway Activity only. Local Activity is
intentionally left unchanged. DVSwitch's
worldwide `DMRIds.dat` supplies the complete meaningful name or description,
including international operators and entries such as club names. Blank,
placeholder, conflicting, or malformed DMR names fall back to the FCC first-name
database; `---` is shown only when neither source supplies usable data. The mod also
installs a self-contained weekly FCC database updater and randomized systemd
timer.

Lookup input is normalized only for the private database lookup: surrounding or
internal spaces and trailing Unicode replacement characters are removed, and
standard `/suffix` or `-suffix` forms are reduced to the base callsign. The
original transmitted callsign remains unchanged on the dashboard. This handles
values such as `WD1V ��` without converting international suffixes into FCC data.

**Required first:** Independent of the P25/NXDN/DMR chain, but install it before
the dashboard Target display modification. Internet access is required for the
initial FCC database build.

```bash
sudo ./mod-dashboard-fcc-first-names.sh --check
sudo ./mod-dashboard-fcc-first-names.sh --install
```

Manual FCC update:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --update
```

### 6. Cleaner dashboard targets

**What it adds:** Row-specific friendly talkgroup and reflector names, D-Star
routes, Group Call, General Call, GPS/Data labels, and a compact legend with
separation from the Local Activity grid. History rows remain tied to the
destination recorded when each reception occurred.

**Required first:** `mod-dashboard-fcc-first-names.sh`; valid P25/NXDN JSON and
BrandMeister/TGIF lists provide the friendly names.

```bash
sudo ./mod-dashboard-targets.sh --check
sudo ./mod-dashboard-targets.sh --install
```

### 7. Hostname-prefixed dashboard title

**What it adds:** The detected system hostname before the existing dashboard
heading and browser-tab title. For example, a host named `pi4test` displays
`pi4test DVSwitch Dashboard` in both places. The hostname is generated by PHP
when the page is rendered, so the same installed modification displays the
current name on each node without being rerun after a hostname change.

This is a surgical modification to the exact `<title>DVSwitch Dashboard</title>`
and `<h2>DVSwitch Dashboard</h2>` blocks in `index.php`. It does not modify
dashboard layout, CSS, themes, activity tables, or Local Activity logic.

```bash
sudo ./mod-dashboard-hostname-title.sh --check
sudo ./mod-dashboard-hostname-title.sh --install
```

### 8. Dashboard Dark Mode

**What it adds:** A dashboard theme selector with **Auto**, **Light**, and
**Dark** modes. Auto follows the browser or operating-system color preference.
The theme is applied to the dashboard without changing DVSwitch's live status
colors.

**Required first:** None. This is a standalone dashboard overlay and is also
available as option 2 in the manager menu. It may be run after the standard
installation and before the display-layout installer.

```bash
sudo ./dvswitch-dark-mode.sh apply
```

The generated web assets are installed as readable Apache files with
`root:root` ownership and mode `0644`, including on a completely fresh
installation.

Restore the latest Dark Mode run backup:

```bash
sudo ./dvswitch-dark-mode.sh restore-latest
```

Restore the protected pre-theme dashboard files:

```bash
sudo ./dvswitch-dark-mode.sh restore-original
```

### 9. Widescreen Display Layout

**What it adds:** Responsive dashboard width, readable table wrapping, wider
Gateway and Local Activity panels, and centered Hardware Info on compatible
screens.

**Required first:** None. This is a standalone dashboard layout installer and
is also available as option 3 in the manager menu. Run it after Dark Mode when
both are being installed together.

```bash
sudo ./dvswitch-display-layout.sh apply
```

Restore the latest layout run backup:

```bash
sudo ./dvswitch-display-layout.sh restore-latest
```

Restore the protected pre-layout dashboard files:

```bash
sudo ./dvswitch-display-layout.sh restore-original
```

---

## 🧭 Complete installation order

The unified manager handles this order automatically:

1. MMDVM spacing repair for the detected architecture
2. DVSwitch database updater repair
3. P25 audio announcement repair for ARM64 or AMD64
4. P25 dashboard repair
5. P25/NXDN JSON databases
6. P25/NXDN friendly names
7. D-Star Tx TG/Ref display
8. DMR friendly names
9. YSF dashboard null repair
10. Worldwide DMR/FCC names
11. Dashboard target display
12. Dashboard cell spacing and Target wrapping
13. Hostname-prefixed dashboard title

The optional standalone dashboard installers are run separately from the
manager's recorded standard-component order:

14. Dark Mode overlay
15. Widescreen Display Layout

The menu launches these two installers after the standard installation choice;
their backups are maintained by the standalone scripts.

> [!NOTE]
> Re-running `--install all` after downloading a newer repository version is
> supported. The manager rechecks every applicable component instead of
> relying only on its previous installation record. Component installers still
> refuse missing, ambiguous, customized, or unsupported targets.

> [!NOTE]
> The DVSwitch database updater cannot be run more than once per hour. The
> manager enforces this limit and reports how long remains before another
> attempt is permitted.

---

## ↩️ Status, backups, and removal

List the changes installed and recorded by the manager:

```bash
sudo ./manage-dvswitch-mods.sh --status
```

The status file records the currently active reversible backup for each
component. An upgrade replaces that component's active record with the new
backup; older backup directories are retained for manual recovery.

Remove everything installed by the manager in safe reverse order:

```bash
sudo ./manage-dvswitch-mods.sh --uninstall all
```

Remove the most recently installed individual component:

```bash
sudo ./manage-dvswitch-mods.sh --uninstall COMPONENT
```

Because several components modify the same files, individual removal is
allowed only in reverse installation order. The manager identifies which later
component must be removed first.

Protected backups are stored under:

```text
/var/backups/dvswitch-mods/
```

Individual scripts can restore their named `install-YYYYMMDD-HHMMSS` backup:

```bash
sudo ./SCRIPT_NAME.sh --restore install-YYYYMMDD-HHMMSS
```

<details>
<summary><strong>DVSwitch was uninstalled and reinstalled</strong></summary>

Before changing anything, the manager confirms that every active record still
has its protected backup. If old manager records remain after DVSwitch and its
backups were removed, installation stops safely.

After intentionally reinstalling DVSwitch, archive and clear only the stale
active records with:

```bash
sudo ./manage-dvswitch-mods.sh --reset-after-reinstall
```

The command does not change DVSwitch or delete backups. It refuses to reset
records while every recorded backup remains available.

</details>

<details>
<summary><strong>FCC updater management</strong></summary>

The weekly updater remains functional even if the repository is removed.

Run it manually:

```bash
sudo /usr/local/sbin/dvswitch-fcc-first-names-update
```

Remove only the automatic updater while preserving the dashboard modification
and database:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --remove-updater
```

Completely remove the modification, database, and updater using the original
installation backup:

```bash
sudo ./mod-dashboard-fcc-first-names.sh --uninstall install-YYYYMMDD-HHMMSS
```

Inspect the schedule and recent log:

```bash
systemctl list-timers dvswitch-fcc-first-names-update.timer
sudo journalctl -u dvswitch-fcc-first-names-update.service -n 100 --no-pager
```

</details>

---

## 🧪 Supported systems and ARMHF testing

Completed testing includes:

- Raspberry Pi 4 with Debian 12 Bookworm ARM64
- Raspberry Pi 5 with Debian 13 Trixie ARM64
- Dell Wyse 3040 with Debian 13 Trixie AMD64
- Exact i386 MMDVM build on a compatible x86 host

`repair-mmdvm-spacing-armhf.sh` is a testing release for one exact 32-bit ARM
hard-float MMDVM_Bridge build. Its offline candidate and safety tests passed,
but it still requires live P25 and YSF testing on an ARMHF DVSwitch node.

```bash
sudo ./repair-mmdvm-spacing-armhf.sh --check
sudo ./repair-mmdvm-spacing-armhf.sh --install
```

> [!CAUTION]
> For the normal installation, do not run the individual MMDVM spacing repair
> scripts yourself. Run:
>
> ```bash
> sudo ./manage-mmdvm-spacing.sh --check
> sudo ./manage-mmdvm-spacing.sh --install
> ```
>
> The manager automatically selects the correct repair for your system. The
> individual ARM64, AMD64/i386, and ARMHF scripts are provided only for
> advanced testing or troubleshooting.

---

## 🛡️ Safety rules

- Test on a non-production system first.
- Always run `--check` before `--install`.
- Never bypass an unsupported-version or checksum error.
- Never edit a patcher's accepted hash merely to force installation.
- Never copy a patched executable or complete upstream file between systems.
- Keep the protected backup until the installation has been fully tested.
- These scripts are not affiliated with or endorsed by the DVSwitch project.

<details>
<summary><strong>If an MMDVM repair rejects the installed binary</strong></summary>

Do not force the existing patch. Start a new ChatGPT session, attach a current
ZIP of this repository and a copy of the rejected, unmodified
`/opt/MMDVM_Bridge/MMDVM_Bridge`, and ask:

> My DVSwitch MMDVM_Bridge spacing repair rejected this exact binary. Analyze
> the attached unmodified binary and repository without changing my live
> system. Determine its architecture, SHA256, size, GNU Build ID, ELF load
> segments, exact P25 and YSF format strings, every code or literal reference
> to those strings, and verified unused mapped or extendable padding. The
> required results are `TalkGroup 10200` and `LinkYSF 44444`; do not treat
> disconnect value 0 as the defect. Create or update a separate hash-specific
> repair only if every offset and reference can be proved. Preserve file size,
> owner, group, mode, atomic installation, protected backup, automatic
> rollback, named restore, `--check`, `--install`, and idempotency. Do not
> modify completed repairs for other architectures. Mark a new build Testing
> until live `strace` and gateway-log results prove both modes. Give me one
> copy-and-paste command at a time, beginning with read-only checks.

Also provide the complete output from:

```bash
cd ~/DVSwitch-Mods && printf '=== REVISION ===\n' && git status --short --branch && git log -1 --oneline --decorate && printf '\n=== SYSTEM ===\n' && uname -a && dpkg --print-architecture && printf '\n=== BINARY ===\n' && sudo sha256sum /opt/MMDVM_Bridge/MMDVM_Bridge && sudo stat -c 'SIZE=%s OWNER=%U:%G MODE=%a' /opt/MMDVM_Bridge/MMDVM_Bridge && sudo file /opt/MMDVM_Bridge/MMDVM_Bridge && sudo readelf -n /opt/MMDVM_Bridge/MMDVM_Bridge | grep -A1 'Build ID' && sudo readelf -lW /opt/MMDVM_Bridge/MMDVM_Bridge && printf '\n=== PACKAGE ===\n' && dpkg-query -W -f='${binary:Package} ${Version} ${Architecture}\n' mmdvm-bridge 2>&1 && apt-cache policy mmdvm-bridge && printf '\n=== REPAIR CHECK ===\n' && sudo ./REPAIR_SCRIPT_NAME.sh --check; printf '\n=== SERVICES ===\n'; systemctl is-active mmdvm_bridge.service ysfgateway.service p25gateway.service
```

Replace `REPAIR_SCRIPT_NAME.sh` with the repair that rejected the binary.
After a test-node installation, capture the exact UDP sends with `strace` and
the new P25Gateway and YSFGateway log entries before marking it completed.

</details>

---

## 📁 Repository contents

- Top-level `.sh` files are the public repair, modification, and manager tools.
- `lib/` contains narrowly scoped patchers and transaction helpers.
- `systemd/` contains the FCC updater service and timer.
- `tests/` contains compatibility and safety tests.
- `LICENSE` covers repository-authored code.
- `THIRD_PARTY_NOTICES.md` describes upstream ownership and license boundaries.

---

## 📜 License

Repository-authored code is licensed under the MIT License. See `LICENSE` and
`THIRD_PARTY_NOTICES.md`.

---

<div align="center">

### DVSwitch default looking Dashboard after being freshly installed

<img width="1600" height="900" alt="Screenshot 2026-09-10 203809" src="https://github.com/user-attachments/assets/615d83c7-a08d-43db-9f36-a443e6f1dc83" />

### DVSwitch Dashboard with the optional modifications installed

<img width="1600" height="900" alt="Screenshot 2026-09-10 220525" src="https://github.com/user-attachments/assets/162d7b7a-5127-4459-87c3-86a8c4ce88cc" />

<img width="1600" height="900" alt="Screenshot 2026-09-10 220512" src="https://github.com/user-attachments/assets/cb79a14d-e21f-4c3c-aed8-e4cef28ae65b" />

<img width="1200" alt="DVSwitch Dashboard" src="https://github.com/user-attachments/assets/1b9a319b-c6e2-49b7-a001-5e3519560408" />

</div>

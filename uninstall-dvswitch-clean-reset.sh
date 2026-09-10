#!/usr/bin/env bash
set -Eeuo pipefail

# DVSwitch-Mods complete test-node reset v1.1.2
# Order: remove DVSwitch, remove backups, remove installed mod/repair files.
# This intentionally does not restore dashboard files because DVSwitch is removed.

readonly SCRIPT_VERSION="1.1.2"
readonly MOD_BACKUPS="/var/backups/dvswitch-mods"
readonly UNINSTALLER_BACKUPS="/var/backups/dvswitch-uninstaller"
readonly FRESH_UPDATER_BACKUPS="/var/backups/dvswitch-fresh-install-updater"
readonly FULL_UPDATER_BACKUPS="/var/backups/dvswitch-full-updater"
readonly DVSWITCH_MODS_REPO="${DVSWITCH_MODS_REPO:-/home/asl/DVSwitch-Mods}"

readonly PACKAGES=(
  dvswitch-server dvswitch dvswitch-base dvswitch-dashboard dvswitch-menu
  analog-bridge mmdvm-bridge md380-emu ysfgateway p25gateway nxdngateway
  nxdnparrot p25parrot ysfparrot ircddbgateway quantar-bridge monit
  dvswitch-monit libapache2-mod-php php-cgi qemu-user qemu-user-binfmt
  qemu-user-static p25reflector analog-reflector mosquitto mosquitto-clients
  libmosquitto-dev nlohmann-json3-dev libwxgtk3.2-dev netcat-openbsd bc
  php-common php8.4-cgi php8.4-cli php8.4-common php8.4-opcache php8.4-readline
  libapache2-mod-php8.4 quantar
)

readonly SERVICES=(
  analog_bridge.service mmdvm_bridge.service md380-emu.service ysfgateway.service
  ysfparrot.service p25gateway.service p25parrot.service nxdngateway.service
  nxdnparrot.service ircddbgateway.service ircddbgatewayd.service
  quantar_bridge.service webproxy.service monit.service netcheck.service stfu.service
  dvswitch-fcc-first-names-update.service dvswitch-fcc-first-names-update.timer
  ysfgw-mqtt-cache.service p25gw-mqtt-cache.service
)

readonly DVSWITCH_PATHS=(
  /opt/Analog_Bridge /opt/MMDVM_Bridge /opt/YSFGateway /opt/YSFParrot
  /opt/P25Gateway /opt/P25Parrot /opt/NXDNGateway /opt/NXDNParrot
  /opt/Quantar_Bridge /opt/Web_Proxy /opt/md380-emu /opt/ircDDBGateway
  /opt/Analog_Reflector /opt/STFU /var/lib/dvswitch /var/lib/mmdvm
  /var/log/dvswitch /var/log/mmdvm /etc/mmdvm /etc/dvswitch
  /usr/share/dvswitch /usr/share/dvswitch-dashboard /var/www/html/dvswitch
  /var/www/dvswitch /etc/monit /var/lib/monit /var/log/monit
  /etc/apache2/conf-available/dvswitch.conf /etc/apache2/conf-enabled/dvswitch.conf
  /var/lib/dvswitch-fresh-install-updater /var/lib/dvswitch-full-updater
  /usr/local/src/dvswitch-fresh-install-updater /usr/local/src/dvswitch-full-updater
  /usr/local/sbin/dvswitch-fcc-first-names-update
  /usr/local/lib/dvswitch-mods
  /var/lib/dvswitch-mods /var/lib/dvswitch-uninstaller
  /etc/systemd/system/dvswitch-fcc-first-names-update.service
  /etc/systemd/system/dvswitch-fcc-first-names-update.timer
  /etc/systemd/system/ysfgw-mqtt-cache.service
  /etc/systemd/system/p25gw-mqtt-cache.service
  /usr/local/sbin/ysfgw_mqtt_cache.sh /usr/local/sbin/p25gw_mqtt_cache.sh
  /usr/share/dvswitch/css/dvs-theme.css /usr/share/dvswitch/scripts/dvs-theme.js
  /usr/local/dvs /usr/local/sbin/DVSM_Update.sh /usr/local/sbin/DVSwitch-startup
  /usr/local/sbin/dvswitch-log-cleanup /usr/local/sbin/netcheck
  /usr/local/sbin/platformDetect.sh /usr/local/sbin/update-config.sh
  /usr/local/bin/ircddbgateway /usr/local/bin/ircddbgatewayd /usr/local/bin/ircddbgatewayconfig
  /usr/bin/ircddbgateway /usr/bin/ircddbgatewayd /usr/bin/ircddbgatewayconfig
  /usr/share/ircddbgateway /usr/share/opendv /usr/local/share/ircddbgateway
  /etc/ircddbgateway /etc/opendv /var/log/ircddbgateway /var/log/opendv
  /etc/systemd/system/ircddbgatewayd.service
  /usr/lib/systemd/system/ircddbgatewayd.service /lib/systemd/system/ircddbgatewayd.service
  /usr/local/bin/dstar /etc/systemd/system/ircddbgatewayd.service.d
  /usr/share/dvswitch/.dvs-dashboard-display-original
)

need_root() { [[ $EUID -eq 0 ]] || { echo "ERROR: run with sudo." >&2; exit 1; }; }
usage() { printf 'DVSwitch complete clean reset %s\nUsage: sudo %s {--check|--uninstall}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }

installed_packages() {
  local package
  for package in "${PACKAGES[@]}"; do
    dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii ' && printf '%s\n' "$package"
  done
}

show_plan() {
  echo "DVSwitch complete clean reset $SCRIPT_VERSION"
  echo
  echo "ORDER OF OPERATIONS:"
  echo "  1. Stop/disable DVSwitch services and purge DVSwitch packages/files."
  echo "  2. Remove DVSwitch-Mods and DVSwitch updater backup directories."
  echo "  3. Remove installed DVSwitch-Mods helper/runtime files."
  echo "  4. Remove the local DVSwitch-Mods Git checkout."
  echo
  echo "ASL3, Asterisk, AllStarLink, allmon3, Debian, networking, SSH, Git, and the working repository are preserved."
  echo
  echo "Installed DVSwitch packages:"; installed_packages | sed 's/^/  /' || true
  echo "Existing target paths:"; for path in "${DVSWITCH_PATHS[@]}"; do [[ -e "$path" || -L "$path" ]] && echo "  $path"; done
  echo "Existing backup roots:"; for path in "$MOD_BACKUPS" "$UNINSTALLER_BACKUPS" "$FRESH_UPDATER_BACKUPS" "$FULL_UPDATER_BACKUPS" /usr/share/dvswitch/.dvs-dashboard-display-backup-*; do [[ -e "$path" ]] && echo "  $path"; done
  [[ -d "$DVSWITCH_MODS_REPO" ]] && echo "Local repository: $DVSWITCH_MODS_REPO"
  return 0
}

remove_services() { local unit; for unit in "${SERVICES[@]}"; do systemctl stop "$unit" 2>/dev/null || true; systemctl disable "$unit" 2>/dev/null || true; done; return 0; }
remove_paths() { local path; for path in "${DVSWITCH_PATHS[@]}"; do [[ -e "$path" || -L "$path" ]] && rm -rf --one-file-system -- "$path" || true; done; return 0; }
remove_backups() { local path; for path in "$MOD_BACKUPS" "$UNINSTALLER_BACKUPS" "$FRESH_UPDATER_BACKUPS" "$FULL_UPDATER_BACKUPS"; do [[ -e "$path" ]] && rm -rf --one-file-system -- "$path" || true; done; return 0; }
remove_repository() { [[ -d "$DVSWITCH_MODS_REPO" ]] || return 0; cd /tmp; rm -rf --one-file-system -- "$DVSWITCH_MODS_REPO"; }

run_uninstall() {
  echo "WARNING: this permanently removes DVSwitch and all listed DVSwitch-Mods data."
  read -r -p "Type REMOVE to continue: " answer
  [[ "$answer" == REMOVE ]] || { echo "Cancelled. No changes made."; exit 0; }
  remove_services
  mapfile -t packages < <(installed_packages)
  ((${#packages[@]} == 0)) || apt-get purge -y "${packages[@]}"
  apt-get purge -y apache2-mod-php 2>/dev/null || true
  remove_paths
  remove_backups
  remove_repository
  systemctl daemon-reload
  echo "PASS: DVSwitch, DVSwitch-Mods files/backups, and local repository were removed."
  echo "Recommended: reboot before beginning fresh-install testing."
}

main() { need_root; case "${1:---uninstall}" in --check) show_plan ;; --uninstall) show_plan; run_uninstall ;; -h|--help) usage ;; *) usage >&2; exit 2 ;; esac; }
main "$@"

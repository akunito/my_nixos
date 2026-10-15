# devbox — an unattended development/test box driven over SSH (winsub on DESK_A_DEV).
#
# Everything an operator at the keyboard would otherwise do:
#   - greetd starts Sway for devBoxAutoLoginUser without a password (initial_session;
#     ReGreet stays as the fallback greeter after a logout);
#   - the user's systemd --user manager lingers, so harness units survive logouts and
#     start at boot without a session;
#   - a hung kernel reboots itself: systemd pets the hardware watchdog (sp5100_tco on
#     AMD; some boards disable it in BIOS -> check `wdctl`), and the panic sysctls turn
#     hung tasks / soft+hard lockups into a panic, which reboots after panic=10. A GPU
#     hang alone does NOT trip the watchdog (PID 1 keeps petting); that case is handled
#     over SSH or by the Pico-driven RESET header;
#   - the firmware BootOrder is re-asserted at every boot so another OS's installer or
#     update on the same box (Windows, a second NixOS with its own ESP) cannot steal the
#     default entry: the entry whose device path carries devBoxEspPartUuid is moved first.
#     Three OSes = three ESPs, so hand-off between them is `efibootmgr --bootnext`, not
#     bootctl (which only sees its own loader entries).
# Flags: devBoxEnable, devBoxAutoLoginUser, devBoxEspPartUuid (lib/defaults.nix).
{ config, lib, pkgs, systemSettings, ... }:
let
  enabled = systemSettings.devBoxEnable or false;
  user = systemSettings.devBoxAutoLoginUser or null;
  espUuid = systemSettings.devBoxEspPartUuid or null;
in
lib.mkIf enabled {
  services.greetd.settings.initial_session = lib.mkIf (user != null) {
    command = "sway";
    inherit user;
  };
  users.users = lib.mkIf (user != null) { ${user}.linger = true; };

  boot.kernelParams = [ "panic=10" "nmi_watchdog=1" ];
  boot.kernel.sysctl = {
    "kernel.hung_task_panic" = 1;
    "kernel.hung_task_timeout_secs" = 120;
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
  };
  systemd.settings.Manager = { RuntimeWatchdogSec = "30s"; RebootWatchdogSec = "10min"; };

  systemd.services.devbox-bootorder = lib.mkIf (espUuid != null) {
    description = "Keep this ESP's boot entry first in the firmware BootOrder";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = { Type = "oneshot"; };
    path = [ pkgs.efibootmgr pkgs.gnugrep pkgs.gnused pkgs.gawk ];
    script = ''
      set -eu
      uuid=$(echo "${espUuid}" | tr 'A-F' 'a-f')
      out=$(efibootmgr -v)
      entry=$(echo "$out" | tr 'A-F' 'a-f' | grep -i "hd(.*,gpt,$uuid," | sed -n 's/^boot\([0-9a-f]\{4\}\).*/\1/p' | head -1)
      [ -n "$entry" ] || { echo "devbox-bootorder: no entry for ESP $uuid"; exit 0; }
      order=$(echo "$out" | sed -n 's/^BootOrder: //p')
      rest=$(echo "$order" | tr ',' '\n' | grep -vi "^$entry$" | paste -sd, -)
      new="$(echo "$entry" | tr 'a-f' 'A-F')''${rest:+,$rest}"
      [ "$(echo "$order" | tr 'a-f' 'A-F')" = "$new" ] || efibootmgr -o "$new"
    '';
  };
}

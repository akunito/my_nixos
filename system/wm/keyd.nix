{ pkgs, lib, userSettings, systemSettings, ... }:
let
  # Keypad profiles (SWAY-18): every profile is an immutable /etc/keypad/<device>/<profile>
  # built here; /etc/keyd/<device>.conf only includes /etc/keyd/<device>-active, a plain root
  # file the activation script and `keypad-profile set` copy the chosen profile into (then
  # keyd reload). Switching never takes arbitrary content: keyd's command() runs as root,
  # so a user-writable include would be a root shell.
  keydOn = (userSettings.wm == "sway" || 
    systemSettings.enableSwayForDESK == true ||
    userSettings.wm == "plasma6" ||
    userSettings.wm == "hyprland" ||
    (systemSettings ? wmEnableHyprland && systemSettings.wmEnableHyprland == true));
  keypads = (builtins.fromJSON (builtins.readFile ../../user/wm/sway/apps/keyd-devices.json)).devices;
  profilesOf = d: d.profiles or { default = { name = "Default"; main = d.main or { }; }; };
  defaultOf = d: d.default_profile or (builtins.head (builtins.attrNames (profilesOf d)));
  # command() runs as root inside keyd: refused here too, not only in the GUI.
  iniOf = p: assert lib.assertMsg (!(lib.hasInfix "command(" (builtins.toJSON p))) "keyd-devices.json: command() is not allowed in keypad profiles"; "[main]\n" + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") (p.main or { }))
    + lib.concatStrings (lib.mapAttrsToList (layer: binds: "\n[${layer}]\n"
        + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") binds)) (p.layers or { }));
  keypadBoards = lib.mapAttrs (n: _: { ids = keypads.${n}.ids; extraConfig = "include ${n}-active"; }) keypads;
  keypadEtc = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList (n: d: lib.mapAttrsToList (pid: p:
    lib.nameValuePair "keypad/${n}/${pid}" { text = iniOf p; mode = "0644"; }) (profilesOf d)) keypads));
  keypadProfile = pkgs.writeShellScriptBin "keypad-profile" ''
    # keypad-profile set|get|list DEVICE [PROFILE] - switch a keypad to a profile built by Nix.
    set -eu
    cmd=''${1:-}; dev=''${2:-}; pid=''${3:-}
    case "$dev" in ""|*[!a-z0-9_]*) echo "bad device" >&2; exit 2;; esac
    case "$cmd" in
      list) ls /etc/keypad/"$dev" ;;
      get) cat /var/lib/keypad/"$dev".profile 2>/dev/null || echo "${"$"}{dev}: none" ;;
      set)
        case "$pid" in ""|*[!a-z0-9_-]*) echo "bad profile" >&2; exit 2;; esac
        [ -f /etc/keypad/"$dev"/"$pid" ] || { echo "no profile $pid for $dev (deploy it first)" >&2; exit 2; }
        ${pkgs.coreutils}/bin/install -D -m 0644 /etc/keypad/"$dev"/"$pid" /etc/keyd/"$dev"-active
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/keypad
        echo "$pid" > /var/lib/keypad/"$dev".profile
        ${pkgs.keyd}/bin/keyd reload >/dev/null
        echo "$dev -> $pid" ;;
      *) echo "usage: keypad-profile set|get|list DEVICE [PROFILE]" >&2; exit 2 ;;
    esac
  '';
in

{
  # Enable keyd service for keyboard remapping
  # Keyd works at the kernel input level, so it works in Sway, Plasma, Hyprland, console, TTY, and login screens
  # Enable for all GUI environments: Sway, Plasma 6, Hyprland
  # This covers personal, desk, laptops, and work computers that use GUI
  services.keyd = lib.mkIf keydOn {
    enable = true;
    
    keyboards = keypadBoards // {
    default = {
      # "-5341:0001": sway-apps input's uinput keyboard (SWAY-17) stays out of keyd, so sway
      # groups it with keyd's virtual keyboard (Diego's keymap, one modifier state) instead of
      # it sharing keyd's layer state and phantom-Ctrl modifier guard with Diego's keyboards.
      ids = [ "*" "-5341:0001" ];  # Apply to all keyboards (and keyboards with mouse buttons)
      settings = {
        main = {
          # Map CapsLock to Ctrl+Alt+Meta (Super) - this equals Hyper key (Mod4+Control+Mod1)
          # This disables normal Caps Lock functionality (no uppercase toggle)
          # Using overload: Caps Lock acts as Hyper when held, Escape when tapped
          # Note: Keychron keyboards with firmware remapping already send C-A-M directly,
          # so this remapping only affects keyboards that send standard Caps Lock keycodes
          capslock = "overload(hyper, esc)";
        };
        # Use single letter M for Meta in the suffix
        "hyper:C-A-M" = {
          # This layer is active when capslock is held
          # The ":C-A-M" suffix automatically sends Control+Alt+Meta modifiers as held modifiers
          # All keys work normally, but with the Hyper modifiers active
          # Dummy entry to prevent Nix from optimizing away the empty set
          noop = "noop";
        };
      };
    };

    # Keypads (Razer Tartarus V2, …) come from user/wm/sway/apps/keyd-devices.json, edited in
    # the sway-apps GUI "Keypad" page (SWAY-18): one keyd keyboard per device, its key ->
    # action map as [main]. An explicit id entry replaces the "*" config for that device, so
    # e.g. the Tartarus' key 11 is a plain shift, not the capslock hyper overload.
    # Separate entry for mice - keyd's "*" wildcard only matches keyboards, not mice
    # This ensures mouse1 mapping works for actual mouse devices
    # Note: To add more mice, add their vendor:product IDs to the ids list
     razer_mouse = {
      ids = [ "1532:00b2" ];  # Razer DeathAdder V3 - add more mouse IDs here as needed
      settings = {
        main = {
          # Map mouse side button (mouse1) to Control+Alt modifier combination
          # Using overload with noop instead of esc - noop does nothing, preventing unwanted key events
          mouse1 = "overload(combo_C_A, noop)";
        };
        # combo_C_A layer for Control+Alt (triggered by mouse1)
        "combo_C_A:C-A" = {
          # Dummy entry to prevent Nix from optimizing away the empty set
          noop = "noop";
        };
        # The side button's firmware sends Hyper+M (shared with W11, where it is AkuWM's
        # mic toggle). Here Hyper+M is Mission Center, so only this device's Hyper+M becomes
        # Hyper+Shift+F12 (sway-apps: mic-toggle). A composite layer drops the held C-A-M and
        # emits exactly the sequence bound here.
        "control+alt+meta" = {
          m = "C-A-M-S-f12";
        };
      };
    };
    };
  };

  environment.etc = lib.mkIf keydOn keypadEtc;
  environment.systemPackages = lib.mkIf keydOn [ keypadProfile ];
  # The GUI's profile switch: exactly `keypad-profile set`, which only copies a Nix-built profile.
  security.sudo.extraRules = lib.mkIf keydOn [{
    users = [ userSettings.username ];
    commands = [{ command = "/run/current-system/sw/bin/keypad-profile set *"; options = [ "NOPASSWD" ]; }];
  }];
  # Re-apply each keypad's chosen profile (its content may have changed with this deploy);
  # a profile that no longer exists falls back to the device's default_profile.
  system.activationScripts.keypad = lib.mkIf keydOn {
    deps = [ "etc" ];
    text = lib.concatStrings (lib.mapAttrsToList (n: d: ''
      mkdir -p /var/lib/keypad
      sel=$(cat /var/lib/keypad/${n}.profile 2>/dev/null || true)
      if [ -z "$sel" ] || [ ! -f /etc/keypad/${n}/"$sel" ]; then sel=${defaultOf d}; fi
      ${pkgs.coreutils}/bin/install -D -m 0644 /etc/keypad/${n}/"$sel" /etc/keyd/${n}-active
      echo "$sel" > /var/lib/keypad/${n}.profile
    '') keypads) + ''
      if ${pkgs.systemd}/bin/systemctl -q is-active keyd; then ${pkgs.keyd}/bin/keyd reload >/dev/null 2>&1 || true; fi
    '';
  };
}

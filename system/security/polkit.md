We can allow certain groups or users to perform specific actions without being asked for password when higher rights are needed.

# Add the rules to your profile config (`profiles/PROFILE-config.nix`)
Sample:
```sh
        polkitEnable = true;
        polkitRules = ''
          polkit.addRule(function(action, subject) {
            if (
              subject.isInGroup("users") && (
                // Allow reboot and power-off actions
                action.id == "org.freedesktop.login1.reboot" ||
                action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
                action.id == "org.freedesktop.login1.power-off" ||
                action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
                action.id == "org.freedesktop.login1.suspend" ||
                action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||

                // Allow managing specific systemd units
                (action.id == "org.freedesktop.systemd1.manage-units" &&
                  action.lookup("verb") == "start" &&
                  action.lookup("unit") == "mnt-NFS_Backups.mount") ||

                // Allow running rsync and restic
                (action.id == "org.freedesktop.policykit.exec" &&
                  (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
                  action.lookup("command") == "/run/current-system/sw/bin/restic"))
              )
            ) {
              return polkit.Result.YES;
            }
          });
        '';
```

# Setup polkit.nix module
And make sure it's sourced by the configuration.nix file

```sh
{ lib, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  security.polkit = {
    enable = true;
    extraConfig = systemSettings.polkitRules;
  };
}

```
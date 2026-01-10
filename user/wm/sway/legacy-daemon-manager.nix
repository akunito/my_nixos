{ config, lib, ... }:

let
  useSystemdSessionDaemons = config.user.wm.sway.useSystemdSessionDaemons;
in
{
  # Legacy daemon-manager path is deprecated in this repo; systemd-first is the default.
  #
  # This module remains as a placeholder so the refactor can keep `imports = [ ... ]` stable
  # without conditional imports. If you ever need to resurrect the legacy logic, implement it
  # under the mkIf below.
  config = lib.mkIf (!useSystemdSessionDaemons) { };
}



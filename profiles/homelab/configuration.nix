{ userSettings, systemSettings, lib, ... }:

{
  imports = [ ./base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = systemSettings.authorizedKeys; # SSH keys
                inherit userSettings;
                inherit systemSettings;
                inherit lib; })
            ]
            # On-demand llama.cpp backend (NAS_PROD: the RTX 3090 reasoner preset). Same module as DESK.
            ++ lib.optional (systemSettings.llamaServerEnable or false) ../../system/app/llama-server.nix
            ++ lib.optional (systemSettings.aiPresetsEnable or false) ../../system/app/ai-presets.nix
            ++ lib.optional (systemSettings.captureHubEnable or false) ../../system/app/capture-hub.nix; # capture-hub: Elgato UVC -> frames + OCR + VLM notes per profile
}

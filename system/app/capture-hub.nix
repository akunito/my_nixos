# capture-hub: screen/HDMI capture pipeline (plan docs/akunito/plans/capture-hub.md).
#
# Frames from a UVC capture card (Elgato 4K X: the HDMI output of ANOTHER machine), the
# local Wayland screen (grim) or pushed files -> change-filtered JPEGs + tesseract text +
# optional VLM notes (NAS llama-server, OpenAI image chat), stored per PROFILE (one
# directory per project: aion2, l2, study, trading, hermes...) and served on a small HTTP
# API (`capture-hub status|profile|ask|latest|text|notes|push`) for the AI that consumes
# them. Script: system/app/capture-hub/capture_hub.py.
#
# Two shapes, same script and config:
#   captureHubUserService = false -> SYSTEM service as User= (NAS: headless, UVC only),
#     StateDirectory /var/lib/capture-hub, port on tailscale0 only.
#   captureHubUserService = true  -> USER service (DESK: the screen source needs
#     WAYLAND_DISPLAY, read from %t/sway-session.env like every other Sway user unit),
#     data in ~/.local/share/capture-hub, API on 127.0.0.1.
# The Elgato 4K X needs kernel >= 6.19 for UVC (AINF-404 on the NAS, 6.12 today); the
# daemon just waits ("waiting-device") until the by-id node appears, so the module can be
# deployed before the card is plugged in.
{ pkgs, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  user = if (cfg.captureHubUser or null) != null then cfg.captureHubUser else userSettings.username;
  userService = cfg.captureHubUserService or false;
  dataDir = if (cfg.captureHubDataDir or null) != null then cfg.captureHubDataDir
            else if userService then "$HOME/.local/share/capture-hub" else "/var/lib/capture-hub";
  listen = cfg.captureHubListen or "127.0.0.1:8095";
  listenPort = lib.toInt (lib.last (lib.splitString ":" listen));

  py = pkgs.python3.withPackages (ps: with ps; [ pillow imagehash ]);
  # tesseract with the languages built in: the wrapper exports TESSDATA_PREFIX itself.
  tesseract = pkgs.tesseract.override { enableLanguages = cfg.captureHubOcrLanguages or [ "eng" "spa" "pol" ]; };
  configFile = pkgs.writeText "capture-hub.json" (builtins.toJSON {
    data_dir = dataDir;
    inherit listen;
    profile = cfg.captureHubDefaultProfile or "generic";
    vlm = {
      url = cfg.captureHubVlmUrl or "http://100.64.0.1:8090";
      model = cfg.captureHubVlmModel or "reasoner-9b-512k";
      timeout = 180;
      max_side = 1280;
    };
    ocr.langs = lib.concatStringsSep "+" (cfg.captureHubOcrLanguages or [ "eng" "spa" "pol" ]);
    sources = cfg.captureHubSources or [ ];
    profiles = cfg.captureHubProfiles or { };
  });
  captureHub = pkgs.runCommand "capture-hub" { } ''
    mkdir -p $out/bin $out/lib/capture-hub
    cp ${./capture-hub/capture_hub.py} $out/lib/capture-hub/capture_hub.py
    cat > $out/bin/capture-hub <<EOF
    #!${pkgs.runtimeShell}
    export CAPTURE_HUB_CONFIG="\''${CAPTURE_HUB_CONFIG:-${configFile}}"
    export CAPTURE_HUB_FFMPEG=${pkgs.ffmpeg}/bin/ffmpeg
    export CAPTURE_HUB_TESSERACT=${tesseract}/bin/tesseract
    export CAPTURE_HUB_GRIM=${pkgs.grim}/bin/grim
    exec ${py}/bin/python3 -I $out/lib/capture-hub/capture_hub.py "\$@"
    EOF
    chmod +x $out/bin/capture-hub
  '';
in
{
  environment.systemPackages = [ captureHub ];
  environment.etc."capture-hub/config.json".source = configFile;

  systemd.services.capture-hub = lib.mkIf (!userService) {
    description = "capture-hub: HDMI/screen capture -> frames + text + VLM notes per profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = user;
      SupplementaryGroups = [ "video" ];
      StateDirectory = "capture-hub";
      StateDirectoryMode = "0750";
      ExecStart = "${captureHub}/bin/capture-hub daemon";
      Restart = "always";
      RestartSec = 5;
      Nice = 5;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.user.services.capture-hub = lib.mkIf userService {
    description = "capture-hub: screen/HDMI capture -> frames + text + VLM notes per profile";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      # WAYLAND_DISPLAY/SWAYSOCK for grim; absent (no Sway session yet) the screen source
      # reports waiting-device and the unit stays up for the v4l2 source.
      EnvironmentFile = "-%t/sway-session.env";
      ExecStart = "${captureHub}/bin/capture-hub daemon";
      Restart = "always";
      RestartSec = 5;
      Nice = 5;
    };
  };

  # NAS: the API is reachable from the tailnet (DESK, VPS/Hermes) and nowhere else.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.optional (!userService && !(lib.hasPrefix "127." listen)) listenPort;
}

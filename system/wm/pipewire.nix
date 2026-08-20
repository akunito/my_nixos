{ lib, pkgs, systemSettings, ... }:

let
  # ALSA card name -> friendly name. See systemSettings.audioDeviceRenames.
  renames = systemSettings.audioDeviceRenames or { };

  # RNNoise mic cleanup. See systemSettings.micNoiseSuppression.
  mic = systemSettings.micNoiseSuppression or null;
in
{
  # Pipewire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    # Friendly labels for USB audio gear that reports a useless generic ident
    # (cheap mics almost all enumerate as "USB PnP Audio Device"). Without this
    # they are indistinguishable from each other in Discord/pavucontrol.
    #
    # Matching is on the ALSA card name, i.e. keyed to the HARDWARE, not to a
    # machine: plug the same mic into any profile with audio and it gets the
    # right label. The rule is inert when the card is absent, which is why the
    # map lives in lib/defaults.nix for every host instead of being enabled
    # per-profile.
    #
    # NOTE: the props are applied to every node on the matched card, so only use
    # this for single-purpose devices (a mic, a headset) — labelling a
    # multi-channel interface this way would name all of its nodes identically.
    wireplumber.extraConfig = lib.optionalAttrs (renames != { }) {
      "51-audio-device-names" = {
        "monitor.alsa.rules" = lib.mapAttrsToList (card: friendly: {
          matches = [ { "api.alsa.card.name" = card; } ];
          actions.update-props = {
            "device.description" = friendly;
            "device.nick" = friendly;
            "node.description" = friendly;
            "node.nick" = friendly;
          };
        }) renames;
      };
    };

    # Mic noise suppression: high-pass -> RNNoise -> virtual "clean" source.
    #
    # Aimed at STEADY noise (fans, PC/NAS hum), which is what RNNoise was
    # trained on. It does little for impulsive noise like keyboard or chair
    # knocks. The high-pass runs first because roughly half the noise energy on
    # a desk mic sits below 250 Hz, and stripping it before RNNoise leaves the
    # network a cleaner problem than it would otherwise get.
    #
    # `target.object` pins the capture side to a specific hardware source. That
    # matters: without it the chain would bind to the DEFAULT source, and once
    # the clean source is itself the default, it would capture its own output.
    #
    # Rate is pinned to 48 kHz because RNNoise only operates there; letting the
    # graph negotiate another rate silently degrades the model.
    #
    # Unlike audioDeviceRenames this is NOT a global default. A rename is inert
    # without its hardware, but a filter chain whose target is absent still
    # publishes a virtual source that produces silence — worse to debug than a
    # missing one. So each profile opts in.
    extraConfig.pipewire = lib.optionalAttrs (mic != null) {
      "99-mic-noise-suppression" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = mic.description;
              "media.name" = mic.description;
              "filter.graph" = {
                nodes = [
                  {
                    type = "builtin";
                    name = "hp";
                    label = "bq_highpass";
                    control = {
                      "Freq" = mic.highPassHz or 90;
                      "Q" = 0.707;
                    };
                  }
                  {
                    type = "ladspa";
                    name = "rn";
                    plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
                    label = "noise_suppressor_mono";
                    control = {
                      # Higher = more aggressive gating of non-speech.
                      "VAD Threshold (%)" = mic.vadThreshold or 50.0;
                      # Keeps the gate open briefly so word endings survive.
                      "VAD Grace Period (ms)" = 200;
                      "Retroactive VAD Grace (ms)" = 0;
                    };
                  }
                ];
                links = [ { output = "hp:Out"; input = "rn:Input"; } ];
              };
              "capture.props" = {
                "node.name" = "${mic.nodeName}.capture";
                "node.passive" = true;
                "target.object" = mic.target;
                "audio.rate" = 48000;
              };
              "playback.props" = {
                "node.name" = mic.nodeName;
                "media.class" = "Audio/Source";
                "audio.rate" = 48000;
              };
            };
          }
        ];
      };
    };
  };
}

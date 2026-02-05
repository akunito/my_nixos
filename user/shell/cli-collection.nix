{ pkgs, lib, ... }:
{
  # Collection of useful CLI apps (cross-platform)
  home.packages = with pkgs;
    # === Cross-platform CLI tools ===
    [
      lolcat
      cowsay
      starfetch
      cava
      killall
      timer
      gnugrep
      bat
      eza
      fd
      bottom
      ripgrep
      rsync
      unzip
      w3m
      pandoc
      numbat
      fzf
      jq
      vim
      neovim
      (pkgs.callPackage ../pkgs/pokemon-colorscripts.nix { })
    ]
    # === Linux-only CLI tools ===
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [
      libnotify      # Linux notification system
      brightnessctl  # Linux brightness control
      hwinfo         # Linux hardware info
      pciutils       # Linux PCI utilities
      # airplane-mode script uses nmcli (NetworkManager) - Linux only
      (pkgs.writeShellScriptBin "airplane-mode" ''
        #!/bin/sh
        connectivity="$(nmcli n connectivity)"
        if [ "$connectivity" == "full" ]
        then
            nmcli n off
        else
            nmcli n on
        fi
      '')
    ];
}

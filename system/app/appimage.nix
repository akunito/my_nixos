{ config, pkgs, lib, ... }:

{
    programs.appimage = {
        enable = true;
        binfmt = true;
    };

    environment.systemPackages = with pkgs; [
        appimage-run
    ];

    programs.appimage.package = pkgs.buildEnv {
        name = "appimage-extra-libs";
        paths = with pkgs; [
            # Add any missing libraries here
            xorg.libxcb
            xorg.libX11
            libxkbcommon
            qt5.qtbase
            glib
            zlib
        ];
    };

    boot.binfmt.registrations.appimage = {
        wrapInterpreterInShell = false;
        interpreter = "${pkgs.appimage-run}/bin/appimage-run";
        recognitionType = "magic";
        offset = 0;
        mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
        magicOrExtension = ''\x7fELF....AI\x02'';
    };

}





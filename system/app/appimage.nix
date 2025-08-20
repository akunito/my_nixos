{ config, pkgs, lib, ... }:

{
    programs.appimage = {
        enable = true;
        binfmt = true;
    };

    environment.systemPackages = with pkgs; [
        appimage-run
    ];

    programs.appimage.package = pkgs.appimage-run.override {
        extraPkgs = pkgs: [ pkgs.qt5.qtbase ];
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





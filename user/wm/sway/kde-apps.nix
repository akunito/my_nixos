{ pkgs, ... }:

{
  # KDE companion apps and MIME associations for Sway session
  #
  # When running Sway without Plasma 6, Dolphin's "Choose Application" dialog
  # is empty because kservice (Plasma's MIME handler) is not running.
  # This module installs KDE apps and sets XDG MIME defaults so files open
  # correctly from Dolphin and other file pickers.

  home.packages = with pkgs.kdePackages; [
    gwenview     # Image viewer
    kolourpaint  # Paint-like image editor
    ark          # Archive manager
    okular       # PDF/document viewer
    kate         # Text editor (for "Open With" from Dolphin)
  ];

  xdg.mimeApps.defaultApplications = {
    # Images → Gwenview
    "image/png" = "org.kde.gwenview.desktop";
    "image/jpeg" = "org.kde.gwenview.desktop";
    "image/gif" = "org.kde.gwenview.desktop";
    "image/bmp" = "org.kde.gwenview.desktop";
    "image/svg+xml" = "org.kde.gwenview.desktop";
    "image/webp" = "org.kde.gwenview.desktop";
    "image/tiff" = "org.kde.gwenview.desktop";
    "image/avif" = "org.kde.gwenview.desktop";
    "image/heif" = "org.kde.gwenview.desktop";
    "image/x-icon" = "org.kde.gwenview.desktop";

    # PDF / Documents → Okular
    "application/pdf" = "okularApplication_pdf.desktop";
    "application/epub+zip" = "okularApplication_epub.desktop";

    # Archives → Ark
    "application/zip" = "org.kde.ark.desktop";
    "application/x-tar" = "org.kde.ark.desktop";
    "application/x-compressed-tar" = "org.kde.ark.desktop";
    "application/x-bzip2-compressed-tar" = "org.kde.ark.desktop";
    "application/x-xz-compressed-tar" = "org.kde.ark.desktop";
    "application/x-zstd-compressed-tar" = "org.kde.ark.desktop";
    "application/x-7z-compressed" = "org.kde.ark.desktop";
    "application/vnd.rar" = "org.kde.ark.desktop";
    "application/gzip" = "org.kde.ark.desktop";
    "application/x-xz" = "org.kde.ark.desktop";
    "application/zstd" = "org.kde.ark.desktop";

    # Video → VLC (already installed via user-basic-pkgs)
    "video/mp4" = "vlc.desktop";
    "video/x-matroska" = "vlc.desktop";
    "video/webm" = "vlc.desktop";
    "video/x-msvideo" = "vlc.desktop";
    "video/mpeg" = "vlc.desktop";
    "video/quicktime" = "vlc.desktop";
    "video/x-flv" = "vlc.desktop";
    "video/ogg" = "vlc.desktop";

    # Audio → VLC (already installed via user-basic-pkgs)
    "audio/mpeg" = "vlc.desktop";
    "audio/flac" = "vlc.desktop";
    "audio/ogg" = "vlc.desktop";
    "audio/x-wav" = "vlc.desktop";
    "audio/opus" = "vlc.desktop";
    "audio/aac" = "vlc.desktop";
    "audio/x-vorbis+ogg" = "vlc.desktop";
    "audio/mp4" = "vlc.desktop";
    "audio/webm" = "vlc.desktop";

    # Text / Code → Kate
    "text/plain" = "org.kde.kate.desktop";
    "text/x-python" = "org.kde.kate.desktop";
    "text/x-shellscript" = "org.kde.kate.desktop";
    "text/xml" = "org.kde.kate.desktop";
    "text/markdown" = "org.kde.kate.desktop";
    "text/x-nix" = "org.kde.kate.desktop";
    "text/x-c" = "org.kde.kate.desktop";
    "text/x-c++src" = "org.kde.kate.desktop";
    "text/x-java" = "org.kde.kate.desktop";
    "text/x-rust" = "org.kde.kate.desktop";
    "text/css" = "org.kde.kate.desktop";
    "text/javascript" = "org.kde.kate.desktop";
    "application/json" = "org.kde.kate.desktop";
    "application/x-yaml" = "org.kde.kate.desktop";
    "application/toml" = "org.kde.kate.desktop";
    "application/xml" = "org.kde.kate.desktop";
  };
}

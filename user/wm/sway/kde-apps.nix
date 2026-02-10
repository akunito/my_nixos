{ pkgs, lib, systemSettings, userSettings, ... }:

{
  # KDE companion apps and MIME associations for Sway session
  #
  # When running Sway without Plasma 6, Dolphin's "Choose Application" dialog
  # is empty because kservice's ksycoca6 cache is never built.
  # This module installs KDE apps, sets XDG MIME defaults, and rebuilds the
  # ksycoca6 cache so Dolphin can discover applications.

  home.packages = with pkgs.kdePackages; [
    gwenview     # Image viewer
    kolourpaint  # Paint-like image editor
    ark          # Archive manager
    okular       # PDF/document viewer
    kate         # Text editor (for "Open With" from Dolphin)
  ];

  # Force dark mode for viewer apps (fixes Gwenview/Okular light mode issue)
  # These apps have KDE Framework-specific color scheme resolution that may not
  # respect qt6ct/kdeglobals properly without explicit ColorScheme setting.
  # We use an activation script to add ColorScheme to [General] section if missing.
  home.activation.setKdeAppColorScheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    # Only run when Sway is enabled (either as primary WM or alongside Plasma)
    if [ "${toString (systemSettings.enableSwayForDESK or false)}" = "true" ] || [ "${toString (userSettings.wm == "sway")}" = "true" ]; then
      # Function to add ColorScheme to [General] section if not present
      add_color_scheme() {
        local config_file="$1"

        # Create file with [General] section if it doesn't exist
        if [ ! -f "$config_file" ]; then
          echo "[General]" > "$config_file"
          echo "ColorScheme=BreezeDark" >> "$config_file"
          echo "Added ColorScheme to new $config_file"
          return
        fi

        # Check if ColorScheme is already set
        if grep -q "^ColorScheme=" "$config_file"; then
          echo "ColorScheme already set in $config_file"
          return
        fi

        # Check if [General] section exists
        if grep -q "^\[General\]" "$config_file"; then
          # Add ColorScheme right after [General] line
          ${pkgs.gnused}/bin/sed -i '/^\[General\]/a ColorScheme=BreezeDark' "$config_file"
          echo "Added ColorScheme to existing [General] in $config_file"
        else
          # Prepend [General] section with ColorScheme
          echo -e "[General]\nColorScheme=BreezeDark\n$(cat "$config_file")" > "$config_file"
          echo "Added [General] section with ColorScheme to $config_file"
        fi
      }

      # Apply to Gwenview and Okular
      add_color_scheme "$HOME/.config/gwenviewrc"
      add_color_scheme "$HOME/.config/okularrc"
    fi
  '';

  # Append MIME associations to kdeglobals after Stylix creates it.
  # Stylix creates kdeglobals for Qt theming via .source (template), so we can't use .text to merge.
  # Instead, append [Added Associations] section during activation.
  # Dolphin reads [Added Associations] from kdeglobals to populate "Choose Application" dialog.
  home.activation.appendKdeglobalsMimeAssociations = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    KDEGLOBALS="$HOME/.config/kdeglobals"

    if [ -f "$KDEGLOBALS" ]; then
      # If it's a symlink (Stylix creates symlinks to Nix store), copy it to a real file
      if [ -L "$KDEGLOBALS" ]; then
        TEMP=$(mktemp)
        cp -L "$KDEGLOBALS" "$TEMP"
        rm "$KDEGLOBALS"
        mv "$TEMP" "$KDEGLOBALS"
      fi

      # Only append if [Added Associations] section doesn't exist yet
      if ! grep -q "^\[Added Associations\]" "$KDEGLOBALS"; then
        cat >> "$KDEGLOBALS" << 'EOF'

[Added Associations]
image/png=org.kde.gwenview.desktop;
image/jpeg=org.kde.gwenview.desktop;
image/gif=org.kde.gwenview.desktop;
image/bmp=org.kde.gwenview.desktop;
image/svg+xml=org.kde.gwenview.desktop;
image/webp=org.kde.gwenview.desktop;
image/tiff=org.kde.gwenview.desktop;
image/avif=org.kde.gwenview.desktop;
image/heif=org.kde.gwenview.desktop;
image/x-icon=org.kde.gwenview.desktop;
application/pdf=okularApplication_pdf.desktop;
application/epub+zip=okularApplication_epub.desktop;
application/zip=org.kde.ark.desktop;
application/x-tar=org.kde.ark.desktop;
application/x-compressed-tar=org.kde.ark.desktop;
application/x-bzip2-compressed-tar=org.kde.ark.desktop;
application/x-xz-compressed-tar=org.kde.ark.desktop;
application/x-zstd-compressed-tar=org.kde.ark.desktop;
application/x-7z-compressed=org.kde.ark.desktop;
application/vnd.rar=org.kde.ark.desktop;
application/gzip=org.kde.ark.desktop;
application/x-xz=org.kde.ark.desktop;
application/zstd=org.kde.ark.desktop;
video/mp4=vlc.desktop;
video/x-matroska=vlc.desktop;
video/webm=vlc.desktop;
video/x-msvideo=vlc.desktop;
video/mpeg=vlc.desktop;
video/quicktime=vlc.desktop;
video/x-flv=vlc.desktop;
video/ogg=vlc.desktop;
audio/mpeg=vlc.desktop;
audio/flac=vlc.desktop;
audio/ogg=vlc.desktop;
audio/x-wav=vlc.desktop;
audio/opus=vlc.desktop;
audio/aac=vlc.desktop;
audio/x-vorbis+ogg=vlc.desktop;
audio/mp4=vlc.desktop;
audio/webm=vlc.desktop;
text/plain=org.kde.kate.desktop;
text/x-python=org.kde.kate.desktop;
text/x-shellscript=org.kde.kate.desktop;
text/xml=org.kde.kate.desktop;
text/markdown=org.kde.kate.desktop;
text/x-nix=org.kde.kate.desktop;
text/x-c=org.kde.kate.desktop;
text/x-c++src=org.kde.kate.desktop;
text/x-java=org.kde.kate.desktop;
text/x-rust=org.kde.kate.desktop;
text/css=org.kde.kate.desktop;
text/javascript=org.kde.kate.desktop;
application/json=org.kde.kate.desktop;
application/x-yaml=org.kde.kate.desktop;
application/toml=org.kde.kate.desktop;
application/xml=org.kde.kate.desktop;
EOF
      fi
    fi
  '';

  # Rebuild desktop database and KDE service cache after Home Manager activation.
  # Without Plasma 6, Dolphin's "Choose Application" dialog is empty.
  # We need both update-desktop-database (freedesktop) and kbuildsycoca6 (KDE).
  # NOTE: xdg.mimeApps creates writable mimeapps.list by default, so we don't need
  # the makesMimeappsWritable activation script anymore.
  home.activation.rebuildDesktopDatabase = lib.hm.dag.entryAfter [ "appendKdeglobalsMimeAssociations" ] ''
    # Update freedesktop.org desktop database
    ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

    # Rebuild KDE service cache
    ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental 2>/dev/null || true
  '';

  # Populate both [Default Applications] and [Added Associations] sections.
  # Dolphin reads [Added Associations] to populate "Choose Application" dialog.
  # When you click "Remember", Dolphin writes to [Added Associations].
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
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

    # Also populate [Added Associations] section (this is what Dolphin reads/writes)
    associations.added = {
    # Images
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

    # PDFs
    "application/pdf" = "okularApplication_pdf.desktop";
    "application/epub+zip" = "okularApplication_epub.desktop";

    # Archives
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

    # Video
    "video/mp4" = "vlc.desktop";
    "video/x-matroska" = "vlc.desktop";
    "video/webm" = "vlc.desktop";
    "video/x-msvideo" = "vlc.desktop";
    "video/mpeg" = "vlc.desktop";
    "video/quicktime" = "vlc.desktop";
    "video/x-flv" = "vlc.desktop";
    "video/ogg" = "vlc.desktop";

    # Audio
    "audio/mpeg" = "vlc.desktop";
    "audio/flac" = "vlc.desktop";
    "audio/ogg" = "vlc.desktop";
    "audio/x-wav" = "vlc.desktop";
    "audio/opus" = "vlc.desktop";
    "audio/aac" = "vlc.desktop";
    "audio/x-vorbis+ogg" = "vlc.desktop";
    "audio/mp4" = "vlc.desktop";
    "audio/webm" = "vlc.desktop";

    # Text
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
  };
}

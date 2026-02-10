{ pkgs, lib, systemSettings, userSettings, ... }:

{
  # KDE companion apps, Wayland-native viewers, and MIME associations for Sway session.
  # Loupe (GTK4/libadwaita) is the default image viewer - auto dark mode via dconf.
  # Swayimg is available as a lightweight Sway-native alternative.
  # Gwenview is kept as a KDE alternative (dark mode via breeze + setKdeAppColorScheme).

  home.packages = with pkgs.kdePackages; [
    gwenview     # Image viewer (KDE - kept as alternative)
    kolourpaint  # Paint-like image editor
    ark          # Archive manager
    okular       # PDF/document viewer
    kate         # Text editor (for "Open With" from file manager)
  ] ++ [
    pkgs.nemo  # File manager (GTK, no KDE deps, Dolphin replacement)
    pkgs.loupe   # GNOME image viewer (GTK4/libadwaita, auto dark mode via dconf)
    pkgs.swayimg # Sway-native image viewer (keyboard-driven, lightweight)
  ];

  # Nemo tree view: enable expandable folders in list view
  dconf.settings = {
    "org/nemo/list-view" = {
      use-tree-view = true;
    };
  };

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

  # XDG MIME default applications and added associations.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
    # Images → Loupe (Wayland-native, auto dark mode via libadwaita/dconf)
    "image/png" = "org.gnome.Loupe.desktop";
    "image/jpeg" = "org.gnome.Loupe.desktop";
    "image/gif" = "org.gnome.Loupe.desktop";
    "image/bmp" = "org.gnome.Loupe.desktop";
    "image/svg+xml" = "org.gnome.Loupe.desktop";
    "image/webp" = "org.gnome.Loupe.desktop";
    "image/tiff" = "org.gnome.Loupe.desktop";
    "image/avif" = "org.gnome.Loupe.desktop";
    "image/heif" = "org.gnome.Loupe.desktop";
    "image/x-icon" = "org.gnome.Loupe.desktop";

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

    # Also populate [Added Associations] section
    associations.added = {
    # Images (Loupe primary, Gwenview as alternative in "Open With")
    "image/png" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/jpeg" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/gif" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/bmp" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/svg+xml" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/webp" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/tiff" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/avif" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/heif" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];
    "image/x-icon" = [ "org.gnome.Loupe.desktop" "org.kde.gwenview.desktop" ];

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

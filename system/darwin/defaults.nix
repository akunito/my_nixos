# macOS System Defaults Configuration
# Configures Dock, Finder, Trackpad, and other macOS system preferences
# Settings are controlled by systemSettings.darwin.* options

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  darwin = systemSettings.darwin;
in
{
  # Dock configuration
  system.defaults.dock = {
    autohide = darwin.dockAutohide;
    autohide-delay = darwin.dockAutohideDelay;
    orientation = darwin.dockOrientation;
    show-recents = darwin.dockShowRecents;
    minimize-to-application = darwin.dockMinimizeToApplication;
    tilesize = darwin.dockTileSize;
    # Disable hot corners
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
  };

  # Finder configuration
  system.defaults.finder = {
    AppleShowAllExtensions = darwin.finderShowExtensions;
    AppleShowAllFiles = darwin.finderAppleShowAllFiles;
    ShowPathbar = darwin.finderShowPathBar;
    ShowStatusBar = darwin.finderShowStatusBar;
    FXPreferredViewStyle = darwin.finderDefaultViewStyle;
    # When performing a search, search the current folder by default
    FXDefaultSearchScope = "SCcf";
    # Disable the warning when changing a file extension
    FXEnableExtensionChangeWarning = false;
    # Don't create .DS_Store files on network or USB volumes
    CreateDesktop = true;
  };

  # Trackpad configuration
  system.defaults.trackpad = {
    Clicking = darwin.trackpadTapToClick;
    TrackpadRightClick = darwin.trackpadSecondaryClick;
    # Enable three finger drag
    TrackpadThreeFingerDrag = false;
  };

  # Global macOS settings
  system.defaults.NSGlobalDomain = {
    # Appearance
    AppleInterfaceStyle = if darwin.darkMode then "Dark" else null;
    AppleInterfaceStyleSwitchesAutomatically = false;

    # Scrolling
    "com.apple.swipescrolldirection" = darwin.scrollDirection;

    # Keyboard
    InitialKeyRepeat = darwin.keyboardInitialKeyRepeat;
    KeyRepeat = darwin.keyboardKeyRepeat;

    # Enable full keyboard access for all controls
    AppleKeyboardUIMode = 3;

    # Disable press-and-hold for keys in favor of key repeat
    ApplePressAndHoldEnabled = false;

    # Expand save panel by default
    NSNavPanelExpandedStateForSaveMode = true;
    NSNavPanelExpandedStateForSaveMode2 = true;

    # Expand print panel by default
    PMPrintingExpandedStateForPrint = true;
    PMPrintingExpandedStateForPrint2 = true;

    # Save to disk (not iCloud) by default
    NSDocumentSaveNewDocumentsToCloud = false;

    # Disable automatic capitalization, smart dashes, period substitution, and spell correction
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
  };

  # Login window settings
  system.defaults.loginwindow = {
    GuestEnabled = false;
    DisableConsoleAccess = true;
  };

  # Screen capture settings
  system.defaults.screencapture = {
    location = "~/Desktop";
    type = "png";
    disable-shadow = true;
  };

  # Activity Monitor settings
  system.defaults.ActivityMonitor = {
    ShowCategory = 0; # Show all processes
    IconType = 5; # Show CPU usage in Dock icon
  };

  # Note: TimeMachine settings are managed via macOS System Settings, not nix-darwin
}

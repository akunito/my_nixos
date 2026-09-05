# Base flake module
# This contains the common flake structure that all profiles share
# It accepts profile-specific config and merges with defaults
# Supports both NixOS (Linux) and nix-darwin (macOS)

{ inputs, self, profileConfig, ... }:

let
  # Get lib first (needed for recursiveUpdate)
  # We'll determine which lib to use after checking systemStable
  lib-unstable = inputs.nixpkgs.lib;
  lib-stable = inputs.nixpkgs-stable.lib;

  # Import defaults - need to use a temporary pkgs for defaults
  tempPkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
  defaults = import ./defaults.nix { pkgs = tempPkgs; };

  # Merge defaults with profile config
  # Use recursiveUpdate for nested structures, but allow complete replacement of lists
  systemSettingsRaw = lib-unstable.recursiveUpdate defaults.systemSettings (profileConfig.systemSettings or {});
  userSettingsRaw = lib-unstable.recursiveUpdate defaults.userSettings (profileConfig.userSettings or {});

  # Detect OS type - "linux" for NixOS, "darwin" for macOS
  osType = systemSettingsRaw.osType or "linux";
  isDarwin = osType == "darwin";
  isLinux = !isDarwin;

  # Handle systemStable - check both systemSettings and userSettings (for HOME profile inconsistency)
  # Also check profile name for homelab/worklab
  systemStable = systemSettingsRaw.systemStable or userSettingsRaw.systemStable or
                 ((systemSettingsRaw.profile == "homelab") || (systemSettingsRaw.profile == "worklab"));

  # Now determine which lib to use
  lib = if systemStable then lib-stable else lib-unstable;

  # Re-merge with correct lib
  systemSettings = lib.recursiveUpdate defaults.systemSettings (profileConfig.systemSettings or {});
  userSettingsMerged = lib.recursiveUpdate defaults.userSettings (profileConfig.userSettings or {});

  # Get temporary pkgs for font computation
  tempPkgsStable = import inputs.nixpkgs-stable { system = systemSettings.system; };
  tempPkgsUnstable = import inputs.nixpkgs { system = systemSettings.system; };

  # Compute fonts based on systemStable (if not overridden in profile config)
  # Check if fonts were explicitly set in profile config
  fontsFromConfig = (profileConfig.systemSettings or {}).fonts or null;
  computedFonts = if fontsFromConfig != null
                  then fontsFromConfig
                  else if systemStable
                       then [
                         tempPkgsStable.nerd-fonts.jetbrains-mono
                         tempPkgsStable.nerd-fonts.symbols-only
                         tempPkgsStable.powerline
                         tempPkgsStable.noto-fonts
                       ]
                       else [
                         tempPkgsUnstable.nerd-fonts.jetbrains-mono
                         tempPkgsUnstable.nerd-fonts.symbols-only
                         tempPkgsUnstable.powerline
                         tempPkgsUnstable.noto-fonts
                       ];

  # Compute derived userSettings values first
  userSettings = userSettingsMerged // {
    # Compute wmType from wm (for darwin, default to "quartz" which is macOS native)
    wmType = if isDarwin then "quartz"
             else if ((userSettingsMerged.wm == "hyprland") || (userSettingsMerged.wm == "plasma") || (userSettingsMerged.wm == "plasma6") || (userSettingsMerged.wm == "sway"))
             then "wayland"
             else "x11";

    # Compute spawnEditor from editor and term
    spawnEditor = if (userSettingsMerged.editor == "emacsclient") then
                    "emacsclient -c -a 'emacs'"
                  else
                    (if ((userSettingsMerged.editor == "vim") ||
                         (userSettingsMerged.editor == "nvim") ||
                         (userSettingsMerged.editor == "nano")) then
                           "exec " + userSettingsMerged.term + " -e " + userSettingsMerged.editor
                     else
                       userSettingsMerged.editor);

    # Auto-enable tmux session persistence for personal/darwin profiles using kitty.
    # Profiles can still override explicitly (profileConfig wins over the default via recursiveUpdate).
    tmuxPersistenceEnable =
      let explicit = (profileConfig.userSettings or {}).tmuxPersistenceEnable or null;
      in if explicit != null then explicit
         else (systemSettings.profile or "") == "personal" && userSettingsMerged.term == "kitty";
  };

  # Evaluate package lists if they're functions (now that userSettings is defined)
  systemPackagesEvaluatedBase = if lib.isFunction (systemSettings.systemPackages or [])
                            then systemSettings.systemPackages pkgs pkgs-unstable
                            else systemSettings.systemPackages or [];

  homePackagesEvaluated = if lib.isFunction (userSettings.homePackages or [])
                          then userSettings.homePackages pkgs pkgs-unstable
                          else userSettings.homePackages or [];

  # Set fontPkg based on font name if not already set
  fontPkgMap = {
    "Intel One Mono" = pkgs.intel-one-mono;
    "JetBrainsMono Nerd Font" = pkgs.nerd-fonts.jetbrains-mono;
    "JetBrainsMono Nerd Font Mono" = pkgs.nerd-fonts.jetbrains-mono;
    # Add more font mappings as needed
  };
  userSettingsWithFontPkg = userSettings // {
    fontPkg = userSettings.fontPkg or fontPkgMap.${userSettings.font} or pkgs.intel-one-mono;
    homePackages = homePackagesEvaluated;
  };

  # Handle background-package if it references assets (Linux only)
  # If background-package is a path or needs self, we'll compute it here
  backgroundPackage = if isDarwin then null
                      else if systemSettings ? background-package && lib.isString systemSettings.background-package
                      then systemSettings.background-package
                      else if systemSettings ? background-package
                           then systemSettings.background-package
                           else pkgs.stdenvNoCC.mkDerivation {
                                name = "background-image";
                                src = self + "/assets/wallpapers";
                                dontUnpack = true;
                                installPhase = ''
                                  cp $src/fuji.jpg $out
                                '';
                              };

  # Add SDDM theme override if using plasma6 (which uses SDDM) - Linux only
  # This needs to be done after backgroundPackage is computed.
  #
  # SDDM theme configuration (controlled by feature flags)
  # - sddmForcePasswordFocus: Force password field focus (fixes multi-monitor focus issues)
  # - Keep the background image (Breeze "dark mode" via solid color was too aggressive)
  sddmThemeConfig = if isLinux && systemSettings.sddmForcePasswordFocus
    then ''
      [General]
      background = ${toString backgroundPackage}
      ForcePasswordFocus=true
    ''
    else if isLinux then ''
      [General]
      background = ${toString backgroundPackage}
    ''
    else "";

  systemPackagesEvaluated = systemPackagesEvaluatedBase ++
    lib.optional (isLinux && systemSettings.sddmBreezePatchedTheme or false) (
      pkgs.writeTextDir "share/sddm/themes/breeze-patched/theme.conf.user" sddmThemeConfig
    );

  systemSettingsWithFonts = systemSettings // {
    fonts = computedFonts;
    systemPackages = systemPackagesEvaluated;
    background-package = backgroundPackage;
  };

  # Create patched nixpkgs (Linux only - darwin doesn't need ROCm patches)
  # Note: Original code used systemSettings.gpu but field is actually gpuType
  nixpkgs-patched = if isDarwin then inputs.nixpkgs
    else (import inputs.nixpkgs {
      system = systemSettingsWithFonts.system;
      rocmSupport = (if (systemSettingsWithFonts.gpuType or "") == "amd" then true else false);
    }).applyPatches {
      name = "nixpkgs-patched";
      src = inputs.nixpkgs;
      patches = [
        # ./patches/emacs-no-version-check.patch
        # ./patches/nixpkgs-348697.patch
      ];
    };

  # NOTE — REMOVED: noOpenldapTestsOverlay / noPatoolTestsOverlay (2026-08-22).
  #
  # Both disabled a flaky test suite with `doCheck = false`. That looks free but
  # is not: overriding a derivation changes its hash, so the result is no longer
  # the one Hydra built and cache.nixos.org has. openldap is a dependency of
  # gnupg, so the override forced a from-source rebuild of the ENTIRE reverse
  # closure on every machine, every update:
  #
  #   openldap -> gnupg -> gpgme -> gpgmepp -> kwallet -> kio
  #                     -> gcr -> gnome-keyring -> bitwarden-desktop
  #                     -> thunderbird / nextcloud-client / git-crypt
  #
  # Measured on LAPTOP_A 2026-08-22: 614 of 664 paths came from cache.nixos.org;
  # the ~50 that did not were this closure, and they pinned 8 cores for hours.
  # DESK had built the same overridden openldap locally two days earlier.
  #
  # The overrides were also self-perpetuating: a package is only test-run when
  # it is built locally, and the override is what forced the local build. With
  # stock derivations the tests never execute here at all — Hydra already ran
  # them. Upstream additionally deletes the cited flaky test itself: openldap's
  # preCheck does `rm -f tests/scripts/test*-sync*`, which covers
  # test017-syncreplication-refresh.
  #
  # If Hydra lag ever forces a local openldap/patool build again and the tests
  # fail, re-add the override TEMPORARILY and drop it once the cache catches up.

  # SwayFX 0.5.3 SEGFAULTs the whole compositor in view_autoconfigure when a
  # client (gamescope running a fullscreen game, e.g. Metro Exodus) commits a
  # fullscreen-workspace surface before its workspace has an output assigned
  # (ws->output == NULL). Fixed upstream by PR #478 ("view: check for NULL output
  # on autoconfigure"), on master but NOT in any tagged release. Applied as an
  # overlay on swayfx-unwrapped so every `pkgs.swayfx` (system programs.sway AND
  # Home Manager wayland.windowManager.sway — the latter is what SDDM actually
  # launches) picks it up. Added to BOTH pkgs-stable and the nixpkgs-patched
  # branch below, since a profile's `pkgs` is one or the other by systemStable.
  #
  # ‼️ THE BUG IS NOT SWAYFX'S — SwayFX inherited it, and so does upstream sway.
  # Verified 2026-09-02 against sway 1.11's own sway/tree/view.c: it computes
  # `output = ws ? ws->output : NULL` and then dereferences `output->lx` in the
  # FULLSCREEN_WORKSPACE branch with no further check, byte for byte the same as
  # the SwayFX code that crashed. So a profile with swayUseSwayfx = false would
  # walk straight back into the Metro Exodus session-killer if only swayfx were
  # patched. The fix is a one-line guard and its hunk context is identical in
  # both trees, so the SAME patch file is applied to both packages.
  swayNullOutputCrashFix = super: super.fetchpatch {
    name = "sway-478-null-output-autoconfigure.patch";
    url = "https://github.com/WillPower3309/swayfx/commit/a6ea43430eac3a104b688906c7f09a80242d4782.patch";
    hash = "sha256-oxpDQxRIc6QKeTd0fvEoWPbMcklS1bM7EUedB/2e3cc=";
  };
  swayfxNullOutputCrashFixOverlay = _: super: {
    swayfx-unwrapped = super.swayfx-unwrapped.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ (swayNullOutputCrashFix super) ];
    });
    sway-unwrapped = super.sway-unwrapped.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ (swayNullOutputCrashFix super) ];
    });
  };

  # Waybar rejects Electron 43.3+ tray icons as "Invalid Status Notifier Item".
  #
  # Electron >= 43.3 registers its item under a WELL-KNOWN bus name
  # (org.freedesktop.StatusNotifierItem-PID-N) instead of the unique connection
  # name, and answers property requests only on that name. Waybar's watcher does
  # not parse the combined "bus_name/object_path" string it now receives, so the
  # item never reaches the bar. Diagnosed here 2026-09-02 by swapping ONLY the
  # runtime under vesktop: electron 42.7.1 registers instantly, 43.4.1 never
  # appears. Trayscale publishes the same well-known-name shape and fails the
  # same way, so this is one bug, not two.
  #
  # Upstream fix: Alexays/Waybar PR #5287, OPEN as of 2026-09-02. Six lines in
  # src/modules/sni/watcher.cpp. Pinned to the COMMIT, not the PR head, so a
  # force-push cannot silently change what we build.
  #
  # WHY A PATCH AND NOT A PIN. Chosen deliberately: when waybar merges this, the
  # patch stops applying and the build FAILS LOUDLY — which is the signal to
  # delete this block. A version pin would keep working forever while quietly
  # going stale, and nothing would ever tell us the moment to remove it.
  #
  # Cost: waybar is built from source instead of fetched from cache. Its reverse
  # closure is empty (nothing depends on waybar), so this rebuilds one package
  # and no more — unlike the doCheck override removed from this file in Aug 2026.
  waybarElectronTrayFixOverlay = _: super: {
    waybar = super.waybar.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (super.fetchpatch {
          name = "waybar-5287-electron-combined-sni-name.patch";
          url = "https://github.com/Alexays/Waybar/commit/bcb91b772f527e54233ea4821b704bf5111b4c32.patch";
          hash = "sha256-BjgRfO/nN52HzomEavaiqQJ9BZrOTX16+S2WKeuckPU=";
        })
      ];
    });
  };

  # gamescope's Wayland backend crashes the game it hosts when its window is
  # briefly left with nothing to present (Black Desert's launcher chain:
  # Launcher -> PALauncher -> game window). CWaylandPlane::Present( nullopt )
  # attaches a NULL buffer to the PRIMARY surface, which unmaps its
  # xdg_toplevel; xdg-shell then requires a fresh configure/ack cycle before
  # the next attach, which gamescope never performs. Whether the next
  # Present() beats the compositor's configure is a race — that is the
  # intermittency. When it loses, sway kills the connection with
  #
  #   xdg_surface#50: "xdg_surface has never been configured"
  #
  # and gamescope's input thread aborts (SIGABRT, rc=134), reaping the game
  # ~10s into launch. Diagnosed 2026-09-05 from WAYLAND_DEBUG captures (three
  # identical deaths); code identical in 3.16.17, 3.16.28 and master as of
  # 2026-09-03, so a version bump cannot fix it. The patch keeps the last
  # frame on screen instead of unmapping (overlay subplanes have no xdg role
  # and still hide via the null attach). Local patch file — no upstream PR to
  # pin. Applies to both stable and unstable gamescope; the hunk drifting is
  # the signal to re-check upstream.
  gamescopeRemapCrashFixOverlay = _: super: {
    gamescope = super.gamescope.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/gamescope-wayland-remap-crash.patch ];
    });
  };

  # Configure pkgs-stable
  pkgs-stable = import inputs.nixpkgs-stable {
    system = systemSettingsWithFonts.system;
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
      # Allow insecure packages needed by some profiles (olm for Matrix E2E)
      permittedInsecurePackages = [
        "olm-3.2.16"
      ];
    };
    # swayfx #478 crash fix — DESK is systemStable=true, so its `pkgs` (and thus
    # the Home Manager compositor via homeConfigurations `inherit pkgs`) is
    # pkgs-stable. The overlay must live here too, not only on the unstable branch.
    overlays = [ swayfxNullOutputCrashFixOverlay waybarElectronTrayFixOverlay gamescopeRemapCrashFixOverlay ];
  };

  # Configure pkgs-unstable
  # Check if rust-overlay should be used (from profile config or default to false)
  useRustOverlay = profileConfig.useRustOverlay or false;
  rustOverlay = if useRustOverlay && (inputs ? rust-overlay)
                then inputs.rust-overlay.overlays.default
                else (_: _: {});
  pkgs-unstable = import inputs.nixpkgs {
    system = systemSettingsWithFonts.system;
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
      permittedInsecurePackages = [
        "olm-3.2.16"
        # bitwarden-desktop-2026.5.0 still bundles electron 39 (EOL upstream).
        # Allow until nixpkgs ships a bitwarden-desktop on a maintained Electron.
        "electron-39.8.10"
        # pnpm-10.29.2 is a build-time-only tool for vesktop (JS/Electron app);
        # flagged insecure upstream (CVE-2026-48995 et al.). Not shipped at
        # runtime. Allow until nixpkgs-unstable bumps vesktop's pnpm.
        "pnpm-10.29.2"
      ];
    };
    overlays = lib.optional useRustOverlay rustOverlay;
  };

  # Configure pkgs based on systemStable and profile
  pkgs = if systemStable
         then
           pkgs-stable
         else if isDarwin
         then
           (import inputs.nixpkgs {
             system = systemSettingsWithFonts.system;
             config = {
               allowUnfree = true;
               allowUnfreePredicate = (_: true);
             };
             overlays = lib.optional useRustOverlay rustOverlay;
           })
         else
           (import nixpkgs-patched {
             system = systemSettingsWithFonts.system;
             config = {
               allowUnfree = true;
               allowUnfreePredicate = (_: true);
             };
             overlays = (lib.optional useRustOverlay rustOverlay) ++ [ swayfxNullOutputCrashFixOverlay waybarElectronTrayFixOverlay gamescopeRemapCrashFixOverlay ];
           });

  # Configure home-manager
  home-manager = if systemStable
                 then
                   inputs.home-manager-stable
                 else
                   inputs.home-manager-unstable;

  # Systems that can run tests (includes both Linux and Darwin)
  supportedLinuxSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];
  supportedDarwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
  supportedSystems = supportedLinuxSystems ++ supportedDarwinSystems;

  # Function to generate a set based on supported systems
  forAllSystems = lib-unstable.genAttrs supportedSystems;
  forLinuxSystems = lib-unstable.genAttrs supportedLinuxSystems;

  # Attribute set of nixpkgs for each system
  nixpkgsFor = forAllSystems (system: import inputs.nixpkgs { inherit system; });

  # Darwin-specific configuration
  darwinConfiguration = if isDarwin && (inputs ? darwin) then {
    darwinConfigurations = {
      system = inputs.darwin.lib.darwinSystem {
        system = systemSettingsWithFonts.system;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/configuration.nix")
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-hm";
            home-manager.extraSpecialArgs = {
              inherit pkgs-stable;
              inherit pkgs-unstable;
              systemSettings = systemSettingsWithFonts;
              userSettings = userSettingsWithFontPkg;
              inherit inputs;
            };
            home-manager.users.${userSettingsWithFontPkg.username} = import (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/home.nix");
          }
        ];
        specialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  } else {};

  # NixOS-specific configuration
  nixosConfiguration = if isLinux then {
    nixosConfigurations = {
      system = lib.nixosSystem {
        system = systemSettingsWithFonts.system;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/configuration.nix")
          (self + "/system/bin/aku.nix")
          # Refuses to build a generation whose fileSystems carry Docker overlay
          # mounts (the emergency-mode brick). Applied to every profile on
          # purpose — script-level guards only cover the install.sh path.
          (self + "/system/security/hwconfig-guard.nix")
          # ‼️ lib.nixosSystem instantiates its OWN nixpkgs — flake-base's
          # pkgs-stable/pkgs-unstable (and their overlays) only feed Home
          # Manager and specialArgs. Verified 2026-09-05: with the gamescope
          # patch overlay only on pkgs-stable, the deployed system's gamescope
          # still came from cache.nixos.org unpatched, because
          # programs.steam.extraPackages resolves through the module system's
          # pkgs. Any overlay that must reach SYSTEM-level packages (Steam's
          # FHS, environment.systemPackages) has to be injected here.
          { nixpkgs.overlays = [ gamescopeRemapCrashFixOverlay ]; }
        ];
        specialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  } else {};

  # Home configurations (always generated, but path differs slightly for darwin)
  homeConfiguration = {
    homeConfigurations = {
      user = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/home.nix")
        ];
        extraSpecialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  };

in
  # Merge all configurations
  homeConfiguration
  // nixosConfiguration
  // darwinConfiguration
  // {
    packages = forAllSystems (system:
      let pkgs = nixpkgsFor.${system};
      in {
        default = self.packages.${system}.install;

        install = pkgs.writeShellApplication {
          name = "install";
          runtimeInputs = with pkgs; [ git ];
          text = ''${self}/install.sh "$@"'';
        };
      });

    apps = forAllSystems (system: {
      default = self.apps.${system}.install;

      install = {
        type = "app";
        program = "${self.packages.${system}.install}/bin/install";
      };
    });
  }

{ config, pkgs, lib, userSettings, systemSettings, ... }:

{
  # Btop theme configuration (Stylix colors)
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  home.file.".config/btop/btop.conf" =
    lib.mkIf (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
      text = ''
        # Btop Configuration
        # Theme matching Stylix colors

        theme_background = "#${config.lib.stylix.colors.base00}"
        theme_text = "#${config.lib.stylix.colors.base07}"
        theme_title = "#${config.lib.stylix.colors.base0D}"
        theme_hi_fg = "#${config.lib.stylix.colors.base0A}"
        theme_selected_bg = "#${config.lib.stylix.colors.base0D}"
        theme_selected_fg = "#${config.lib.stylix.colors.base07}"
        theme_cpu_box = "#${config.lib.stylix.colors.base0B}"
        theme_mem_box = "#${config.lib.stylix.colors.base0E}"
        theme_net_box = "#${config.lib.stylix.colors.base0C}"
        theme_proc_box = "#${config.lib.stylix.colors.base09}"
      '';
    };

  # Libinput-gestures configuration for SwayFX
  # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
  # Uses next_on_output/prev_on_output to prevent gestures from jumping between monitors
  xdg.configFile."libinput-gestures.conf".text = ''
    # Libinput-gestures configuration for SwayFX
    # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)

    gesture swipe left 3 ${pkgs.swayfx}/bin/swaymsg workspace next_on_output
    gesture swipe right 3 ${pkgs.swayfx}/bin/swaymsg workspace prev_on_output
    # Optional: 3-finger swipe up for fullscreen toggle
    # gesture swipe up 3 ${pkgs.swayfx}/bin/swaymsg fullscreen toggle
  '';

  # Swappy configuration (screenshot editor) - managed by Home Manager
  # Stylix integration: use Stylix font + accent color when available.
  xdg.configFile."swappy/config".text =
    let
      stylixAvailable =
        systemSettings.stylixEnable == true
        && (config ? stylix)
        && (config.stylix ? fonts)
        && (config ? lib)
        && (config.lib ? stylix)
        && (config.lib.stylix ? colors);

      # Convert 6-digit hex ("rrggbb") to rgba(r,g,b,1)
      # We keep alpha fixed at 1 because Swappy expects a single default color.
      hexToRgbaSolid = hex:
        let
          hexDigitToDec = d:
            if d == "0" then 0
            else if d == "1" then 1
            else if d == "2" then 2
            else if d == "3" then 3
            else if d == "4" then 4
            else if d == "5" then 5
            else if d == "6" then 6
            else if d == "7" then 7
            else if d == "8" then 8
            else if d == "9" then 9
            else if d == "a" || d == "A" then 10
            else if d == "b" || d == "B" then 11
            else if d == "c" || d == "C" then 12
            else if d == "d" || d == "D" then 13
            else if d == "e" || d == "E" then 14
            else if d == "f" || d == "F" then 15
            else 0;
          hexToDec = hexStr:
            let
              d1 = builtins.substring 0 1 hexStr;
              d2 = builtins.substring 1 1 hexStr;
            in
              hexDigitToDec d1 * 16 + hexDigitToDec d2;
          r = hexToDec (builtins.substring 0 2 hex);
          g = hexToDec (builtins.substring 2 2 hex);
          b = hexToDec (builtins.substring 4 2 hex);
        in
          "rgba(${toString r}, ${toString g}, ${toString b}, 1)";

      saveDir = "${config.home.homeDirectory}/Pictures/Screenshots";
      fontName = if stylixAvailable then config.stylix.fonts.sansSerif.name else "JetBrainsMono Nerd Font";
      accentHex = if stylixAvailable then config.lib.stylix.colors.base0D else "268bd2";
    in
      lib.generators.toINI { } {
        Default = {
          save_dir = saveDir;
          save_filename_format = "swappy-%Y%m%d-%H%M%S.png";
          show_panel = false;
          line_size = 5;
          text_size = 20;
          text_font = fontName;
          custom_color = hexToRgbaSolid accentHex;
        };
      };

  # Ensure the default screenshots directory exists (used by Swappy save_dir).
  home.activation.ensureScreenshotsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/Pictures/Screenshots" || true
  '';

  # Install scripts to .config/sway/scripts/
  home.file.".config/sway/scripts/screenshot.sh" = {
    source = ./scripts/screenshot.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/ssh-smart.sh" = {
    source = ./scripts/ssh-smart.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/app-toggle.sh" = {
    source = ./scripts/app-toggle.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/window-move.sh" = {
    source = ./scripts/window-move.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/window-overview-grouped.sh" = {
    source = ./scripts/window-overview-grouped.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/rofi-power-mode.sh" = {
    source = ./scripts/rofi-power-mode.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/rofi-power-launch.sh" = {
    source = ./scripts/rofi-power-launch.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-perf.sh" = {
    source = ./scripts/waybar-perf.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-metrics.sh" = {
    source = ./scripts/waybar-metrics.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-mic.sh" = {
    source = ./scripts/waybar-mic.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-gpu-tool.sh" = {
    source = ./scripts/waybar-gpu-tool.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-flatpak-updates.sh" = {
    source = ./scripts/waybar-flatpak-updates.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-notifications.sh" = {
    source = ./scripts/waybar-notifications.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-vpn-wg-client.sh" = {
    source = ./scripts/waybar-vpn-wg-client.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/waybar-nixos-update.sh" = {
    source = ./scripts/waybar-nixos-update.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/idle-inhibit-status.sh" = {
    source = ./scripts/idle-inhibit-status.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/idle-inhibit-toggle.sh" = {
    source = ./scripts/idle-inhibit-toggle.sh;
    executable = true;
  };


  home.file.".config/sway/scripts/swaysome-assign-groups.sh" = {
    source = ./scripts/swaysome-assign-groups.sh;
    executable = true;
  };

  # DESK workspace assignment script with Nix path interpolation
  # CRITICAL: Uses ${pkgs.jq}/bin/jq and ${pkgs.sway}/bin/swaymsg for strict NixOS compatibility
  home.file.".config/sway/scripts/swaysome-pin-groups-desk.sh" = lib.mkIf (systemSettings.enableSwayForDESK == true) {
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # DESK-only: Pin output -> swaysome group mapping deterministically by hardware ID.
      # Goal:
      # - Samsung  -> group 1 (11-20)
      # - NSL      -> group 2 (21-30)
      # - Philips  -> group 3 (31-40)
      # - BNQ      -> group 4 (41-50)

      # CRITICAL: Use Nix-interpolated paths (strict NixOS compatibility)
      SWAYMSG_BIN="${pkgs.sway}/bin/swaymsg"
      JQ_BIN="${pkgs.jq}/bin/jq"
      SWAYSOME_BIN="${pkgs.swaysome}/bin/swaysome"

      [ -n "$SWAYMSG_BIN" ] || exit 0
      [ -n "$JQ_BIN" ] || exit 0
      [ -n "$SWAYSOME_BIN" ] || exit 0

      # Hardware IDs (exact matches from swaymsg -t get_outputs)
      SAMSUNG="Samsung Electric Company Odyssey G70NC H1AK500000"
      NSL="NSL RGB-27QHDS    Unknown"
      PHILIPS="Philips Consumer Electronics Company PHILIPS FTV 0x01010101"
      BNQ="BNQ ZOWIE XL LCD 7CK03588SL0"

      # Expected output names (extracted from DESK-config.nix/kanshi)
      # These are the actual output names Sway assigns based on hardware
      EXPECTED_OUTPUTS=("DP-1" "DP-2" "HDMI-A-1" "DP-3")

      # Lock file for signaling completion
      LOCK_FILE="/tmp/sway-workspaces-ready.lock"

      # Cleanup function for lock file
      cleanup() {
        rm -f "$LOCK_FILE"
      }
      trap cleanup EXIT INT TERM
      rm -f "$LOCK_FILE"  # Remove stale lock at start

      # Instrumentation: Log execution context and timing
      LOG_FILE="/tmp/sway-workspace-assignment.log"
      echo "=== DESK WORKSPACE ASSIGNMENT START ===" >> "$LOG_FILE"
      echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
      echo "PID: $$" >> "$LOG_FILE"
      echo "Called from: ''${0}" >> "$LOG_FILE"
      echo "Arguments: $*" >> "$LOG_FILE"

      # Save original focused workspace
      ORIGINAL_FOCUSED_WS=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' 2>/dev/null || echo "")
      echo "Original focused workspace: $ORIGINAL_FOCUSED_WS" >> "$LOG_FILE"

      # Log current workspace state before any changes
      echo "=== PRE-ASSIGNMENT STATE ===" >> "$LOG_FILE"
      $SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | "Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$LOG_FILE" 2>&1 || echo "Failed to get workspace state" >> "$LOG_FILE"

      # Log monitor state
      echo "=== MONITOR STATE ===" >> "$LOG_FILE"
      $SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r '.[] | select(.active==true) | "\(.name): \(.make) \(.model) \(.serial) -> \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz"' >> "$LOG_FILE" 2>&1 || echo "Failed to get monitor state" >> "$LOG_FILE"

      echo "DESK: Starting hardware-ID-based workspace initialization..." >&2
      echo "DESK: Starting hardware-ID-based workspace initialization..." >> "$LOG_FILE"

      # Wait for kanshi to stabilize (poll for specific expected outputs)
      wait_for_kanshi_stability() {
        local timeout=15
        local elapsed=0
        echo "Waiting for kanshi to configure all expected outputs..." >> "$LOG_FILE"
        while [ $elapsed -lt $timeout ]; do
          local all_present=true
          for output in "''${EXPECTED_OUTPUTS[@]}"; do
            if ! $SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -e --arg name "$output" '.[] | select(.name==$name and .active==true)' >/dev/null 2>&1; then
              all_present=false
              break
            fi
          done
          if [ "$all_present" = true ]; then
            echo "All expected outputs are active" >> "$LOG_FILE"
            return 0
          fi
          sleep 0.5
          elapsed=$((elapsed + 1))
        done
        echo "WARNING: Timeout waiting for all expected outputs after ''${timeout}s" >&2
        echo "WARNING: Timeout waiting for all expected outputs after ''${timeout}s" >> "$LOG_FILE"
        return 1
      }

      # Function to get output name by hardware ID
      get_output_by_hwid() {
        local hwid="$1"
        local result
        result=$($SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r --arg hwid "$hwid" '
          .[] | select(.active==true) | select((.make + " " + .model + " " + .serial) == $hwid) | .name
        ' | head -n1)
        echo "Hardware ID lookup: '$hwid' -> '$result'" >> "$LOG_FILE"
        echo "$result"
      }

      # Collision-safe workspace renumbering
      renumber_workspace_safe() {
        local source_ws="$1"
        local target_ws="$2"
        local output="$3"
        
        # Check if target exists
        if $SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -e --arg name "$target_ws" '.[] | select(.name==$name)' >/dev/null 2>&1; then
          # Target exists: move containers from source to target
          echo "Target workspace $target_ws exists, moving containers from $source_ws" >> "$LOG_FILE"
          $SWAYMSG_BIN "[workspace=$source_ws] move container to workspace $target_ws" >/dev/null 2>&1 || true
          # Focus target to verify move and trigger source workspace destruction (Sway auto-destroys empty workspaces)
          $SWAYMSG_BIN "workspace $target_ws" >/dev/null 2>&1 || true
        else
          # Target missing: standard rename
          echo "Target workspace $target_ws does not exist, renaming $source_ws" >> "$LOG_FILE"
          $SWAYMSG_BIN "rename workspace \"$source_ws\" to \"$target_ws\"" >/dev/null 2>&1 || true
        fi
      }

      # Renumber invalid workspaces FIRST (before assignment)
      renumber_invalid_workspaces() {
        echo "=== RENUMBERING INVALID WORKSPACES (PHASE 1) ===" >> "$LOG_FILE"
        echo "DESK: Renumbering workspaces outside correct ranges..." >&2
        echo "Renumbering workspaces to fit monitor ranges" >> "$LOG_FILE"

        local renumbered_count=0
        local workspace_list
        workspace_list=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | .name' 2>/dev/null || echo "")

        for ws in $workspace_list; do
          if [ -z "$ws" ]; then
            continue
          fi
          # Skip non-numeric workspace names
          if ! [[ "$ws" =~ ^[0-9]+$ ]]; then
            continue
          fi
          
          # Get the output for this workspace
          local output
          output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$ws\") | .output" 2>/dev/null || echo "")

          if [ -z "$output" ]; then
            continue
          fi

          # Determine if workspace is in the correct range for its monitor
          local should_renumber=false
          local offset=0
          case "$output" in
            "DP-1")      # Samsung: should be 11-20
              if [ "$ws" -lt 11 ] || [ "$ws" -gt 20 ]; then
                offset=10
                should_renumber=true
              fi
              ;;
            "DP-2")      # NSL: should be 21-30
              if [ "$ws" -lt 21 ] || [ "$ws" -gt 30 ]; then
                offset=20
                should_renumber=true
              fi
              ;;
            "HDMI-A-1")  # Philips: should be 31-40
              if [ "$ws" -lt 31 ] || [ "$ws" -gt 40 ]; then
                offset=30
                should_renumber=true
              fi
              ;;
            "DP-3")      # BNQ: should be 41-50
              if [ "$ws" -lt 41 ] || [ "$ws" -gt 50 ]; then
                offset=40
                should_renumber=true
              fi
              ;;
          esac

          if [ "$should_renumber" = true ]; then
            # Calculate new workspace number
            local new_ws=$((ws + offset))
            # Ensure new workspace is in valid range
            case "$output" in
              "DP-1")      if [ "$new_ws" -lt 11 ] || [ "$new_ws" -gt 20 ]; then continue; fi ;;
              "DP-2")      if [ "$new_ws" -lt 21 ] || [ "$new_ws" -gt 30 ]; then continue; fi ;;
              "HDMI-A-1")  if [ "$new_ws" -lt 31 ] || [ "$new_ws" -gt 40 ]; then continue; fi ;;
              "DP-3")      if [ "$new_ws" -lt 41 ] || [ "$new_ws" -gt 50 ]; then continue; fi ;;
            esac

            echo "Renumbering workspace $ws on $output to $new_ws (correct range)" >> "$LOG_FILE"
            echo "DESK: Renumbering workspace $ws to $new_ws on $output" >&2
            renumber_workspace_safe "$ws" "$new_ws" "$output"
            renumbered_count=$((renumbered_count + 1))
          else
            echo "Workspace $ws on $output is already in correct range" >> "$LOG_FILE"
          fi
        done

        echo "Renumbered $renumbered_count workspaces to correct ranges" >> "$LOG_FILE"
      }

      # Pre-create essential workspace on specific output (optimized: focus output + workspace)
      pre_create_essential_workspace() {
        local workspace_num="$1"
        local output_name="$2"
        
        # Check if workspace already exists on correct output
        local current_output
        current_output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$workspace_num\") | .output" 2>/dev/null || echo "")
        
        if [ -n "$current_output" ] && [ "$current_output" = "$output_name" ]; then
          echo "Workspace $workspace_num already exists on correct output $output_name" >> "$LOG_FILE"
          return 0
        fi
        
        # Focus output first, then create workspace (one IPC event, no flicker)
        echo "Pre-creating workspace $workspace_num on $output_name" >> "$LOG_FILE"
        $SWAYMSG_BIN "focus output \"$output_name\"" >/dev/null 2>&1
        $SWAYMSG_BIN "workspace $workspace_num" >/dev/null 2>&1
      }

      # Pre-create all essential workspaces used by startup apps
      pre_create_all_essential_workspaces() {
        echo "=== PRE-CREATING ESSENTIAL WORKSPACES ===" >> "$LOG_FILE"
        echo "DESK: Pre-creating essential workspaces (11, 12, 21, 22, 31, 41)..." >&2
        
        local samsung_output
        samsung_output=$(get_output_by_hwid "$SAMSUNG")
        local nsl_output
        nsl_output=$(get_output_by_hwid "$NSL")
        local philips_output
        philips_output=$(get_output_by_hwid "$PHILIPS")
        local bnq_output
        bnq_output=$(get_output_by_hwid "$BNQ")
        
        if [ -n "$samsung_output" ]; then
          pre_create_essential_workspace 11 "$samsung_output"
          pre_create_essential_workspace 12 "$samsung_output"
        fi
        
        if [ -n "$nsl_output" ]; then
          pre_create_essential_workspace 21 "$nsl_output"
          pre_create_essential_workspace 22 "$nsl_output"
        fi
        
        if [ -n "$philips_output" ]; then
          pre_create_essential_workspace 31 "$philips_output"
        fi
        
        if [ -n "$bnq_output" ]; then
          pre_create_essential_workspace 41 "$bnq_output"
        fi
      }

      # Assign workspace range to output by hardware ID
      assign_workspace_range_to_output() {
        local hwid="$1"
        local start_ws="$2"
        local end_ws="$3"
        local name="$4"

        local output_name
        output_name="$(get_output_by_hwid "$hwid")"

        echo "=== ASSIGNING $name ($start_ws-$end_ws) ===" >> "$LOG_FILE"
        echo "Hardware ID: $hwid" >> "$LOG_FILE"
        echo "Target output: $output_name" >> "$LOG_FILE"

        if [ -n "$output_name" ]; then
          echo "DESK: Assigning $name ($hwid) workspaces $start_ws-$end_ws to $output_name" >&2
          echo "DESK: Assigning $name ($hwid) workspaces $start_ws-$end_ws to $output_name" >> "$LOG_FILE"

          # Move ALL existing workspaces in this range to the correct output
          local moved_count=0
          for ws in $(seq "$start_ws" "$end_ws"); do
            local current_output
            current_output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$ws\") | .output" 2>/dev/null || echo "")
            if [ -n "$current_output" ] && [ "$current_output" != "$output_name" ]; then
              echo "Moving workspace $ws from $current_output to $output_name" >> "$LOG_FILE"
              echo "DESK: Moving workspace $ws to $output_name" >&2
              $SWAYMSG_BIN "workspace $ws" >/dev/null 2>&1
              $SWAYMSG_BIN "move workspace to \"$output_name\"" >/dev/null 2>&1
              moved_count=$((moved_count + 1))
            elif [ -n "$current_output" ]; then
              echo "Workspace $ws already on correct output $output_name" >> "$LOG_FILE"
            fi
          done
          echo "Moved $moved_count workspaces for $name" >> "$LOG_FILE"

          # Focus the output and ensure the first workspace exists
          echo "Focusing output $output_name and ensuring workspace $start_ws exists" >> "$LOG_FILE"
          $SWAYMSG_BIN "focus output \"$output_name\"" >/dev/null 2>&1
          $SWAYMSG_BIN "workspace $start_ws" >/dev/null 2>&1

          echo "DESK: Successfully assigned $name workspaces $start_ws-$end_ws" >&2
          echo "Successfully assigned $name workspaces $start_ws-$end_ws" >> "$LOG_FILE"
        else
          echo "DESK: WARNING - $name ($hwid) not found or not active" >&2
          echo "WARNING - $name ($hwid) not found or not active" >> "$LOG_FILE"
        fi
      }

      # Verify all essential workspaces exist on correct outputs
      verify_essential_workspaces() {
        echo "=== VERIFYING ESSENTIAL WORKSPACES ===" >> "$LOG_FILE"
        local essential_workspaces=(11 12 21 22 31 41)
        local all_correct=true
        
        local samsung_output
        samsung_output=$(get_output_by_hwid "$SAMSUNG")
        local nsl_output
        nsl_output=$(get_output_by_hwid "$NSL")
        local philips_output
        philips_output=$(get_output_by_hwid "$PHILIPS")
        local bnq_output
        bnq_output=$(get_output_by_hwid "$BNQ")
        
        for ws in "''${essential_workspaces[@]}"; do
          local expected_output=""
          case "$ws" in
            11|12) expected_output="$samsung_output" ;;
            21|22) expected_output="$nsl_output" ;;
            31) expected_output="$philips_output" ;;
            41) expected_output="$bnq_output" ;;
          esac
          
          if [ -z "$expected_output" ]; then
            echo "WARNING: Cannot verify workspace $ws - output not found" >> "$LOG_FILE"
            continue
          fi
          
          local current_output
          current_output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$ws\") | .output" 2>/dev/null || echo "")
          
          if [ -z "$current_output" ]; then
            echo "ERROR: Workspace $ws does not exist" >> "$LOG_FILE"
            all_correct=false
          elif [ "$current_output" != "$expected_output" ]; then
            echo "ERROR: Workspace $ws is on $current_output but should be on $expected_output" >> "$LOG_FILE"
            all_correct=false
          else
            echo "OK: Workspace $ws is on correct output $expected_output" >> "$LOG_FILE"
          fi
        done
        
        if [ "$all_correct" = true ]; then
          echo "All essential workspaces verified" >> "$LOG_FILE"
          return 0
        else
          echo "WARNING: Some essential workspaces are not correctly assigned" >> "$LOG_FILE"
          return 1
        fi
      }

      # Main execution sequence
      wait_for_kanshi_stability
      renumber_invalid_workspaces  # Run FIRST before assignment
      pre_create_all_essential_workspaces  # Create 11,12,21,22,31,41
      assign_workspace_range_to_output "$SAMSUNG" 11 20 "Samsung"
      assign_workspace_range_to_output "$NSL" 21 30 "NSL"
      assign_workspace_range_to_output "$PHILIPS" 31 40 "Philips"
      assign_workspace_range_to_output "$BNQ" 41 50 "BNQ"
      verify_essential_workspaces
      
      # Create completion lock file
      touch "$LOCK_FILE"
      echo "Created completion lock file: $LOCK_FILE" >> "$LOG_FILE"
      echo "DESK: Workspaces ready - lock file created" >&2

      # Log final state
      echo "=== POST-ASSIGNMENT STATE ===" >> "$LOG_FILE"
      $SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | "Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$LOG_FILE" 2>&1 || echo "Failed to get final workspace state" >> "$LOG_FILE"

      # Restore original focus with safety check
      if [ -n "$ORIGINAL_FOCUSED_WS" ]; then
        if $SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -e --arg name "$ORIGINAL_FOCUSED_WS" '.[] | select(.name==$name)' >/dev/null 2>&1; then
          echo "Restoring focus to original workspace: $ORIGINAL_FOCUSED_WS" >> "$LOG_FILE"
          $SWAYMSG_BIN "workspace $ORIGINAL_FOCUSED_WS" >/dev/null 2>&1 || true
        else
          # Original workspace was renamed/deleted, default to workspace 11
          echo "Original workspace $ORIGINAL_FOCUSED_WS no longer exists, defaulting to workspace 11" >> "$LOG_FILE"
          $SWAYMSG_BIN "workspace 11" >/dev/null 2>&1 || true
        fi
      fi

      echo "DESK: Hardware-ID-based workspace assignment complete" >&2
      echo "=== WORKSPACE ASSIGNMENT COMPLETE ===" >> "$LOG_FILE"
      exit 0
    '';
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-utils.sh" = {
    source = ./scripts/workspace-utils.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-nav-prev.sh" = {
    source = ./scripts/workspace-nav-prev.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-nav-next.sh" = {
    source = ./scripts/workspace-nav-next.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-move-prev.sh" = {
    source = ./scripts/workspace-move-prev.sh;
    executable = true;
  };

  home.file.".config/sway/scripts/workspace-move-next.sh" = {
    source = ./scripts/workspace-move-next.sh;
    executable = true;
  };

  # Generate swaybar-toggle script with proper package paths
  home.file.".config/sway/scripts/swaybar-toggle.sh" = {
    text = ''
      #!/bin/sh
      # Toggle SwayFX's default bar (swaybar) visibility
      # The bar is disabled by default in the config (mode invisible)
      # This script allows manual toggling when needed

      # Get current bar mode
      CURRENT_MODE=$(${pkgs.swayfx}/bin/swaymsg -t get_bar_config bar-0 | ${pkgs.jq}/bin/jq -r '.mode' 2>/dev/null)

      if [ "$CURRENT_MODE" = "invisible" ] || [ -z "$CURRENT_MODE" ]; then
        # Bar is invisible or doesn't exist - show it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode dock
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar enabled (dock mode)" || true
      else
        # Bar is visible - hide it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode invisible
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar disabled (invisible mode)" || true
      fi
    '';
    executable = true;
  };

  # Base Sway packages (startup-app scripts are provided by `startup-apps.nix`)
  home.packages = with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar # Waybar status bar (also configured via programs.waybar)
    swaysome # Workspace namespace per monitor

    # Screenshot workflow
    grim
    slurp
    swappy
    font-awesome_5 # Swappy uses Font Awesome icons
    swaybg # Wallpaper manager

    # Gaming tools
    gamescope
    mangohud

    # Terminal and tools
    jq # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist # Clipboard history manager for Wayland

    # Touchpad gestures
    libinput-gestures

    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    pavucontrol # GUI audio mixer (referenced in waybar config)
  ];
}



# Karabiner-Elements Configuration
# Maps CapsLock to Hyperkey (Cmd+Ctrl+Alt+Shift) for Hammerspoon

{ config, pkgs, lib, userSettings, ... }:

{
  # Create Karabiner configuration file
  home.file.".config/karabiner/karabiner.json".text = builtins.toJSON {
    global = {
      check_for_updates_on_startup = true;
      show_in_menu_bar = true;
      show_profile_name_in_menu_bar = false;
    };

    profiles = [
      {
        name = "Default";
        selected = true;

        # Simple modifications
        simple_modifications = [];

        # Complex modifications (CapsLock → Hyperkey)
        complex_modifications = {
          parameters = {
            "basic.simultaneous_threshold_milliseconds" = 50;
            "basic.to_delayed_action_delay_milliseconds" = 500;
            "basic.to_if_alone_timeout_milliseconds" = 1000;
            "basic.to_if_held_down_threshold_milliseconds" = 500;
            "mouse_motion_to_scroll.speed" = 100;
          };

          rules = [
            {
              description = "CapsLock to Hyperkey (Cmd+Ctrl+Alt+Shift)";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "caps_lock";
                    modifiers = {
                      optional = [ "any" ];
                    };
                  };
                  to = [
                    {
                      key_code = "left_shift";
                      modifiers = [ "left_command" "left_control" "left_option" ];
                    }
                  ];
                  to_if_alone = [
                    {
                      key_code = "escape";
                    }
                  ];
                }
              ];
            }
          ];
        };

        # Virtual keyboard settings
        virtual_hid_keyboard = {
          country_code = 0;
          indicate_sticky_modifier_keys_state = true;
          mouse_key_xy_scale = 100;
        };

        # Devices (empty = apply to all)
        devices = [];
      }
    ];
  };
}

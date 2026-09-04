{ config, pkgs, ... }:

{
  home.packages = [ pkgs.mangohud ];

  home.file.".config/MangoHud/MangoHud.conf".text = ''
    # MangoHud Configuration
    # Toggle: Shift_L+F8 | Cycle layout: Shift_L+F11
    #
    # The HUD starts hidden (no_display) and is summoned with the toggle key.
    # That way it is always running and collecting — so when something feels
    # wrong mid-game you can pull up the frame timing graph immediately, at the
    # moment it matters — without an overlay sitting on screen the rest of the
    # time. Under gamescope the overlay comes from `--mangoapp`, never from
    # MANGOHUD=1 on the game (gamescope's own help says to use --mangoapp
    # instead, and injecting MangoHud into a game under gamescope is what Lutris
    # explicitly disables).

    # Hidden until Shift_L+F8
    no_display

    # Metrics
    fps
    frametime=1
    frame_timing
    cpu_stats
    cpu_temp
    gpu_stats
    gpu_temp
    gpu_mem_clock
    gpu_core_clock
    vram
    ram

    # Display
    position=top-left
    font_size=20
    text_color=FFFFFF
    round_corners=10
    background_alpha=0.4
    toggle_hud=Shift_L+F8
    toggle_hud_position=Shift_L+F11
  '';
}


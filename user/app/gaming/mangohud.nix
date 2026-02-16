{ config, pkgs, ... }:

{
  home.packages = [ pkgs.mangohud ];

  home.file.".config/MangoHud/MangoHud.conf".text = ''
    # MangoHud Configuration
    # Toggle: Shift_L+F8 | Cycle layout: Shift_L+F11

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


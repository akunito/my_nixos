{ config, pkgs, ... }:

{
  home.packages = [ pkgs.mangohud ];
  
  home.file.".config/MangoHud/MangoHud.conf".text = ''
    # MangoHud Configuration
    # Essential metrics for gaming
    
    cpu_temp
    gpu_temp
    ram
    fps
    frametime
    
    # Display settings
    position=top-left
    text_color=FFFFFF
    round_corners=10
    background_alpha=0.5
  '';
}


{ pkgs, systemSettings, lib, ... }:

{
  # GPU Monitoring Packages based on GPU type
  # This module acts as the single source of truth for btop and GPU monitoring tools
  environment.systemPackages = with pkgs; lib.mkMerge [
    
    # --- AMD Dedicated GPU (DESK, AGADESK) ---
    (lib.mkIf (systemSettings.gpuType == "amd") [
      # 1. System Monitor: Use btop-rocm (Provides '/bin/btop')
      #    CRITICAL: Do not install standard 'btop' here to avoid collision
      btop-rocm
      
      # 2. Runtime Dependency for btop-rocm
      rocmPackages.rocm-smi
      
      # 3. Visual Monitor (AMD variant - prevents NVIDIA build errors)
      nvtopPackages.amd
      
      # 4. Low-level debug tool
      radeontop
    ])

    # --- Intel / Integrated GPU (LAPTOP, AGA, YOGAAKU, WSL) ---
    (lib.mkIf (systemSettings.gpuType == "intel") [
      # 1. System Monitor: Use standard btop
      btop
      
      # 2. Visual Monitor (Intel variant)
      nvtopPackages.intel
      
      # 3. Intel-specific CLI tools (provides 'intel_gpu_top')
      intel-gpu-tools
    ])
    
    # --- Fallback / Generic (NVIDIA, unknown, etc.) ---
    (lib.mkIf (systemSettings.gpuType != "amd" && systemSettings.gpuType != "intel") [
      btop
      nvtopPackages.modelling  # Generic fallback
    ])
  ];
  
  # User Permissions - Ensure user can access GPU sensors
  # Note: This should be checked in user configuration
  # users.users.${username}.extraGroups = [ "video" "render" ];
}


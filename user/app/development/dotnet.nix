{
  pkgs,
  systemSettings,
  lib,
  ...
}:

# .NET toolchain for AkuWM (github.com/akunito/AkuWM), built from WSL on DESK_W11.
# Gated by systemSettings.dotnetDevEnable so no other profile pays for the SDK.
#
# The Windows binary is produced from here with
#   dotnet publish -r win-x64 --self-contained
# and the pure projects (AkuWM.Core, AkuWM.Tests) run their unit tests on Linux.

{
  home.packages = lib.optionals (systemSettings.dotnetDevEnable or false) [
    pkgs.dotnet-sdk_8 # 8.0.4xx; win-x64 publishing works from Linux
  ];

  # Telemetry off, and keep the workload/package caches inside $HOME so a
  # `nix-collect-garbage` never takes the NuGet cache with it.
  home.sessionVariables = lib.mkIf (systemSettings.dotnetDevEnable or false) {
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_NOLOGO = "1";
    DOTNET_ROOT = "${pkgs.dotnet-sdk_8}/share/dotnet";
  };
}

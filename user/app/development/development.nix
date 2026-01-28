{
  pkgs,
  pkgs-unstable,
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  # Development tools and IDEs
  # Controlled by systemSettings.developmentToolsEnable flag
  home.packages = lib.optionals (systemSettings.developmentToolsEnable == true) [
    # Code Editors and IDEs
    pkgs-unstable.vscode           # Visual Studio Code
    pkgs-unstable.code-cursor      # Cursor AI-powered code editor
    pkgs-unstable.opencode         # Open-source code editor
    pkgs-unstable.claude-code      # Claude Code CLI
    pkgs-unstable.qwen-code        # Alibaba Qwen Code editor

    # Version Control Tools
    pkgs.git-crypt                 # Transparent file encryption in git

    # Shell and Cloud Tools
    pkgs-unstable.powershell       # PowerShell 7+
    pkgs.azure-cli                 # Azure command-line interface
    pkgs-unstable.cloudflared      # Cloudflare tunnel client

    # Database Management
    pkgs-unstable.dbeaver-bin      # Universal database management tool

    # Design and Documentation
    pkgs-unstable.drawio           # Diagramming and flowchart tool

    # Development Framework Tools
    pkgs-unstable.antigravity      # Development automation and tooling
  ];

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };
}

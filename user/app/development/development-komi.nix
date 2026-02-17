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
    # === Programming Language Runtimes ===
    pkgs-unstable.nodejs_22        # Node.js 22.x LTS (includes npm, npx)
    pkgs-unstable.python312        # Python 3.12 (includes pip)
    pkgs-unstable.python312Packages.pip # Ensure pip is available
    pkgs-unstable.go               # Go programming language
    pkgs-unstable.rustup           # Rust toolchain installer (provides cargo, rustc)

    # === Code Editors and IDEs ===
    pkgs-unstable.vscode           # Visual Studio Code
    pkgs-unstable.code-cursor      # Cursor AI-powered code editor
    pkgs-unstable.opencode         # Open-source code editor
    pkgs-unstable.claude-code      # Claude Code CLI
    pkgs-unstable.qwen-code        # Alibaba Qwen Code editor

    # === Version Control Tools ===
    pkgs.git-crypt                 # Transparent file encryption in git

    # === Shell and Cloud Tools ===
    pkgs-unstable.powershell       # PowerShell 7+
    pkgs.azure-cli                 # Azure command-line interface
    pkgs-unstable.cloudflared      # Cloudflare tunnel client

    # === Database Management ===
    pkgs-unstable.dbeaver-bin      # Universal database management tool

    # === Design and Documentation ===
    pkgs-unstable.drawio           # Diagramming and flowchart tool

    # === Development Framework Tools ===
    pkgs-unstable.antigravity      # Development automation and tooling
  ];

}

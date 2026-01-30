{ pkgs, userSettings, ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    # Bracketed Segments preset with username@hostname prefix
    # Based on: https://starship.rs/presets/bracketed-segments
    settings = {
      "$schema" = "https://starship.rs/config-schema.json";

      # Prompt format: username@hostname [directory] [git] [languages...] [time]
      format = "$username$hostname $directory$python$rust$nodejs$golang$java$c$lua$docker_context$nix_shell$git_branch$git_status$fill$cmd_duration$time\n$character";

      # Add newline between prompts for better readability
      add_newline = true;

      # Username - no brackets, bold cyan
      username = {
        show_always = true;
        format = "[$user]($style)";
        style_user = "bold cyan";
        style_root = "bold red";
      };

      # Hostname - no brackets, with @ prefix
      # SSH symbol U+F489
      hostname = {
        ssh_only = false;
        ssh_symbol = " ";
        format = "[@$hostname]($style)";
        style = "bold cyan";
        disabled = false;
      };

      # Directory - bracketed
      # Read-only lock icon U+F023
      directory = {
        format = "\\[[$path]($style)[$read_only]($read_only_style)\\] ";
        style = "bold cyan";
        truncation_length = 3;
        truncate_to_repo = true;
        read_only = " ";
        read_only_style = "red";
      };

      # Git branch - bracketed with icon
      # Git branch icon U+E0A0
      git_branch = {
        format = "\\[[$symbol$branch]($style)\\] ";
        symbol = " ";
        style = "bold green";
      };

      # Git status - bracketed
      # Uses standard Unicode arrows and Nerd Font icons
      git_status = {
        format = "(\\[[$all_status$ahead_behind]($style)\\] )";
        style = "bold yellow";
        conflicted = "=\${count}";
        ahead = "\${count}";        # U+F062 arrow up
        behind = "\${count}";       # U+F063 arrow down
        diverged = "\${ahead_count}\${behind_count}";
        untracked = "?\${count}";
        stashed = "\${count}";      # U+F01C inbox
        modified = "!\${count}";
        staged = "+\${count}";
        renamed = "»\${count}";
        deleted = "\${count}";     # U+F00D x mark
      };

      # Command duration - bracketed
      cmd_duration = {
        format = "\\[[$duration]($style)\\] ";
        style = "bold yellow";
        min_time = 2000;
      };

      # Time - bracketed
      time = {
        disabled = false;
        format = "\\[[$time]($style)\\]";
        style = "bold white";
        time_format = "%H:%M";
      };

      # Fill - spaces between left and right prompt
      fill = {
        symbol = " ";
      };

      # Character (prompt symbol)
      # U+F054  (chevron right) or U+276F ❯
      character = {
        success_symbol = "[](bold green)";
        error_symbol = "[](bold red)";
        vimcmd_symbol = "[](bold green)";
      };

      # Language/tech stack modules - bracketed format
      # Icons use Nerd Font codepoints

      # Python - U+E73C
      python = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold yellow";
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" ".python-version" "pyproject.toml" "Pipfile" "setup.py"];
      };

      # Rust - U+E7A8
      rust = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold red";
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml"];
      };

      # Node.js - U+E718
      nodejs = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold green";
        detect_extensions = ["js" "mjs" "cjs" "ts"];
        detect_files = ["package.json" ".node-version" ".nvmrc"];
      };

      # Golang - U+E626
      golang = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold cyan";
        detect_extensions = ["go"];
        detect_files = ["go.mod" "go.sum"];
      };

      # Java - U+E738
      java = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold red";
        detect_extensions = ["java" "class" "jar"];
        detect_files = ["pom.xml" "build.gradle" "build.gradle.kts"];
      };

      # C/C++ - U+E61E
      c = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold blue";
        detect_extensions = ["c" "h" "cpp" "cc" "hpp"];
      };

      # Lua - U+E620
      lua = {
        symbol = " ";
        format = "\\[[$symbol($version)]($style)\\] ";
        style = "bold blue";
        detect_extensions = ["lua"];
      };

      # Docker - U+F308
      docker_context = {
        symbol = " ";
        format = "\\[[$symbol$context]($style)\\] ";
        style = "bold blue";
        detect_files = ["Dockerfile" "docker-compose.yml" "docker-compose.yaml"];
      };

      # Nix shell - U+F313
      nix_shell = {
        symbol = " ";
        format = "\\[[$symbol$state( \\($name\\))]($style)\\] ";
        style = "bold blue";
      };

      # Additional language symbols with Nerd Font codepoints
      aws.symbol = " ";      # U+F270
      buf.symbol = " ";      # U+F0E7
      conda.symbol = " ";    # U+F10D3
      dart.symbol = " ";     # U+E798
      elixir.symbol = " ";   # U+E62D
      haskell.symbol = " ";  # U+E61F
      julia.symbol = " ";    # U+E624
      kotlin.symbol = " ";   # U+E634
      memory_usage.symbol = " "; # U+F035B
      package.symbol = " ";  # U+F0C4
      swift.symbol = " ";    # U+E755
    };
  };
}

{ pkgs, userSettings, ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  # Write starship.toml directly with proper Unicode escapes for Nerd Font icons
  # This avoids issues with Nix string handling of Unicode characters
  xdg.configFile."starship.toml".text = ''
    "$schema" = "https://starship.rs/config-schema.json"
    add_newline = true
    format = "$username$hostname $directory$python$rust$nodejs$golang$java$c$lua$docker_context$nix_shell$git_branch$git_status$fill$cmd_duration$time\n$character"

    # Username - no brackets, bold cyan
    [username]
    show_always = true
    format = "[$user]($style)"
    style_user = "bold cyan"
    style_root = "bold red"

    # Hostname - no brackets, with @ prefix
    [hostname]
    ssh_only = false
    ssh_symbol = "\uf489 "
    format = "[@$hostname]($style)"
    style = "bold cyan"
    disabled = false

    # Directory - bracketed
    [directory]
    format = "[$path]($style)[$read_only]($read_only_style) "
    style = "bold cyan"
    truncation_length = 3
    truncate_to_repo = true
    read_only = " \uf023"
    read_only_style = "red"

    # Git branch - bracketed with icon U+E0A0
    [git_branch]
    format = "[\ue0a0 $branch]($style) "
    style = "bold green"

    # Git status
    [git_status]
    format = "([$all_status$ahead_behind]($style) )"
    style = "bold yellow"
    conflicted = "="
    ahead = "\uf062"
    behind = "\uf063"
    diverged = "\uf062\uf063"
    untracked = "?"
    stashed = "\uf01c"
    modified = "!"
    staged = "+"
    renamed = ">"
    deleted = "\uf00d"

    # Command duration
    [cmd_duration]
    format = "[$duration]($style) "
    style = "bold yellow"
    min_time = 2000

    # Time
    [time]
    disabled = false
    format = "[$time]($style)"
    style = "bold white"
    time_format = "%H:%M"

    # Fill
    [fill]
    symbol = " "

    # Character (prompt symbol) U+276F
    [character]
    success_symbol = "[\u276f](bold green)"
    error_symbol = "[\u276f](bold red)"
    vimcmd_symbol = "[\u276e](bold green)"

    # Python U+E73C
    [python]
    symbol = "\ue73c "
    format = "[$symbol($version)]($style) "
    style = "bold yellow"
    detect_extensions = ["py"]
    detect_files = ["requirements.txt", ".python-version", "pyproject.toml", "Pipfile", "setup.py"]

    # Rust U+E7A8
    [rust]
    symbol = "\ue7a8 "
    format = "[$symbol($version)]($style) "
    style = "bold red"
    detect_extensions = ["rs"]
    detect_files = ["Cargo.toml"]

    # Node.js U+E718
    [nodejs]
    symbol = "\ue718 "
    format = "[$symbol($version)]($style) "
    style = "bold green"
    detect_extensions = ["js", "mjs", "cjs", "ts"]
    detect_files = ["package.json", ".node-version", ".nvmrc"]

    # Golang U+E626
    [golang]
    symbol = "\ue626 "
    format = "[$symbol($version)]($style) "
    style = "bold cyan"
    detect_extensions = ["go"]
    detect_files = ["go.mod", "go.sum"]

    # Java U+E738
    [java]
    symbol = "\ue738 "
    format = "[$symbol($version)]($style) "
    style = "bold red"
    detect_extensions = ["java", "class", "jar"]
    detect_files = ["pom.xml", "build.gradle", "build.gradle.kts"]

    # C/C++ U+E61E
    [c]
    symbol = "\ue61e "
    format = "[$symbol($version)]($style) "
    style = "bold blue"
    detect_extensions = ["c", "h", "cpp", "cc", "hpp"]

    # Lua U+E620
    [lua]
    symbol = "\ue620 "
    format = "[$symbol($version)]($style) "
    style = "bold blue"
    detect_extensions = ["lua"]

    # Docker U+F308
    [docker_context]
    symbol = "\uf308 "
    format = "[$symbol$context]($style) "
    style = "bold blue"
    detect_files = ["Dockerfile", "docker-compose.yml", "docker-compose.yaml"]

    # Nix shell U+F313
    [nix_shell]
    symbol = "\uf313 "
    format = "[$symbol$state( \\($name\\))]($style) "
    style = "bold blue"

    # Additional symbols
    [aws]
    symbol = "\uf270 "

    [buf]
    symbol = "\uf0e7 "

    [conda]
    symbol = "\uf10d "

    [dart]
    symbol = "\ue798 "

    [elixir]
    symbol = "\ue62d "

    [haskell]
    symbol = "\ue61f "

    [julia]
    symbol = "\ue624 "

    [kotlin]
    symbol = "\ue634 "

    [memory_usage]
    symbol = "\uf035 "

    [package]
    symbol = "\uf0c4 "

    [swift]
    symbol = "\ue755 "
  '';
}

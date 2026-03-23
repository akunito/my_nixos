{
  pkgs,
  pkgs-unstable,
  lib,
  systemSettings,
  userSettings,
  ...
}:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isDesktop = systemSettings.developmentToolsEnable or false;
  # Standalone mode: claudeCodeEnable without full developmentToolsEnable (for VPS/headless)
  isStandalone = (systemSettings.claudeCodeEnable or false) && !isDesktop;
  dotfilesPath = systemSettings.dotfilesPath or "/home/${userSettings.username}/.dotfiles";

  # Claude config Nextcloud backup
  claudeBackupToNextcloudEnable = systemSettings.claudeBackupToNextcloudEnable or false;
  nextcloudFolder = systemSettings.nextcloudSyncFolder or "/home/${userSettings.username}/Nextcloud";

  # Notification command: notify-send on desktop, no-op on headless
  notificationCommand =
    if isDarwin then
      "osascript -e 'display notification \"Needs your attention\" with title \"Claude Code\"'"
    else if isDesktop && (systemSettings.gpuType or "none") != "none" then
      "notify-send -u normal -t 10000 -i dialog-information 'Claude Code' 'Needs your attention'"
    else
      "true"; # no-op on headless/VPS

  # Perplexity API key from secrets (passed through systemSettings)
  perplexityApiKey = systemSettings.perplexityApiKey or "";

  # Claude Code read-only mode (deny edit/write tools)
  claudeCodeReadOnly = systemSettings.claudeCodeReadOnly or false;

  # Plane MCP credentials
  planeApiToken = systemSettings.planeApiToken or "";
  planeApiUrl = systemSettings.planeApiUrl or "";
  planeWorkspaceSlug = systemSettings.planeWorkspaceSlug or "";

  # Grafana MCP credentials
  grafanaMcpToken = systemSettings.grafanaMcpToken or "";
  grafanaMcpUrl = systemSettings.grafanaMcpUrl or "";

  # PostgreSQL MCP credentials (read-only)
  dbClaudeReadonlyConnStr = systemSettings.dbClaudeReadonlyConnStr or "";

  # n8n MCP credentials
  n8nMcpApiKey = systemSettings.n8nMcpApiKey or "";
  n8nMcpUrl = systemSettings.n8nMcpUrl or "";

  # Build the settings.json structure
  # NOTE: MCP servers are NOT configured here — Claude Code reads them from
  # .mcp.json (project-scoped) or ~/.claude.json (user-scoped), NOT settings.json.
  # Plane MCP is configured in .mcp.json with env var references; the actual
  # credentials are set via home.sessionVariables below.
  settingsJson = {
    permissions = {
      allow = [
        # Read-only tools (always safe)
        "Read"
        "Glob"
        "Grep"
        "WebFetch"
        "WebSearch"

        # MCP tools — Plane project management
        "mcp__plane__*"

        # MCP tools — Infrastructure monitoring & automation
        "mcp__grafana__*"
        "mcp__postgres__*"
        "mcp__n8n__*"

        # Safe Bash patterns — read-only system inspection
        "Bash(ls *)"
        "Bash(cat *)"
        "Bash(head *)"
        "Bash(tail *)"
        "Bash(wc *)"
        "Bash(file *)"
        "Bash(which *)"
        "Bash(echo *)"
        "Bash(env)"
        "Bash(printenv *)"
        "Bash(pwd)"
        "Bash(whoami)"
        "Bash(hostname)"
        "Bash(uname *)"
        "Bash(df *)"
        "Bash(du *)"
        "Bash(free *)"
        "Bash(uptime)"
        "Bash(ps *)"
        "Bash(top -bn1*)"

        # Git (read-only)
        "Bash(git status*)"
        "Bash(git log*)"
        "Bash(git diff*)"
        "Bash(git branch*)"
        "Bash(git show*)"
        "Bash(git remote*)"
        "Bash(git tag*)"
        "Bash(git rev-parse*)"
        "Bash(git config --get*)"
        "Bash(git config --list*)"
        "Bash(git stash list*)"

        # Nix (read-only)
        "Bash(nix eval:*)"
        "Bash(nix flake show*)"
        "Bash(nix flake metadata*)"
        "Bash(nix flake info*)"
        "Bash(nix-instantiate --eval*)"
        "Bash(nixos-option *)"

        # Systemd inspection
        "Bash(systemctl status *)"
        "Bash(systemctl --user status *)"
        "Bash(systemctl list-units*)"
        "Bash(systemctl list-timers*)"
        "Bash(systemctl is-active*)"
        "Bash(systemctl is-enabled*)"
        "Bash(journalctl *)"

        # Docker inspection
        "Bash(docker ps*)"
        "Bash(docker logs*)"
        "Bash(docker images*)"
        "Bash(docker network ls*)"
        "Bash(docker network inspect*)"
        "Bash(docker volume ls*)"
        "Bash(docker inspect*)"

        # Network inspection
        "Bash(ip addr*)"
        "Bash(ip link*)"
        "Bash(ip route*)"
        "Bash(ss -*)"
        "Bash(ping *)"
        "Bash(curl -s *)"
        "Bash(curl --silent *)"
        "Bash(dig *)"
        "Bash(nslookup *)"

        # GitHub CLI (read-only)
        "Bash(gh pr list*)"
        "Bash(gh pr view*)"
        "Bash(gh pr status*)"
        "Bash(gh issue list*)"
        "Bash(gh issue view*)"
        "Bash(gh api *)"
        "Bash(gh repo view*)"

        # Search tools
        "Bash(tree *)"
        "Bash(find *)"
        "Bash(rg *)"
        "Bash(grep *)"

        # VPN inspection
        "Bash(tailscale status*)"
        "Bash(wg show*)"
      ];

      deny = [
        # === nixos-rebuild protection (existing) ===
        "Bash(*nixos-rebuild switch*)"
        "Bash(*nixos-rebuild switch --flake*)"
        "Bash(*sudo nixos-rebuild*)"
        "Bash(ssh*nixos-rebuild*)"
        "Bash(ssh*nixos-rebuild switch*)"

        # === SSH key and credential protection ===
        "Read(~/.ssh/id_*)"
        "Read(~/.ssh/*.pem)"
        "Read(~/.ssh/*.key)"
        "Read(~/.ssh/authorized_keys)"
        "Edit(~/.ssh/**)"
        "Write(~/.ssh/**)"

        # === System credential files ===
        "Read(//etc/shadow)"
        "Read(//etc/gshadow)"

        # === GPG keyring ===
        "Read(~/.gnupg/**)"
        "Edit(~/.gnupg/**)"

        # === Cloud and service credentials ===
        "Read(~/.aws/credentials)"
        "Read(~/.kube/config)"
        "Read(~/.docker/config.json)"
        "Read(~/.git-crypt/**)"
        "Read(~/.claude/.credentials.json)"

        # === Bash variants for credential files ===
        "Bash(cat ~/.ssh/id_*)"
        "Bash(*cat /etc/shadow*)"
        "Bash(*cat /etc/gshadow*)"
        "Bash(cat ~/.gnupg/*)"
        "Bash(cat ~/.aws/credentials*)"
        "Bash(cat ~/.git-crypt/*)"
        "Bash(cat ~/.claude/.credentials.json*)"
        "Bash(*base64*~/.ssh/*)"

        # === Destructive git operations ===
        "Bash(git push --force*)"
        "Bash(git push -f *)"

        # === Destructive filesystem operations ===
        "Bash(rm -rf /*)"
        "Bash(rm -rf ~/*)"
      ]
      # Add read-only deny rules if claudeCodeReadOnly is enabled
      ++ lib.optionals claudeCodeReadOnly [
        "Edit(**)"
        "Write(**)"
      ];
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${dotfilesPath}/.claude/hooks/block-nixos-rebuild.sh";
              timeout = 5;
            }
            {
              type = "command";
              command = "${dotfilesPath}/.claude/hooks/block-sensitive-files.sh";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Read|Edit|Write|Grep|Glob";
          hooks = [
            {
              type = "command";
              command = "${dotfilesPath}/.claude/hooks/block-sensitive-files.sh";
              timeout = 5;
            }
          ];
        }
      ];

      PostToolUse = [
        {
          matcher = "WebFetch";
          hooks = [
            {
              type = "command";
              command = "${dotfilesPath}/.claude/hooks/scan-web-content.sh";
              timeout = 10;
            }
          ];
        }
        {
          matcher = "Write|Edit";
          hooks = [
            {
              type = "command";
              command = "${dotfilesPath}/.claude/hooks/doc-update-reminder.sh";
              timeout = 3;
            }
          ];
        }
      ];

      Notification = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = notificationCommand;
            }
          ];
        }
      ];
    };
  };

in
{
  # Standalone mode: install claude-code + nodejs (for npx/MCP) without full dev IDEs
  home.packages = lib.optionals isStandalone [
    pkgs-unstable.claude-code      # Claude Code CLI
    pkgs.nodejs_22                 # Node.js for npx (required by Perplexity MCP)
    pkgs-unstable.uv               # Python package runner (uvx, required by Plane MCP)
    pkgs.git-crypt                 # Transparent file encryption in git
  ];

  # Generate settings JSON as a base reference file (for the activation script to copy from)
  # This is NOT the actual settings.json — it's a template stored in ~/.config/
  xdg.configFile."claude-settings-base.json" = {
    text = builtins.toJSON settingsJson;
  };

  # Copy settings.json as a writable file (not a symlink) so Claude Code can modify it
  # (e.g., "don't ask again" permissions). Only writes on first setup or migration from symlink.
  # To force-regenerate: rm ~/.claude/settings.json && sync-user.sh
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    settings_file="$HOME/.claude/settings.json"
    base_file="$HOME/.config/claude-settings-base.json"

    if [ -L "$settings_file" ]; then
      # Migration: replace Nix store symlink with a writable copy
      echo "Claude Code: Migrating settings.json from symlink to writable file"
      cp -L "$settings_file" "$settings_file.bak"
      rm "$settings_file"
      cp "$base_file" "$settings_file"
      chmod 644 "$settings_file"
      echo "Claude Code: Backup saved to settings.json.bak"
    elif [ ! -f "$settings_file" ]; then
      # First-time setup: create from base
      mkdir -p "$HOME/.claude"
      cp "$base_file" "$settings_file"
      chmod 644 "$settings_file"
      echo "Claude Code: Generated writable settings.json"
    else
      # Already a regular file: don't touch it (preserve user changes)
      echo "Claude Code: settings.json exists (preserving user changes)"
    fi
  '';

  # Set API keys as environment variables for MCP servers (referenced in .mcp.json)
  home.sessionVariables =
    lib.optionalAttrs (perplexityApiKey != "") {
      PERPLEXITY_API_KEY = perplexityApiKey;
    }
    // lib.optionalAttrs (planeApiToken != "") {
      PLANE_API_KEY = planeApiToken;
      PLANE_BASE_URL = planeApiUrl;
      PLANE_WORKSPACE_SLUG = planeWorkspaceSlug;
    }
    // lib.optionalAttrs (grafanaMcpToken != "") {
      GRAFANA_URL = grafanaMcpUrl;
      GRAFANA_API_KEY = grafanaMcpToken;
    }
    // lib.optionalAttrs (dbClaudeReadonlyConnStr != "") {
      POSTGRES_MCP_CONNECTION_STRING = dbClaudeReadonlyConnStr;
    }
    // lib.optionalAttrs (n8nMcpApiKey != "") {
      N8N_MCP_API_KEY = n8nMcpApiKey;
      N8N_MCP_BASE_URL = n8nMcpUrl;
    };

  # Generate env file for systemd services (e.g., claude-matrix-bot) that need MCP credentials.
  # Systemd user services don't inherit shell sessionVariables, so they need an EnvironmentFile.
  home.file.".claude/mcp-env" = {
    text = lib.concatStringsSep "\n" (
      lib.optional (perplexityApiKey != "") "PERPLEXITY_API_KEY=${perplexityApiKey}"
      ++ lib.optional (planeApiToken != "") "PLANE_API_KEY=${planeApiToken}"
      ++ lib.optional (planeApiUrl != "") "PLANE_BASE_URL=${planeApiUrl}"
      ++ lib.optional (planeWorkspaceSlug != "") "PLANE_WORKSPACE_SLUG=${planeWorkspaceSlug}"
      ++ lib.optional (grafanaMcpToken != "") "GRAFANA_URL=${grafanaMcpUrl}"
      ++ lib.optional (grafanaMcpToken != "") "GRAFANA_API_KEY=${grafanaMcpToken}"
      ++ lib.optional (dbClaudeReadonlyConnStr != "") "POSTGRES_MCP_CONNECTION_STRING=${dbClaudeReadonlyConnStr}"
      ++ lib.optional (n8nMcpApiKey != "") "N8N_MCP_API_KEY=${n8nMcpApiKey}"
      ++ lib.optional (n8nMcpUrl != "") "N8N_MCP_BASE_URL=${n8nMcpUrl}"
    ) + "\n";
    force = true;
  };

  # Nextcloud backup: daily compressed archive of ~/.claude/ (excludes ephemeral + credentials)
  systemd.user.services."claude-nextcloud-backup" = lib.mkIf claudeBackupToNextcloudEnable {
    Unit = {
      Description = "Backup Claude Code config to Nextcloud";
    };
    Service = {
      Type = "oneshot";
      ExecStart = let
        backupScript = pkgs.writeShellScript "claude-nextcloud-backup" ''
          set -euo pipefail
          DEST="${nextcloudFolder}/backups"
          mkdir -p "$DEST"
          ${pkgs.gnutar}/bin/tar \
            --create \
            --zstd \
            --file "$DEST/claude-backup.tar.zst.tmp" \
            --directory="$HOME" \
            --exclude='.claude/debug' \
            --exclude='.claude/telemetry' \
            --exclude='.claude/.credentials.json' \
            --exclude='.claude/settings.json.bak' \
            --exclude='.claude/mcp-env' \
            .claude/
          mv "$DEST/claude-backup.tar.zst.tmp" "$DEST/claude-backup.tar.zst"
        '';
      in "${backupScript}";
    };
  };

  systemd.user.timers."claude-nextcloud-backup" = lib.mkIf claudeBackupToNextcloudEnable {
    Unit = {
      Description = "Daily Claude Code backup to Nextcloud";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}

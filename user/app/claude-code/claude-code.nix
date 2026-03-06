{
  pkgs,
  lib,
  systemSettings,
  userSettings,
  ...
}:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isDesktop = systemSettings.developmentToolsEnable or false;
  dotfilesPath = systemSettings.dotfilesPath or "/home/${userSettings.username}/.dotfiles";

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

  # Build the settings.json structure
  settingsJson = {
    permissions = {
      allow = [
        # Read-only tools (always safe)
        "Read"
        "Glob"
        "Grep"
        "WebFetch"
        "WebSearch"

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
  # Declaratively manage ~/.claude/settings.json
  home.file.".claude/settings.json" = {
    text = builtins.toJSON settingsJson;
  };

  # Set Perplexity API key as environment variable for MCP server
  home.sessionVariables = lib.mkIf (perplexityApiKey != "") {
    PERPLEXITY_API_KEY = perplexityApiKey;
  };
}

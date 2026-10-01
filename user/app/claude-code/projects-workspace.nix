# ~/Projects as a single Claude Code workspace for several projects.
#
# WHY: Aga manages two projects (babydocs → Plane IRIN, homedocs → Plane HOME) and
# would certainly end up with the wrong window in front of her if each repository
# were its own VS Code window. One window is the lesser evil — mixing context can be
# controlled with rules, mixing windows cannot.
#
# WHAT THIS HAS TO PROVIDE: Claude Code resolves project settings and `.mcp.json`
# from the directory it was started in (or the git repository root, when that is an
# ancestor). Launch it in ~/Projects and the per-repository `.claude/settings.json`
# and `.mcp.json` inside babydocs are NOT loaded — she would get a permission prompt
# per step and no Plane. So the allowlist and the MCP config have to exist one level
# up, next to a router CLAUDE.md.
#
# CLAUDE.md is different: files above the working directory load at launch, and files
# in subdirectories load on demand when Claude reads files there. So the router here
# and each project's own CLAUDE.md both apply, in that order.
#
# BROWSER: the VS Code panel only attaches Claude in Chrome after `@browser`, once
# per conversation, and has no setting for it ("Enabled by default" only covers
# sessions started outside the editor). The attach is nothing but an MCP server
# running `claude --claude-in-chrome-mcp`, so mcp.json declares it — under the
# name "browser": a server named "claude-in-chrome" in a config file is dropped
# (reserved), measured 2026-10-01 on LAPTOP_YOGA. The browser extension's own
# per-site permissions still apply; mcp__browser__* is allowed so the panel does
# not prompt per click.
#
# Flags: claudeProjectsWorkspaceEnable, claudeProjectsWorkspaceDir (default "Projects").

{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.claudeProjectsWorkspaceEnable or false;
  dir = systemSettings.claudeProjectsWorkspaceDir or "Projects";
in
lib.mkIf enabled {
  home.file."${dir}/CLAUDE.md".source = ./projects-workspace/CLAUDE.md;
  home.file."${dir}/.claude/settings.json".source = ./projects-workspace/settings.json;
  home.file."${dir}/.mcp.json".source = ./projects-workspace/mcp.json;
}

// OpenCode plugin: the deploy/infra rules of ~/.dotfiles/CLAUDE.md and .claude/rules/deployment.md,
// the part of Claude Code's hooks that matters for a private local model (Diego 2026-10-16: reading
// private data or passwords is fine, so no read/secret rules here). A thrown Error blocks the bash call
// and its message goes back to the model. Confirmation prompts (flake update, reboot, tailscale…)
// live in opencode.nix `permission.bash`, which can ask; a plugin can only allow or block.
import { execSync } from "node:child_process";

const HOME = process.env.HOME || "";
const DOTFILES = `${HOME}/.dotfiles`;

const sh = (cmd, cwd) => {
  try { return execSync(cmd, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 5000 }).trim(); }
  catch { return null; }
};

const DEPLOY = /(^|[\s;&|"'(\/])(install|deploy)\.sh\b/;
const NIXOS_REBUILD = /\bnixos-rebuild\s+(switch|boot|test)\b/;
const PIPED = /(install|deploy)\.sh[^|]*\|\s*(tail|head|grep)\b/;
const HEAVY_BUILD = /\b(docker\s+(build|buildx|compose\s+build)|dotnet\s+(build|publish)|cargo\s+build|npm\s+(run\s+build|ci|install)|pip\s+install)\b/;

// The ssh options before user@host must contain -A (agent forwarding: sudo over ssh needs it).
const sshWithoutA = (cmd) => {
  const m = cmd.match(/\bssh\b((?:\s+-[^\s]+(?:\s+[^\s@-][^\s@]*)?)*)\s+[\w.-]+@[\w.-]+/);
  if (!m) return false;
  return !/(^|\s)-[a-zA-Z]*A[a-zA-Z]*(?=\s|$)/.test(m[1]);
};

const BLOCK = (msg) => { throw new Error(`deploy-guard: ${msg}`); };

export const DeployGuard = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return;
    const cmd = String(output?.args?.command ?? "");
    const inDotfiles = (directory || "").startsWith(DOTFILES) || cmd.includes(".dotfiles");

    if (NIXOS_REBUILD.test(cmd))
      BLOCK("nixos-rebuild switch/boot/test is FORBIDDEN on every machine (wrong hardware-configuration.nix → boot failures). " +
        "Local: ./deploy.sh --profile <PROFILE>. Remote: commit+push, then " +
        "ssh -A user@<IP> \"cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s [-d]\". " +
        "`nixos-rebuild build` / `nix build` are fine.");

    if (/\.homelab\/plane/.test(cmd) &&
        /(\bcp\b|\bmv\b|\brm\b|sed\s+-i|\btee\b|>\s*\S|docker(\s+compose)?\s+(up|restart|stop|rm))/.test(cmd))
      BLOCK("Plane changes ONLY through plane-deploy on VPS_PROD (--dev-only, --yes, --rollback prod). Never edit ~/.homelab/plane* or restart the stack by hand.");

    if (process.env.ENV_PROFILE === "DESK_W11" && HEAVY_BUILD.test(cmd) && !/\brbuild\b/.test(cmd))
      BLOCK("on DESK_W11 builds run on the VPS (a WSL2 docker/dotnet build stalls Hyper-V networking → game lag): scripts/rbuild PROJECT_DIR -- COMMAND.");

    if (inDotfiles) {
      if (/\bgit\s+(-C\s+\S+\s+)?add\s+(-A|--all|\.)(\s|$)/.test(cmd) || /\bgit\s+(-C\s+\S+\s+)?commit\b[^|;&]*\s-[a-zA-Z]*a[a-zA-Z]*\b/.test(cmd))
        BLOCK("several sessions share ~/.dotfiles' git index: stage and commit BY PATH (git add -- <paths>; git commit -m … -- <paths>), never add -A / add . / commit -a.");
      if (/\bgit\s+(-C\s+\S+\s+)?commit\b/.test(cmd) && !/\s--\s+\S/.test(cmd))
        BLOCK("commit by path in ~/.dotfiles: git commit -m \"…\" -- <paths> (a bare commit takes whatever other sessions staged).");
      if (/\bgit\s+(-C\s+\S+\s+)?reset\s+--hard\b/.test(cmd) && !/\bssh\b/.test(cmd)) {
        const dirty = sh("git status --porcelain --untracked-files=no", DOTFILES);
        if (dirty) BLOCK(`local git reset --hard would destroy uncommitted work in ~/.dotfiles (possibly another session's):\n${dirty}`);
      }
    }

    if (!DEPLOY.test(cmd)) return;

    if (PIPED.test(cmd))
      BLOCK("never pipe the deploy chain through tail/head/grep: $? becomes the filter's and a failed git fetch reads as EXIT=0. Redirect to a log file (> LOG 2>&1), then check the log and that the node's `git rev-parse HEAD` == origin/main.");
    if (/\bnohup\b/.test(cmd) && /\bssh\b/.test(cmd))
      BLOCK("never nohup/detach a remote install.sh: the detached sudo loses the forwarded ssh-agent and fails. Run it in the foreground over ssh -A.");
    if (/\bssh\b/.test(cmd) && sshWithoutA(cmd))
      BLOCK("remote deploys need agent forwarding: use ssh -A (sudo inside install.sh authenticates through the agent).");

    // install.sh does `git reset --hard origin/main` on the node: anything not pushed is silently reverted.
    const ahead = sh("git rev-list --count origin/main..HEAD", DOTFILES);
    if (ahead && ahead !== "0")
      BLOCK(`~/.dotfiles has ${ahead} commit(s) not pushed to origin/main; install.sh resets the node to origin/main and would deploy WITHOUT them. git push origin main first.`);

    // One deploy per machine at a time (two runs race each other's git reset + rebuild).
    if (!/\bssh\b/.test(cmd)) {
      const running = sh("pgrep -af '[i]nstall.sh /home'");
      if (running) BLOCK(`another install.sh is already running on this machine:\n${running}`);
    }
  },
});

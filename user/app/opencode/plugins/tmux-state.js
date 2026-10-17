// OpenCode plugin: the tmux tab-state icons Claude Code gets from its hooks (.claude/hooks/tmux-claude-state.sh —
// hourglass busy, red ! waiting for a permission/question, check done, cleared when the tab is in view), fed from
// OpenCode's plugin hooks and bus events. Needs TMUX_PANE in the environment (inherited from the pane's shell).
// Subagent sessions also go idle; only a session without parentID marks the pane done.
import { execFile } from "node:child_process";

const HOOK = `${process.env.HOME}/.dotfiles/.claude/hooks/tmux-claude-state.sh`;
const PANE = process.env.TMUX_PANE;

const set = (state) => {
  if (!PANE) return;
  try {
    const p = execFile(HOOK, [state], { timeout: 3000, stdio: ["pipe", "ignore", "ignore"] }, () => {});
    p.stdin?.end("{}");
  } catch {}
};

export const TmuxState = async ({ client }) => {
  const isRoot = async (id) => {
    try {
      const r = await client.session.get({ path: { id } });
      return !(r?.data?.parentID);
    } catch { return true; }
  };
  return {
    "chat.message": async () => set("busy"),
    "tool.execute.before": async (input) => set(input?.tool === "question" ? "ask" : "busy"),
    "permission.ask": async () => set("ask"),
    event: async ({ event }) => {
      switch (event?.type) {
        case "permission.updated": set("ask"); break;
        case "permission.replied": set("busy"); break;
        case "session.idle":
        case "session.error": {
          const id = event?.properties?.sessionID;
          if (!id || await isRoot(id)) set("done");
          break;
        }
      }
    },
  };
};

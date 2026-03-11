#!/usr/bin/env node
/**
 * Claude Code SDK Bridge
 *
 * JSON-lines IPC bridge between Python Matrix bot and Claude Code SDK.
 * Reads commands from stdin, writes events to stdout.
 * Spawned per-query, exits after completion.
 *
 * Deploy to: ~/.claude-matrix-bot/bridge/bridge.mjs on VPS_PROD
 */

import { query } from "@anthropic-ai/claude-code";
import { createInterface } from "readline";
import { randomUUID } from "crypto";

// Tools that are auto-approved (read-only, no side effects)
const AUTO_APPROVE_TOOLS = new Set([
  "Read",
  "Glob",
  "Grep",
  "WebFetch",
  "WebSearch",
  "ListMcpResourcesTool",
  "ReadMcpResourceTool",
  "ToolSearch",
]);

// Pending permission requests: requestId -> { resolve }
const pendingPermissions = new Map();
let activeQuery = null;

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function debug(...args) {
  process.stderr.write(`[bridge] ${args.join(" ")}\n`);
}

// Set up stdin line reader
const rl = createInterface({ input: process.stdin, terminal: false });

rl.on("line", (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    send({ type: "error", message: "Invalid JSON on stdin" });
    return;
  }

  switch (msg.type) {
    case "query":
      handleQuery(msg).catch((err) => {
        send({ type: "error", message: err.message || String(err) });
        process.exit(1);
      });
      break;
    case "permission_response":
      handlePermissionResponse(msg);
      break;
    case "abort":
      handleAbort();
      break;
    default:
      debug(`Unknown message type: ${msg.type}`);
  }
});

rl.on("close", () => {
  debug("stdin closed, exiting");
  if (activeQuery) {
    try {
      activeQuery.close();
    } catch {}
  }
  process.exit(0);
});

function handlePermissionResponse(msg) {
  const pending = pendingPermissions.get(msg.requestId);
  if (pending) {
    pending.resolve(msg.action);
    pendingPermissions.delete(msg.requestId);
  } else {
    debug(`No pending permission for requestId=${msg.requestId}`);
  }
}

function handleAbort() {
  if (activeQuery) {
    try {
      activeQuery.close();
    } catch {}
    activeQuery = null;
  }
  // Reject all pending permissions
  for (const [, pending] of pendingPermissions) {
    pending.resolve("deny");
  }
  pendingPermissions.clear();
  process.exit(0);
}

async function handleQuery(msg) {
  const timeoutMs = (msg.permissionTimeout || 300) * 1000;

  const options = {
    cwd: msg.workingDir || process.cwd(),
    allowedTools: [...AUTO_APPROVE_TOOLS],
    settingSources: ["user", "project"],
    permissionMode: "default",
    canUseTool: async (toolName, input) => {
      // Double-check auto-approve (belt + suspenders with allowedTools)
      if (AUTO_APPROVE_TOOLS.has(toolName)) {
        return { behavior: "allow" };
      }

      // Auto-approve Task with Explore subagent
      if (toolName === "Task" && input?.subagent_type === "Explore") {
        return { behavior: "allow" };
      }

      // Request permission from Python -> Matrix
      const requestId = randomUUID();
      send({
        type: "permission_request",
        requestId,
        tool: toolName,
        input: summarizeInput(input),
      });

      // Wait for user response with timeout
      return new Promise((resolve) => {
        const timer = setTimeout(() => {
          pendingPermissions.delete(requestId);
          send({ type: "permission_timeout", requestId });
          resolve({ behavior: "deny", message: "Permission timed out" });
        }, timeoutMs);

        pendingPermissions.set(requestId, {
          resolve: (action) => {
            clearTimeout(timer);
            resolve(
              action === "allow"
                ? { behavior: "allow" }
                : { behavior: "deny", message: "Denied by user" }
            );
          },
        });
      });
    },
  };

  // System prompt: extend Claude Code's built-in prompt
  if (msg.systemPrompt) {
    options.systemPrompt = {
      type: "preset",
      preset: "claude_code",
      append: msg.systemPrompt,
    };
  }

  // Resume existing session
  if (msg.sessionId) {
    options.resume = msg.sessionId;
  }

  debug(
    `Query start | resume=${msg.sessionId || "new"} | cwd=${options.cwd}`
  );

  try {
    activeQuery = query({ prompt: msg.message, options });

    let accumulatedText = "";
    let sessionId = null;

    for await (const event of activeQuery) {
      // Capture session ID from any event that has one
      if (event.sessionId && !sessionId) {
        sessionId = event.sessionId;
        send({ type: "session_id", sessionId });
      }

      if (event.type === "assistant") {
        const newText = extractText(event.message?.content);
        if (newText) {
          accumulatedText += newText;
          send({ type: "text_chunk", text: accumulatedText });
        }
      } else if (event.type === "result") {
        // Final result — may contain the complete response text
        if (typeof event.result === "string" && event.result) {
          accumulatedText = event.result;
        }
        if (event.sessionId) {
          sessionId = event.sessionId;
        }
      }

      debug(`Event: ${event.type}`);
    }

    send({
      type: "complete",
      result: accumulatedText,
      sessionId,
    });
  } catch (err) {
    send({ type: "error", message: err.message || String(err) });
  }

  activeQuery = null;
  debug("Query complete, exiting");
  process.exit(0);
}

function extractText(content) {
  if (!Array.isArray(content)) return "";
  return content
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

function summarizeInput(input) {
  // Truncate long values for display in permission prompts
  if (!input || typeof input !== "object") return input;
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (typeof value === "string" && value.length > 1000) {
      result[key] = value.slice(0, 997) + "...";
    } else {
      result[key] = value;
    }
  }
  return result;
}

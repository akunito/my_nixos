#!/usr/bin/env python3
"""
Permission Manager for Matrix-Claude bridge.

Tracks pending tool permission requests per room, enabling /yes and /no
command routing from Matrix to the bridge.

Deploy to: ~/.claude-matrix-bot/permission_manager.py on VPS_PROD
"""

import time
from typing import Optional


class PermissionManager:
    """Tracks pending tool permission requests per room."""

    def __init__(self):
        self._pending = {}  # room_id -> {requestId, tool, input, timestamp}

    def has_pending(self, room_id: str) -> bool:
        return room_id in self._pending

    def set_pending(
        self, room_id: str, request_id: str, tool: str, input_data: dict
    ):
        self._pending[room_id] = {
            "requestId": request_id,
            "tool": tool,
            "input": input_data,
            "timestamp": time.time(),
        }

    def resolve(self, room_id: str, action: str) -> Optional[dict]:
        """Resolve a pending request. Returns IPC message dict or None."""
        pending = self._pending.pop(room_id, None)
        if not pending:
            return None
        return {
            "type": "permission_response",
            "requestId": pending["requestId"],
            "action": action,
        }

    def clear(self, room_id: str):
        self._pending.pop(room_id, None)

    def clear_all(self):
        self._pending.clear()

    def get_display(self, room_id: str) -> Optional[str]:
        """Get formatted markdown string for pending permission."""
        pending = self._pending.get(room_id)
        if not pending:
            return None

        tool = pending["tool"]
        input_data = pending.get("input", {})

        lines = ["**Permission Required**", f"**Tool**: {tool}"]

        # Format input based on tool type
        if tool == "Bash":
            cmd = input_data.get("command", "")
            lines.append(f"**Command**: `{cmd}`")
        elif tool == "Write":
            path = input_data.get("file_path", "")
            lines.append(f"**File**: `{path}`")
        elif tool == "Edit":
            path = input_data.get("file_path", "")
            old = input_data.get("old_string", "")
            preview = old[:100] + ("..." if len(old) > 100 else "")
            lines.append(f"**File**: `{path}`")
            if preview:
                lines.append(f"**Replacing**: `{preview}`")
        elif tool == "NotebookEdit":
            path = input_data.get("notebook_path", "")
            lines.append(f"**Notebook**: `{path}`")
        else:
            # Generic: show first key-value pairs
            for k, v in list(input_data.items())[:2]:
                val = str(v)[:100]
                lines.append(f"**{k}**: `{val}`")

        elapsed = int(time.time() - pending["timestamp"])
        remaining = max(0, 300 - elapsed)

        lines.append("")
        lines.append(
            f"Reply `/yes` to approve or `/no` to deny ({remaining}s remaining)"
        )

        return "\n".join(lines)

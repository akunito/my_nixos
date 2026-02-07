#!/usr/bin/env python3
"""
Session Manager

SQLite-based session persistence for Matrix users.
Tracks Claude Code sessions, working directories, and activity.

Deploy to: ~/.claude-matrix-bot/session_manager.py on LXC_matrix
"""

import asyncio
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import aiosqlite
import structlog

log = structlog.get_logger()


class SessionManager:
    """Manages user sessions with SQLite persistence."""

    def __init__(self, db_path: str = "sessions.db"):
        self.db_path = Path(db_path)
        self.db: Optional[aiosqlite.Connection] = None

    async def initialize(self):
        """Initialize the database and create tables."""
        # Ensure parent directory exists
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self.db = await aiosqlite.connect(str(self.db_path))
        self.db.row_factory = aiosqlite.Row

        await self.db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                matrix_id TEXT PRIMARY KEY,
                claude_session_id TEXT,
                working_dir TEXT NOT NULL,
                last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                message_count INTEGER DEFAULT 0
            )
        """)

        await self.db.execute("""
            CREATE TABLE IF NOT EXISTS message_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                matrix_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (matrix_id) REFERENCES sessions(matrix_id)
            )
        """)

        await self.db.commit()
        log.info("Session database initialized", path=str(self.db_path))

    async def close(self):
        """Close database connection."""
        if self.db:
            await self.db.close()
            log.info("Session database closed")

    async def get_session(self, matrix_id: str) -> Optional[dict]:
        """Get session for a Matrix user."""
        async with self.db.execute(
            "SELECT * FROM sessions WHERE matrix_id = ?",
            (matrix_id,)
        ) as cursor:
            row = await cursor.fetchone()
            if row:
                return dict(row)
        return None

    async def get_or_create_session(
        self,
        matrix_id: str,
        default_working_dir: str = None,
    ) -> dict:
        """Get existing session or create a new one."""
        session = await self.get_session(matrix_id)

        if session:
            # Update last active timestamp
            await self.db.execute(
                "UPDATE sessions SET last_active = CURRENT_TIMESTAMP WHERE matrix_id = ?",
                (matrix_id,)
            )
            await self.db.commit()
            return session

        # Create new session
        working_dir = default_working_dir or str(Path.home() / ".dotfiles")
        await self.db.execute(
            """
            INSERT INTO sessions (matrix_id, working_dir)
            VALUES (?, ?)
            """,
            (matrix_id, working_dir)
        )
        await self.db.commit()

        log.info("Created new session", matrix_id=matrix_id, working_dir=working_dir)
        return await self.get_session(matrix_id)

    async def update_claude_session(
        self,
        matrix_id: str,
        claude_session_id: str,
    ):
        """Update the Claude Code session ID for a user."""
        await self.db.execute(
            """
            UPDATE sessions
            SET claude_session_id = ?, last_active = CURRENT_TIMESTAMP
            WHERE matrix_id = ?
            """,
            (claude_session_id, matrix_id)
        )
        await self.db.commit()
        log.debug("Updated Claude session", matrix_id=matrix_id, session_id=claude_session_id[:8])

    async def update_working_dir(self, matrix_id: str, working_dir: str):
        """Update the working directory for a user's session."""
        await self.db.execute(
            """
            UPDATE sessions
            SET working_dir = ?, last_active = CURRENT_TIMESTAMP
            WHERE matrix_id = ?
            """,
            (working_dir, matrix_id)
        )
        await self.db.commit()
        log.info("Updated working directory", matrix_id=matrix_id, working_dir=working_dir)

    async def increment_message_count(self, matrix_id: str):
        """Increment the message count for a session."""
        await self.db.execute(
            """
            UPDATE sessions
            SET message_count = message_count + 1, last_active = CURRENT_TIMESTAMP
            WHERE matrix_id = ?
            """,
            (matrix_id,)
        )
        await self.db.commit()

    async def reset_session(self, matrix_id: str):
        """Reset a user's session (clear Claude session ID)."""
        await self.db.execute(
            """
            UPDATE sessions
            SET claude_session_id = NULL,
                message_count = 0,
                last_active = CURRENT_TIMESTAMP
            WHERE matrix_id = ?
            """,
            (matrix_id,)
        )
        await self.db.commit()
        log.info("Reset session", matrix_id=matrix_id)

    async def add_message_history(
        self,
        matrix_id: str,
        role: str,
        content: str,
    ):
        """Add a message to the history (for debugging/audit)."""
        await self.db.execute(
            """
            INSERT INTO message_history (matrix_id, role, content)
            VALUES (?, ?, ?)
            """,
            (matrix_id, role, content[:10000])  # Limit content size
        )
        await self.db.commit()

    async def cleanup_old_sessions(self, max_age_hours: int = 24):
        """Clean up sessions older than max_age_hours."""
        cutoff = datetime.now() - timedelta(hours=max_age_hours)

        async with self.db.execute(
            """
            SELECT matrix_id FROM sessions
            WHERE last_active < ? AND claude_session_id IS NOT NULL
            """,
            (cutoff.isoformat(),)
        ) as cursor:
            old_sessions = await cursor.fetchall()

        if old_sessions:
            await self.db.execute(
                """
                UPDATE sessions
                SET claude_session_id = NULL
                WHERE last_active < ?
                """,
                (cutoff.isoformat(),)
            )
            await self.db.commit()
            log.info("Cleaned up old sessions", count=len(old_sessions))

        return len(old_sessions)

    async def get_stats(self) -> dict:
        """Get session statistics."""
        stats = {}

        async with self.db.execute("SELECT COUNT(*) FROM sessions") as cursor:
            row = await cursor.fetchone()
            stats["total_sessions"] = row[0]

        async with self.db.execute(
            "SELECT COUNT(*) FROM sessions WHERE claude_session_id IS NOT NULL"
        ) as cursor:
            row = await cursor.fetchone()
            stats["active_sessions"] = row[0]

        async with self.db.execute("SELECT SUM(message_count) FROM sessions") as cursor:
            row = await cursor.fetchone()
            stats["total_messages"] = row[0] or 0

        return stats

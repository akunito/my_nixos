#!/bin/sh
# Smart SSH session manager
# Usage: ssh-smart.sh user@host
#
# Checks if a tmux session named 'user@host' exists
# If yes -> attaches to it
# If no -> creates it and connects
# If running in Kitty, uses 'kitten ssh' for better terminfo handling

HOST="$1"

if [ -z "$HOST" ]; then
    echo "Usage: ssh-smart.sh user@host"
    exit 1
fi

# Generate session name from host
SESSION_NAME="$HOST"

# Check if we're running in Kitty
if [ -n "$KITTY_WINDOW_ID" ] || [ "$TERM" = "xterm-kitty" ]; then
    SSH_CMD="kitten ssh"
else
    SSH_CMD="ssh"
fi

# Check if tmux session exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Session exists, attach to it
    tmux attach-session -t "$SESSION_NAME"
else
    # Session doesn't exist, create it and connect
    tmux new-session -d -s "$SESSION_NAME" "$SSH_CMD $HOST"
    tmux attach-session -t "$SESSION_NAME"
fi


#!/usr/bin/env python3
"""
Terminal Keybindings Configuration Script for VS Code and Cursor

This script patches keybindings.json files for VS Code and Cursor to ensure
proper terminal copy/paste behavior. It is idempotent and safe to run multiple times.

Required keybindings:
- Ctrl+V → workbench.action.terminal.paste (when terminal focused)
- Ctrl+C → workbench.action.terminal.copySelection (when terminal focused and text selected)
"""

import json
import os
import re
import shutil
from pathlib import Path

# --- Configuration ---
# The keybindings we want to enforce
REQUIRED_BINDINGS = [
    {
        "key": "ctrl+v",
        "command": "workbench.action.terminal.paste",
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+c",
        "command": "workbench.action.terminal.copySelection",
        "when": "terminalFocus && terminalTextSelected"
    }
]

# Paths to check (Expand user home directory ~)
# Adjust these if you are on macOS or standard Linux vs NixOS
TARGET_FILES = [
    Path.home() / ".config/Code/User/keybindings.json",   # VS Code (Linux)
    Path.home() / ".config/Cursor/User/keybindings.json", # Cursor (Linux)
    # Path.home() / "Library/Application Support/Code/User/keybindings.json", # VS Code (macOS)
    # Path.home() / "Library/Application Support/Cursor/User/keybindings.json", # Cursor (macOS)
]

# --- Helpers ---

def remove_comments(json_str):
    """
    Standard JSON library fails on // comments. 
    This simple regex strips lines starting with // or blocks /* */.
    """
    pattern = r'(\".*?\"|\'.*?\')|(/\*.*?\*/|//[^\r\n]*$)'
    # first group captures quoted strings (keep them)
    # second group captures comments (remove them)
    regex = re.compile(pattern, re.MULTILINE|re.DOTALL)
    def _replacer(match):
        if match.group(2) is not None:
            return "" # So we ignore the comment
        else: 
            return match.group(1) # So we keep the string
    return regex.sub(_replacer, json_str)

def entry_exists(existing_list, new_entry):
    """Check if an entry with the same key and command already exists."""
    for item in existing_list:
        if (item.get('key') == new_entry['key'] and 
            item.get('command') == new_entry['command']):
            return True
    return False

def patch_file(file_path):
    print(f"Checking: {file_path}")
    
    # 1. Ensure directory exists (for fresh installs)
    if not file_path.parent.exists():
        print(f"  -> Creating directory: {file_path.parent}")
        os.makedirs(file_path.parent, exist_ok=True)
    
    # 2. Create backup if file exists
    backup_path = None
    if file_path.exists():
        backup_path = file_path.with_suffix(file_path.suffix + '.bak')
        try:
            shutil.copy2(file_path, backup_path)
            print(f"  -> Created backup: {backup_path}")
        except Exception as e:
            print(f"  -> Warning: Could not create backup: {e}")
            # Continue anyway - user can manually backup if needed
    
    # 3. Read existing data
    data = []
    if file_path.exists():
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                # fast fail if empty
                if not content.strip():
                    data = []
                else:
                    clean_content = remove_comments(content)
                    data = json.loads(clean_content)
        except json.JSONDecodeError as e:
            print(f"  -> Error: Could not parse existing JSON in {file_path}. Is it valid?")
            print(f"  -> Details: {e}")
            if backup_path and backup_path.exists():
                print(f"  -> Backup available at: {backup_path}")
            return
    else:
        print(f"  -> File doesn't exist, creating new.")

    # 4. Patch data
    modified = False
    if not isinstance(data, list):
        print(f"  -> Error: Root of JSON is not a list. Cannot patch.")
        return

    for binding in REQUIRED_BINDINGS:
        if not entry_exists(data, binding):
            data.append(binding)
            print(f"  -> Added missing rule: {binding['key']} -> {binding['command']}")
            modified = True
        else:
            print(f"  -> Rule exists: {binding['key']}")

    # 5. Write back if modified
    if modified:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=4)
            print(f"  -> Saved changes to {file_path}")
        except Exception as e:
            print(f"  -> Failed to write file: {e}")
            if backup_path and backup_path.exists():
                print(f"  -> Original file preserved in backup: {backup_path}")
    else:
        print("  -> No changes needed.")
    print("-" * 40)

# --- Main ---
if __name__ == "__main__":
    print("Starting Keybinding Check...\n")
    for path in TARGET_FILES:
        patch_file(path)
    print("Done.")


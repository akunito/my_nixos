import os
import re

VAULT_PATH = "/home/akunito/Nextcloud/myLibrary/MyDocuments/My_Notes_Diego"
PLANE_BASE_URL = "https://plane.akunito.com/api"
WORKSPACE_SLUG = "akuworkspace"

# Project IDs
IAKU_PROJECT_ID = "ea5c0b30-a3ab-4ab3-bd11-a4b47d3d7171"
AWN_PROJECT_ID = "ec30de69-c749-4506-9441-9690753391f5"

# AWN state UUIDs
AWN_STATES = {
    "Backlog": "689e5cf8-f196-4bdb-892b-2d3d29e4fe57",
    "Todo": "65ba5e69-ba15-4e5c-9e1f-162799caeec1",
    "In Progress": "b23a317a-7d8a-4dac-8965-2db9e2317739",
    "On Hold": "8f56e099-cbe8-4995-b7eb-7406a07d6608",
    "Done": "b2edbb1a-a9af-4d4e-839c-9b40a214fa69",
    "Cancelled": "b18075bb-68c6-492e-acd6-d2a521df7dd3",
}

# Kanban column to AWN state mapping
KANBAN_STATE_MAP = {
    "Important": "Backlog",
    "Backlog": "Backlog",
    "TODO": "Todo",
    "In Progress": "In Progress",
    "On Hold": "On Hold",
    "Done": "Done",
    "Deprecated": "Cancelled",
}

# Nextcloud share base URL
NEXTCLOUD_BASE = "https://nextcloud.akunito.com"
NEXTCLOUD_SHARE_TOKEN = os.environ.get("NEXTCLOUD_SHARE_TOKEN", "FCH7moejgL6dZdb")

# Secrets path for API token
SECRETS_PATH = os.path.expanduser("~/.dotfiles/secrets/domains.nix")

# Rate limiting
API_DELAY_SECONDS = 0.5

# State file for resumability
STATE_FILE = os.path.join(os.path.dirname(__file__), "migration_state.json")
CLASSIFICATION_FILE = os.path.join(os.path.dirname(__file__), "classification_review.json")

# Files/dirs to skip
SKIP_DIRS = {".obsidian", ".trash", "Templates"}
SKIP_FILES = {"Kanban Computer.md", "Kanban NixOS.md", "Kanban Template.md"}

# Minimum file size to migrate (skip empty hub files)
MIN_FILE_SIZE_BYTES = 50

# Work-related keywords (route to AWN)
WORK_KEYWORDS = [
    "Active Directory", "BEAM", "Power BI", "Schenker", "Bee360", "bee360",
    "BeeAPI", "bee4it", "SSMS", "SQL Server", "ServiceNow", "Camunda",
    "Dynatrace", "INC00", "J870", "J681", "J1076", "ENOVA", "OHS",
    "SIMS Interface", "FTE target", "EI Lifecycle", "Datasets guide",
    "export daily actuals", "app factsheet", "Optimize Merging csv",
    "Employee   Supervisor", "edge - install extensions",
    "Justyna", "Gaurav", "Sabine", "Monika", "Karen", "Johannes",
    "PZU", "Clausmark",
]

# Category prefix rules for IT Documentation Source files
IT_DOC_CATEGORIES = {
    "Proxmox": "[Proxmox]",
    "Docker": "[Docker]",
    "NixOS": "[NixOS]",
    "Nix ": "[Nix]",
    "nix-": "[Nix]",
    "Azure": "[Azure]",
    "Linux": "[Linux]",
    "Arch ": "[Arch Linux]",
    "Arch-": "[Arch Linux]",
    "CSS": "[Web Dev]",
    "HTML": "[Web Dev]",
    "Rails": "[Web Dev]",
    "Django": "[Web Dev]",
    "python": "[Python]",
    "Python": "[Python]",
    "Ruby": "[Ruby]",
    "Git ": "[Git]",
    "git-": "[Git]",
    "TrueNAS": "[TrueNAS]",
    "K8s": "[Kubernetes]",
    "k3s": "[Kubernetes]",
    "k8s": "[Kubernetes]",
    "2FA": "[Security]",
    "Wireguard": "[VPN]",
    "WireGuard": "[VPN]",
    "VPN": "[VPN]",
    "Tailscale": "[Networking]",
    "tailscale": "[Networking]",
    "pfsense": "[pfSense]",
    "pfSense": "[pfSense]",
    "Router": "[Networking]",
    "DNS": "[Networking]",
    "Cronjob": "[Automation]",
    "cron": "[Automation]",
    "Cloudflare": "[Networking]",
    "nginx": "[Networking]",
    "Nextcloud": "[Self-Hosted]",
    "Matrix": "[Self-Hosted]",
    "Grafana": "[Monitoring]",
    "Prometheus": "[Monitoring]",
    "VPS": "[VPS]",
    "ssh": "[SSH]",
    "SSH": "[SSH]",
    "LUKS": "[Security]",
    "Sway": "[Desktop]",
    "plasma": "[Desktop]",
    "Hyprland": "[Desktop]",
    "tmux": "[Tools]",
    "vim": "[Tools]",
    "neovim": "[Tools]",
    "zsh": "[Tools]",
    "bat ": "[Tools]",
    "Btop": "[Tools]",
    "Atuin": "[Tools]",
    "fzf": "[Tools]",
    "Ansible": "[DevOps]",
    "Terraform": "[DevOps]",
    "Arduino": "[Hardware]",
    "Raspberry": "[Hardware]",
    "gaming": "[Gaming]",
    "Steam": "[Gaming]",
    "Skyrim": "[Gaming]",
    "poe2": "[Gaming]",
    "Runescape": "[Gaming]",
    "emulator": "[Gaming]",
    "Excalidraw": "[Diagram]",
    "fitness": "[Personal]",
    "powerlifting": "[Personal]",
    "finance": "[Personal]",
    "Economy": "[Personal]",
    "Poland": "[Personal]",
    "Chinese": "[Personal]",
}

# AWN category rules
AWN_CATEGORIES = {
    "BEAM": "[BEAM]",
    "Bee360": "[Bee360]",
    "bee360": "[Bee360]",
    "BeeAPI": "[Bee360]",
    "bee4it": "[Bee360]",
    "Power BI": "[PowerBI]",
    "PBI": "[PowerBI]",
    "pbi": "[PowerBI]",
    "SQL": "[SQL]",
    "Camunda": "[Camunda]",
    "Dynatrace": "[Monitoring]",
    "ServiceNow": "[ServiceNow]",
    "Service NOW": "[ServiceNow]",
    "Active Directory": "[AD]",
    "Schenker": "[Schenker]",
}


def get_nextcloud_share_url(relative_path: str) -> str:
    """Build Nextcloud public share download URL for a file.

    Uses format: /s/TOKEN/download?path=/DIRECTORY&files=FILENAME
    """
    import urllib.parse

    if NEXTCLOUD_SHARE_TOKEN:
        # Split into directory and filename
        parts = relative_path.rsplit("/", 1)
        if len(parts) == 2:
            directory = "/" + parts[0]
            filename = parts[1]
        else:
            directory = "/"
            filename = parts[0]

        dir_encoded = urllib.parse.quote(directory)
        file_encoded = urllib.parse.quote(filename)
        return f"{NEXTCLOUD_BASE}/s/{NEXTCLOUD_SHARE_TOKEN}/download?path={dir_encoded}&files={file_encoded}"

    # Fallback: WebDAV URL (requires auth)
    encoded = urllib.parse.quote(relative_path)
    return f"{NEXTCLOUD_BASE}/remote.php/dav/files/akunito/myLibrary/MyDocuments/My_Notes_Diego/{encoded}"


def read_plane_token() -> str:
    """Read planeApiToken from secrets/domains.nix."""
    with open(SECRETS_PATH) as f:
        content = f.read()
    match = re.search(r'planeApiToken\s*=\s*"([^"]+)"', content)
    if match:
        return match.group(1)
    raise ValueError(f"planeApiToken not found in {SECRETS_PATH}")

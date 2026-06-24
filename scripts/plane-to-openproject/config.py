"""Configuration for the Plane -> OpenProject demo migration.

Read-only against Plane (only GET), writes only to the disposable OpenProject
demo instance. Nothing here mutates the live Plane workspace.
"""
import os
import re

# --- Plane (SOURCE, read-only) ---------------------------------------------
# Pages live on the patched internal `/api/` (see obsidian-to-plane notes);
# issues/states/labels use the public `/api/v1/`.
# PLANE_BASE_URL may be set in the environment to the bare host (e.g. the VPS
# exports "https://plane.akunito.com" with no /api). Normalize so /api is always
# present, accepting host, host/api, or host/api/v1.
_plane_raw = os.environ.get("PLANE_BASE_URL", "https://plane.akunito.com").rstrip("/")
if _plane_raw.endswith("/api/v1"):
    _plane_raw = _plane_raw[: -len("/v1")]
if not _plane_raw.endswith("/api"):
    _plane_raw = _plane_raw + "/api"
PLANE_BASE = _plane_raw                 # .../api      (pages live here)
PLANE_BASE_V1 = PLANE_BASE + "/v1"      # .../api/v1   (issues/states/labels)
WORKSPACE_SLUG = os.environ.get("PLANE_WORKSPACE_SLUG", "akuworkspace")
AINF_PROJECT_ID = "ea5c0b30-a3ab-4ab3-bd11-a4b47d3d7171"

# --- OpenProject (TARGET, write) -------------------------------------------
# Run on the VPS against the loopback port, or over Tailscale against the vhost.
OP_BASE_URL = os.environ.get("OP_BASE_URL", "http://127.0.0.1:8200")
OP_PROJECT_NAME = "AINF Demo"
OP_PROJECT_IDENTIFIER = "ainf-demo"
OP_DEFAULT_TYPE = "Task"

# --- Mappings ---------------------------------------------------------------
# Plane state "group" -> OpenProject default status name.
# Plane groups: backlog, unstarted, started, completed, cancelled.
STATE_GROUP_TO_OP_STATUS = {
    "backlog": "New",
    "unstarted": "New",
    "started": "In progress",
    "completed": "Closed",
    "cancelled": "Rejected",
}
OP_STATUS_FALLBACK = "New"

# Plane priority -> OpenProject default priority name.
PRIORITY_TO_OP = {
    "urgent": "Immediate",
    "high": "High",
    "medium": "Normal",
    "low": "Low",
    "none": "Normal",
}
OP_PRIORITY_FALLBACK = "Normal"

# How many AINF pages to sample for the wiki-fidelity test.
SAMPLE_PAGES_COUNT = int(os.environ.get("SAMPLE_PAGES", "25"))

# Idempotent resume state.
STATE_FILE = os.path.join(os.path.dirname(__file__), "migration_state.json")

# Reuse the obsidian migration's Nextcloud public-share image handling.
NEXTCLOUD_BASE = "https://nextcloud.akunito.com"
NEXTCLOUD_SHARE_TOKEN = os.environ.get("NEXTCLOUD_SHARE_TOKEN", "FCH7moejgL6dZdb")

SECRETS_PATH = os.path.expanduser("~/.dotfiles/secrets/domains.nix")
API_DELAY_SECONDS = 0.4


def _read_secret(key: str, env_var: str) -> str:
    """Prefer an env var; otherwise read `key = "..."` from secrets/domains.nix."""
    val = os.environ.get(env_var)
    if val:
        return val
    try:
        with open(SECRETS_PATH) as f:
            content = f.read()
    except FileNotFoundError:
        raise ValueError(
            f"{key} not in env (${env_var}) and {SECRETS_PATH} not found. "
            f"Set ${env_var} (e.g. when running on the VPS)."
        )
    match = re.search(rf'{re.escape(key)}\s*=\s*"([^"]+)"', content)
    if match:
        return match.group(1)
    raise ValueError(f"{key} not found in {SECRETS_PATH} and ${env_var} unset.")


def read_plane_token() -> str:
    return _read_secret("planeApiToken", "PLANE_API_KEY")


def read_op_api_key() -> str:
    # The OpenProject demo admin generates this in: My account -> Access tokens -> API.
    return _read_secret("openProjectDemoApiKey", "OP_API_KEY")

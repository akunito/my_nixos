import os
import re

# =============================================================================
# API Endpoints
# =============================================================================
LINEAR_API_ENDPOINT = "https://api.linear.app/graphql"
PLANE_BASE_URL = "https://plane.akunito.com/api"
WORKSPACE_SLUG = "akuworkspace"

# =============================================================================
# Target Project
# =============================================================================
LW_PROJECT_ID = "3a917926-76e4-420f-b729-3dfbb76b4602"

# Linear source filters
LINEAR_TEAM_KEY = "aku & komi projects"  # Team name in Linear
LINEAR_PROJECT_NAME = "Lefty Workout App"  # Project name in Linear

# =============================================================================
# User Mapping (Linear email → Plane UUID)
# =============================================================================
USER_MAP = {
    # Diego (akunito)
    "diego88aku@gmail.com": "794b4ebf-4f96-4532-85e1-24f1b6683fef",
    # Misia (Komi)
    "michalina.kowalczyk@proton.me": "b24d5e9a-f2f6-4d69-9326-d51c1b7929dd",
}

# =============================================================================
# State Mapping (Linear state name/type → Plane state UUID for LW project)
# =============================================================================
PLANE_STATES = {
    "Backlog": "8a2d66f3-2c7d-4c41-aefd-aaf77931a3c8",
    "Icebox": "60d40ecf-d186-4379-8bd8-bc52afa1f010",
    "Todo": "9de4e6aa-772e-4293-8cf9-ddf8ea642909",
    "In Progress": "0fde0d1f-9945-4f2a-b57c-a4e24f5a3167",
    "In Review": "d01a3450-1207-42b9-88cb-7f8c65ca7ec4",
    "Done": "81130f16-6cb2-455b-9a12-640031ea3545",
    "Cancelled": "f20d5556-29e9-4891-bf93-8a2fc7957502",
}

# Map Linear state type to Plane state name (fallback when name doesn't match)
STATE_TYPE_MAP = {
    "backlog": "Backlog",
    "unstarted": "Todo",
    "started": "In Progress",
    "completed": "Done",
    "canceled": "Cancelled",
    "triage": "Icebox",
}

# =============================================================================
# Priority Mapping (Linear int → Plane string)
# =============================================================================
PRIORITY_MAP = {
    0: "none",
    1: "urgent",
    2: "high",
    3: "medium",
    4: "low",
}

# =============================================================================
# Rate Limiting
# =============================================================================
LINEAR_DELAY_SECONDS = 0.5
PLANE_DELAY_SECONDS = 0.5

# =============================================================================
# Paths
# =============================================================================
SECRETS_PATH = os.path.expanduser("~/.dotfiles/secrets/domains.nix")
STATE_FILE = os.path.join(os.path.dirname(__file__), "migration_state.json")
EXPORT_FILE = os.path.join(os.path.dirname(__file__), "linear_export.json")


# =============================================================================
# Secret Readers
# =============================================================================
def read_linear_token() -> str:
    """Read linearApiToken from secrets/domains.nix."""
    with open(SECRETS_PATH) as f:
        content = f.read()
    match = re.search(r'linearApiToken\s*=\s*"([^"]+)"', content)
    if match:
        return match.group(1)
    raise ValueError(f"linearApiToken not found in {SECRETS_PATH}")


def read_plane_token() -> str:
    """Read planeApiToken from secrets/domains.nix."""
    with open(SECRETS_PATH) as f:
        content = f.read()
    match = re.search(r'planeApiToken\s*=\s*"([^"]+)"', content)
    if match:
        return match.group(1)
    raise ValueError(f"planeApiToken not found in {SECRETS_PATH}")


def map_linear_state(state_name: str, state_type: str) -> str:
    """Map a Linear state to a Plane state UUID.

    Tries name match first, then falls back to type-based mapping.
    """
    # Explicit name overrides (Linear name → Plane name)
    name_overrides = {
        "Review": "In Review",
        "Duplicate": "Cancelled",
    }
    if state_name in name_overrides:
        return PLANE_STATES[name_overrides[state_name]]

    # Direct name match
    if state_name in PLANE_STATES:
        return PLANE_STATES[state_name]

    # Fuzzy name match (case-insensitive)
    for plane_name, plane_id in PLANE_STATES.items():
        if state_name.lower() == plane_name.lower():
            return plane_id

    # Type-based fallback
    plane_state_name = STATE_TYPE_MAP.get(state_type, "Backlog")
    return PLANE_STATES[plane_state_name]


def map_linear_priority(linear_priority: int) -> str:
    """Map Linear priority (0-4) to Plane priority string."""
    return PRIORITY_MAP.get(linear_priority, "none")


def map_linear_user(email: str) -> str | None:
    """Map Linear user email to Plane user UUID. Returns None if not found."""
    return USER_MAP.get(email)

"""Generate a Zen spaces/pins Nix module from the extracted Vivaldi tree.

Vivaldi          -> Zen
  workspace      -> space
  tab stack      -> folder (pin with isGroup, children nested)
  tab            -> pinned tab inside that folder
Loose tabs land directly in the space.

UUIDs are derived deterministically (uuid5) so rebuilds keep the same ids —
changing a space id re-creates it and loses its tabs.
"""
import json, os, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "vivaldi-tabs.json")
DEST = os.path.join(HERE, "zen-spaces.nix")
NS = uuid.UUID("6ba7b811-9dad-11d1-80b4-00c04fd430c8")

# emoji per workspace, read straight from Vivaldi's Preferences
VIV = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
icons = {}
try:
    for w in json.load(open(VIV))["vivaldi"]["workspaces"]["list"]:
        icons[w["name"]] = w.get("emoji", "")
except Exception:
    pass

data = json.load(open(SRC))["workspaces"]


def uid(*parts):
    return str(uuid.uuid5(NS, "|".join(parts)))


def nixstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${") + '"'


def title_of(tab):
    t = (tab.get("title") or "").strip() or tab["url"]
    return t[:80]


def unique(name, used):
    """Nix attrsets need unique keys; two tabs can share a title."""
    if name not in used:
        used.add(name)
        return name
    i = 2
    while f"{name} ({i})" in used:
        i += 1
    out = f"{name} ({i})"
    used.add(out)
    return out


def skip(tab):
    """Drop tabs captured mid-auth-redirect. These carry a signed JWT in the
    query string, are expired the moment they're written, and must not land in
    a tracked file."""
    u = tab["url"]
    return "cloudflareaccess.com/cdn-cgi/access/login" in u or "/oauth2/authorize" in u or "/oauth2/v2.0/authorize" in u


out = ["# GENERATED from Vivaldi session data — see scratchpad/gen_spaces.py.",
       "# Vivaldi workspace -> Zen space, tab stack -> folder, tab -> pinned tab.",
       "{ ... }:", "{",
       '  programs.zen-browser.profiles."Default (release)" = {',
       "    spaces = {"]

space_pos = 1000
n_spaces = n_folders = n_pins = 0

for ws, groups in data.items():
    if ws == "(no workspace)":
        ws_name, icon = "Unsorted", "📦"
    else:
        ws_name, icon = ws, icons.get(ws, "")

    out.append(f'      {nixstr(ws_name)} = {{')
    out.append(f'        id = "{uid("space", ws_name)}";')
    out.append(f"        position = {space_pos};")
    if icon:
        out.append(f"        icon = {nixstr(icon)};")
    out.append("        pins = {")

    pos = 100
    n_spaces += 1
    used_space = set()
    urls_space = set()

    # loose tabs first
    for tab in groups.get("(ungrouped)", []):
        if skip(tab) or tab["url"] in urls_space:
            continue
        urls_space.add(tab["url"])
        out.append(f'          {nixstr(unique(title_of(tab), used_space))} = {{')
        out.append(f'            id = "{uid("pin", ws_name, tab["url"])}";')
        out.append(f'            url = {nixstr(tab["url"])};')
        out.append(f"            position = {pos};")
        out.append("          };")
        pos += 1
        n_pins += 1

    # then each group as a folder with children nested inside
    for group, tabs in groups.items():
        if group == "(ungrouped)":
            continue
        # Vivaldi shows unnamed stacks by their active tab's title, so a raw
        # "stack <id>" folder name would be meaningless here.
        if group.startswith("stack ") and tabs:
            group = (tabs[0].get("title") or tabs[0]["url"])[:40]
        out.append(f'          {nixstr(unique(group, used_space))} = {{')
        out.append(f'            id = "{uid("folder", ws_name, group)}";')
        out.append(f"            position = {pos};")
        out.append("            isFolderCollapsed = true;")
        out.append("            editedTitle = true;")
        out.append("            pins = {")
        pos += 1
        n_folders += 1
        used_folder = set()
        urls_folder = set()
        for tab in tabs:
            if skip(tab) or tab["url"] in urls_folder:
                continue
            urls_folder.add(tab["url"])
            out.append(f'              {nixstr(unique(title_of(tab), used_folder))} = {{')
            out.append(f'                id = "{uid("pin", ws_name, group, tab["url"])}";')
            out.append(f'                url = {nixstr(tab["url"])};')
            out.append(f"                position = {pos};")
            out.append("              };")
            pos += 1
            n_pins += 1
        out.append("            };")
        out.append("          };")

    out.append("        };")
    out.append("      };")
    space_pos += 1000

out += ["    };", "  };", "}"]
open(DEST, "w").write("\n".join(out) + "\n")
print(f"{n_spaces} spaces, {n_folders} folders, {n_pins} pinned tabs -> {DEST}")

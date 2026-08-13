"""Extract Vivaldi workspaces -> tab groups -> tabs into a portable JSON tree."""
import json, os, sys, glob, collections
from snss import records, Pickle

VIV = os.path.expanduser("~/.config/vivaldi/Default")

CMD_SET_TAB_WINDOW = 0
CMD_UPDATE_TAB_NAV = 6
CMD_SET_SELECTED_NAV_INDEX = 7
CMD_SET_PINNED = 12
CMD_TAB_EXTDATA = 21


def newest_session():
    files = glob.glob(os.path.join(VIV, "Sessions", "Session_*"))
    return max(files, key=os.path.getmtime)


def richest_session():
    """Vivaldi keeps several session files; the newest is often the current
    window only. Pick the one carrying the most workspace-tagged tabs."""
    best, best_n = None, -1
    for path in glob.glob(os.path.join(VIV, "Sessions", "Session_*")):
        try:
            _, _, ext, _, _ = parse_session(path)
        except Exception:
            continue
        n = sum(1 for e in ext.values() if e.get("workspaceId"))
        if n > best_n:
            best, best_n = path, n
    return best or newest_session()


def load_workspaces():
    prefs = json.load(open(os.path.join(VIV, "Preferences")))
    out = {}
    for w in prefs.get("vivaldi", {}).get("workspaces", {}).get("list", []):
        # ids are floats in Preferences, strings in tab extData
        out[str(int(w["id"]))] = {"name": w.get("name", "?"), "emoji": w.get("emoji", "")}
    return out


def parse_session(path):
    navs = collections.defaultdict(dict)   # tab_id -> {nav_index: (url, title)}
    selected = {}                          # tab_id -> nav_index
    ext = {}                               # tab_id -> extData dict
    pinned = set()
    window_of = {}                         # tab_id -> window_id

    for cmd, payload in records(path):
        try:
            p = Pickle(payload)
            p.u32()  # pickle payload size
            if cmd == CMD_UPDATE_TAB_NAV:
                tab = p.i32(); idx = p.i32()
                url = p.string(); title = p.string16()
                navs[tab][idx] = (url, title)
            elif cmd == CMD_SET_SELECTED_NAV_INDEX:
                tab = p.i32(); selected[tab] = p.i32()
            elif cmd == CMD_TAB_EXTDATA:
                tab = p.i32()
                ext[tab] = json.loads(p.string())
            elif cmd == CMD_SET_PINNED:
                tab = p.i32()
                if p.i32():
                    pinned.add(tab)
            elif cmd == CMD_SET_TAB_WINDOW:
                win = p.i32(); window_of[p.i32()] = win
        except Exception:
            continue
    return navs, selected, ext, pinned, window_of


def main():
    session = sys.argv[1] if len(sys.argv) > 1 else newest_session()
    workspaces = load_workspaces()
    navs, selected, ext, pinned, window_of = parse_session(session)

    tree = collections.defaultdict(lambda: collections.defaultdict(list))
    orphans = []
    for tab, entries in navs.items():
        idx = selected.get(tab, max(entries))
        url, title = entries.get(idx) or entries[max(entries)]
        if not url or url.startswith(("chrome://", "vivaldi://", "about:", "chrome-extension://")):
            continue
        e = ext.get(tab, {})
        # workspaceId is a float in both Preferences and extData
        raw_ws = e.get("workspaceId")
        ws_id = str(int(float(raw_ws))) if raw_ws else ""
        ws = workspaces.get(ws_id, {}).get("name") if ws_id else None
        group = e.get("fixedGroupTitle") or (f"stack {e['group'][:8]}" if e.get("group") else None)
        rec = {"url": url, "title": title, "pinned": tab in pinned}
        if ws is None:
            orphans.append(rec)
        tree[ws or "(no workspace)"][group or "(ungrouped)"].append(rec)

    out = {
        "source_session": os.path.basename(session),
        "workspaces": {
            ws: {g: tabs for g, tabs in sorted(groups.items())}
            for ws, groups in sorted(tree.items())
        },
    }
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vivaldi-tabs.json")
    json.dump(out, open(dest, "w"), indent=2, ensure_ascii=False)

    total = 0
    print(f"session: {os.path.basename(session)}")
    print(f"{'workspace':<22} {'group':<30} tabs")
    for ws, groups in out["workspaces"].items():
        for g, tabs in groups.items():
            print(f"{ws:<22} {g:<30} {len(tabs)}")
            total += len(tabs)
    print(f"\nTOTAL {total} tabs -> {dest}")
    print(f"workspaces defined in Preferences: {[w['name'] for w in workspaces.values()]}")


if __name__ == "__main__":
    main()

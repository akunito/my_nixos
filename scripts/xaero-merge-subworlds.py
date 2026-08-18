#!/usr/bin/env python3
"""Merge two Xaero sub-worlds ("Overworld" duplicates) inside one instance.

Xaero's World Map splits a server into sub-worlds when the level id the server
reports changes.  The result is two entries in the World/Sub-World dropdown,
each holding half of the explored map and half of the waypoints.

There is no chunk-level merger for the current region.xaero format (the only
public tool, XaeroRegionMerger, only handles the pre-1.19 format), so this
merges at region granularity: for every 512x512 region present in either
sub-world, the copy holding more rendered data wins.  Waypoints merge fully.

    xaero-merge-subworlds.py <instance-dir> <server> <target-mw> <source-mw> \
        [--apply] [--archive DIR] [--name LABEL] [--waypoints-only]

Pass "all" as <server> to process every server folder in the instance.  If the
target sub-world does not exist yet the source is simply renamed onto it, which
is the right fix for a player who has not logged in since the id changed.

Without --apply it only reports what it would do.  --archive moves the drained
sub-world out of the tree so the dropdown stops listing it, and --name sets the
label the survivor shows in that dropdown.  --waypoints-only merges the
waypoints but leaves the target's map data untouched, i.e. keeps one map whole
instead of combining both.
"""

import shutil
import sys
import zipfile
from pathlib import Path

CACHE_DIRS = {"cache", "cache_1"}


def region_weight(zip_path: Path) -> int:
    """Uncompressed size of the region payload — our proxy for how much of the
    region has actually been rendered."""
    try:
        with zipfile.ZipFile(zip_path) as z:
            return sum(i.file_size for i in z.infolist())
    except (zipfile.BadZipFile, OSError):
        return -1


def region_files(mw_dir: Path) -> dict[str, Path]:
    """Every region zip under a sub-world, keyed by path relative to it.
    Covers the surface regions and every caves/<layer>/ directory."""
    out = {}
    for p in mw_dir.rglob("*.zip"):
        rel = p.relative_to(mw_dir)
        if rel.parts[0] in CACHE_DIRS:
            continue
        out[str(rel)] = p
    return out


def merge_map(server_dir: Path, target_mw: str, source_mw: str, apply: bool) -> None:
    for dim_dir in sorted(d for d in server_dir.iterdir() if d.is_dir()):
        tgt, src = dim_dir / target_mw, dim_dir / source_mw
        if not src.is_dir():
            continue
        if not tgt.is_dir():
            print(f"\n[{dim_dir.name}] target {target_mw} absent — renaming {source_mw}")
            if apply:
                src.rename(tgt)
            continue

        t_files, s_files = region_files(tgt), region_files(src)
        added = replaced = kept = 0
        print(f"\n[{dim_dir.name}] {len(t_files)} regions in target, {len(s_files)} in source")

        for rel in sorted(s_files):
            s_w = region_weight(s_files[rel])
            if rel not in t_files:
                print(f"  + {rel:<24} {s_w:>10,}  (only in source)")
                added += 1
                if apply:
                    dest = tgt / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(s_files[rel], dest)
                continue
            t_w = region_weight(t_files[rel])
            if s_w > t_w:
                print(f"  ^ {rel:<24} {t_w:>10,} -> {s_w:>10,}  (source denser)")
                replaced += 1
                if apply:
                    shutil.copy2(s_files[rel], t_files[rel])
            else:
                kept += 1

        print(f"  = {kept} kept, {added} copied in, {replaced} replaced")

        # Zoom caches are derived data; drop them so Xaero rebuilds from the
        # merged regions instead of showing the pre-merge composite.
        for name in CACHE_DIRS:
            cache = tgt / name
            if cache.is_dir():
                print(f"  x dropping stale {name}/")
                if apply:
                    shutil.rmtree(cache)


def merge_waypoints(minimap_server: Path, target_mw: str, source_mw: str, apply: bool) -> None:
    if not minimap_server.is_dir():
        return
    for dim_dir in sorted(d for d in minimap_server.iterdir() if d.is_dir()):
        srcs = sorted(dim_dir.glob(f"{source_mw}_*.txt"))
        tgts = sorted(dim_dir.glob(f"{target_mw}_*.txt"))
        if not srcs:
            continue
        if not tgts:
            print(f"\n[waypoints {dim_dir.name}] no target file — renaming source")
            if apply:
                for s in srcs:
                    s.rename(dim_dir / s.name.replace(source_mw, target_mw, 1))
            continue

        tgt = tgts[0]
        lines = tgt.read_text().splitlines()
        # A waypoint is identified by name + coordinates; colour or icon may differ.
        have = {tuple(l.split(":")[1:6]) for l in lines if l.startswith("waypoint:")}
        new = []
        for s in srcs:
            for l in s.read_text().splitlines():
                if not l.startswith("waypoint:"):
                    continue
                key = tuple(l.split(":")[1:6])
                if key not in have:
                    have.add(key)
                    new.append(l)

        print(f"\n[waypoints {dim_dir.name}] {tgt.name}: {len(have) - len(new)} existing, {len(new)} added")
        for l in new:
            f = l.split(":")
            print(f"  + {f[1]}  ({f[3]}, {f[4]}, {f[5]})")
        if apply and new:
            tgt.write_text("\n".join(lines + new) + "\n")


def set_label(dim_dir: Path, mw: str, label: str, apply: bool) -> None:
    """Rewrite the MWName line so the dropdown shows `label` for this sub-world,
    and drop entries naming sub-worlds that no longer exist on disk — Xaero
    would otherwise still offer them in the dropdown."""
    cfg = dim_dir / "dimension_config.txt"
    if not cfg.is_file() or not (dim_dir / mw).is_dir():
        return
    lines = []
    for l in cfg.read_text().splitlines():
        if not l.startswith("MWName:"):
            lines.append(l)
            continue
        named = l.split(":", 2)[1]
        if named == mw:
            continue
        if (dim_dir / named).is_dir():
            lines.append(l)
        else:
            print(f"  - [{dim_dir.name}] dropping stale entry for {named}")
    lines.insert(0, f"MWName:{mw}:{label}")
    print(f"  ~ [{dim_dir.name}] {mw} labelled '{label}'")
    if apply:
        cfg.write_text("\n".join(lines) + "\n")


def archive_source(server_dir: Path, minimap_server: Path, source_mw: str,
                   dest: Path, apply: bool) -> None:
    """Move the drained sub-world out of the tree, and drop its MWName entry so
    Xaero stops listing it in the World/Sub-World dropdown."""
    for base, kind in ((server_dir, "world-map"), (minimap_server, "minimap")):
        if not base.is_dir():
            continue
        for dim_dir in sorted(d for d in base.iterdir() if d.is_dir()):
            moves = [dim_dir / source_mw] if (dim_dir / source_mw).is_dir() else []
            moves += sorted(dim_dir.glob(f"{source_mw}_*.txt"))
            for src in moves:
                rel = src.relative_to(base.parent.parent)
                print(f"  > archiving {kind}/{dim_dir.name}/{src.name}")
                if apply:
                    out = dest / rel
                    out.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(src), str(out))

            cfg = dim_dir / "dimension_config.txt"
            if cfg.is_file():
                lines = cfg.read_text().splitlines()
                kept = [l for l in lines if not l.startswith(f"MWName:{source_mw}:")]
                if len(kept) != len(lines) and apply:
                    cfg.write_text("\n".join(kept) + "\n")


def main() -> int:
    args, apply, archive, label, wp_only = [], False, None, None, False
    it = iter(sys.argv[1:])
    for a in it:
        if a == "--apply":
            apply = True
        elif a == "--waypoints-only":
            wp_only = True
        elif a == "--archive":
            archive = Path(next(it))
        elif a == "--name":
            label = next(it)
        else:
            args.append(a)
    if len(args) != 4:
        print(__doc__)
        return 2

    instance, server, target_mw, source_mw = args
    mc = Path(instance)
    if not (mc / "xaero").is_dir():
        mc = mc / "minecraft"
    print(f"{'APPLYING' if apply else 'DRY RUN'}: {source_mw} -> {target_mw}  in {mc}")

    if not apply:
        print("(dry run — nothing will be written; re-run with --apply)")

    names = [server]
    if server == "all":
        names = sorted(d.name for d in (mc / "xaero/world-map").iterdir() if d.is_dir())
        print(f"servers found: {names}")
    for name in names:
        print(f"\n########## server {name}")
        run_one(mc, name, target_mw, source_mw, apply, archive, label, wp_only)
    return 0


def run_one(mc: Path, server: str, target_mw: str, source_mw: str,
            apply: bool, archive, label, wp_only: bool) -> None:
    world_map = mc / "xaero/world-map" / server
    minimap = mc / "xaero/minimap" / server
    if wp_only:
        print("\nMap data: keeping the target's map whole, no regions combined.")
    else:
        merge_map(world_map, target_mw, source_mw, apply)
    merge_waypoints(minimap, target_mw, source_mw, apply)

    if archive:
        print("\nArchiving the drained sub-world:")
        archive_source(world_map, minimap, source_mw, archive, apply)
    if label:
        for dim_dir in sorted(d for d in world_map.iterdir() if d.is_dir()):
            set_label(dim_dir, target_mw, label, apply)


if __name__ == "__main__":
    sys.exit(main())

# M1 scorer (AINF-408): compare BenchDump.java output for <id>.stripped with the FUNC and
# IFUNC symbols of <id> (ground truth, readelf). Usage: score.py CORPUS RESULTS READELF
# found:    Ghidra has a function starting at a ground-truth function address.
# named:    ...and its name matches any symbol there (libc aliases one body under several
#           names), compared by a canonical key.
# wrong:    a non-default name that matches none of them.
# conflict: Ghidra's own "FID_conflict:" (several identical bodies) — reported apart.
# thunk:    a thunk named after its target (cmp_rec -> strcmp tail call) — reported apart.
# Fixes from the independent audit (2026-10-14): IFUNC in the truth (glibc resolvers),
# "(anonymous namespace)" before splitting at "(", Rust "::<T>" generics, drop_glue ==
# drop_in_place, closure spellings, an empty key never matches.
import json
import os
import re
import subprocess
import sys

corpus, results, readelf = sys.argv[1:4]
# Structural labels Ghidra puts on split .cold blocks (switchD_x::caseD_y) are not names.
DEFAULT = re.compile(r"^(thunk_)?(FUN|LAB|SUB)_[0-9a-fA-F]+$|^_(INIT|FINI)_\d+$|^(switchD|caseD)_")
RUST_HASH = re.compile(r"::h[0-9a-f]{16}$|\.abi0$")  # Rust hash, Go ABI0 wrapper suffix
ALIAS = {"_DT_INIT": "init", "_DT_FINI": "fini", "entry": "start"}
WIDE = {"string", "ostream", "istream", "iostream", "ostringstream", "istringstream", "stringstream",
        "ofstream", "ifstream", "fstream", "streambuf", "stringbuf", "filebuf", "ios"}
CLOSURE = re.compile(r"\{\{closure\}\}|\{closure#\d+\}")


def strip_templates(s: str) -> str:
    out, depth = [], 0
    for ch in s:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def key(n: str) -> str:
    """Canonical comparison key: last scope component without template arguments,
    return type, spaces or leading underscores; basic_X == X and wX == X (Ghidra names
    ctors by the std typedef: `string` for basic_string, measured)."""
    n = n.replace("(anonymous namespace)", "anon").replace("thunk to ", "")
    n = CLOSURE.sub("{closure}", n).replace("drop_glue", "drop_in_place")
    n = strip_templates(n.split("(")[0]).replace(" ", "").rstrip(":")
    n = n.split("::")[-1].split("&")[-1].split("*")[-1]
    dtor = n.startswith("~")
    n = n.lstrip("~").lstrip("_")
    n = n[6:] if n.startswith("basic_") else n
    if n[:1] == "w" and n[1:] in WIDE:
        n = n[1:]
    return ("~" if dtor else "") + n


def norm(n: str) -> str:
    n = n.removeprefix("FID_conflict:")
    n = n.split("::")[-1] if n.startswith("<EXTERNAL>::") else n
    n = ALIAS.get(n, n).replace("(anonymous namespace)", "anon")
    n = RUST_HASH.sub("", n).split("(")[0].strip()
    return n.lstrip("_")


def truth(path: str) -> dict:
    out = subprocess.run([readelf, "-sW", "--demangle", path], capture_output=True, text=True).stdout
    gt = {}
    for line in out.splitlines():
        p = line.split(None, 7)
        if len(p) == 8 and p[3] in ("FUNC", "IFUNC") and p[6] != "UND" and int(p[1], 16):
            gt.setdefault(int(p[1], 16), set()).add(norm(p[7].split("@")[0]))
    return gt


rows = []
for fn in sorted(os.listdir(results)):
    if not fn.endswith(".json") or fn == "score.json":
        continue
    bid = fn[:-5]
    d = json.load(open(os.path.join(results, fn)))
    gt = truth(os.path.join(corpus, bid))
    best = None
    for delta in {0, d["image_base"]}:
        by_off = {f["off"] - delta: f for f in d["functions"]}
        found = [a for a in gt if a in by_off]
        if best is None or len(found) > len(best[1]):
            best = (by_off, found)
    by_off, found = best
    named = wrong = conflict = thunk = 0
    for a in found:
        f = by_off[a]
        g = f["name"]
        if DEFAULT.match(g.split("::")[-1]) or DEFAULT.match(g):
            continue
        gn, names = norm(g), gt[a]
        k = key(gn)
        if gn in names or (k and k in {key(t) for t in names}):
            named += 1
        elif f["thunk"]:
            thunk += 1
        elif g.startswith("FID_conflict:"):
            conflict += 1
        else:
            wrong += 1
    n = max(len(gt), 1)
    rows.append({
        "id": bid,
        "gt_functions": len(gt),
        "ghidra_functions": d["total"],
        "found_pct": round(100 * len(found) / n, 1),
        "named_pct": round(100 * named / n, 1),
        "wrong_pct": round(100 * wrong / n, 1),
        "conflict_pct": round(100 * conflict / n, 1),
        "thunk_named": thunk,
        "decompile_fail": d["decompile_fail"],
        "decompile_s": round(d["decompile_ms"] / 1000, 1),
        "c_lines": sum(f.get("lines", 0) for f in d["functions"]),
        "gotos": sum(f.get("gotos", 0) for f in d["functions"]),
        "warnings": sum(f.get("warns", 0) for f in d["functions"]),
    })
json.dump(rows, sys.stdout, indent=1)

# M1 scorer (AINF-408): compare BenchDump.java output for <id>.stripped with the FUNC
# symbols of <id> (ground truth, readelf). Usage: score.py CORPUS RESULTS READELF > score.json
# found:  Ghidra has a function starting at a ground-truth function address.
# named:  ...and its name matches (demangled, no Rust hash, no leading "_", Ghidra's
#         structural names _DT_INIT/_DT_FINI/entry = _init/_fini/_start).
# wrong:  ...a non-default name that does NOT match (e.g. a tail call to strcmp taken
#         for a thunk and named strcmp — measured on c-gcc-O2's cmp_rec).
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


def norm(n: str) -> str:
    n = n.split("::")[-1] if n.startswith("<EXTERNAL>::") else n
    n = ALIAS.get(n, n)
    n = RUST_HASH.sub("", n).split("(")[0].strip()
    return n.lstrip("_")


def truth(path: str) -> dict:
    out = subprocess.run([readelf, "-sW", "--demangle", path], capture_output=True, text=True).stdout
    gt = {}
    for line in out.splitlines():
        p = line.split(None, 7)
        if len(p) == 8 and p[3] == "FUNC" and p[6] != "UND" and int(p[1], 16):
            gt.setdefault(int(p[1], 16), norm(p[7].split("@")[0]))
    return gt


rows = []
for fn in sorted(os.listdir(results)):
    if not fn.endswith(".json") or fn == "score.json":
        continue
    bid = fn[:-5]
    d = json.load(open(os.path.join(results, fn)))
    gt = truth(os.path.join(corpus, bid))
    funcs = d["functions"]
    best = None
    for delta in {0, d["image_base"]}:
        by_off = {f["off"] - delta: f for f in funcs}
        found = [a for a in gt if a in by_off]
        if best is None or len(found) > len(best[1]):
            best = (by_off, found)
    by_off, found = best
    named = wrong = 0
    for a in found:
        g = by_off[a]["name"]
        if DEFAULT.match(g.split("::")[-1]) or DEFAULT.match(g):
            continue
        gn, tn = norm(g), gt[a]
        if gn == tn or gn.split("::")[-1] == tn.split("::")[-1]:
            named += 1
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
        "decompile_fail": d["decompile_fail"],
        "decompile_s": round(d["decompile_ms"] / 1000, 1),
    })
json.dump(rows, sys.stdout, indent=1)

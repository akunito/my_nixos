# Print the M1 score table. Usage: table.py score.json bench-times.txt
import json
import sys

rows = json.load(open(sys.argv[1]))
t = dict(l.split() for l in open(sys.argv[2]) if l.strip())
print(f"{'binary':26} {'gt':>5} {'ghidra':>6} {'found%':>7} {'named%':>7} {'wrong%':>7} {'confl%':>7} {'thunk':>5} {'fail':>5} {'lines':>7} {'gotos':>5} {'warn':>5} {'total_s':>8}")
for r in rows:
    print(f"{r['id']:26} {r['gt_functions']:>5} {r['ghidra_functions']:>6} {r['found_pct']:>7} {r['named_pct']:>7} {r['wrong_pct']:>7} {r.get('conflict_pct', 0):>7} {r.get('thunk_named', 0):>5} {r['decompile_fail']:>5} {r.get('c_lines', 0):>7} {r.get('gotos', 0):>5} {r.get('warnings', 0):>5} {t.get(r['id'], '?'):>8}")

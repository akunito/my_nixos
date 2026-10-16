#!/usr/bin/env python3
"""Throughput bench for the NAS reasoner presets (plan docs/akunito/plans/nas-reasoner-throughput.md).

Runs from DESK against the gate; the PRESET must already be loaded (`ai preset set`), every
request names it. Results go to $OUT (default /tmp/ai-bench) as JSON lines.

  bench.py depth PRESET [--depths 0,32000,100000] [--reps 3] [--n 1024]
      Filler (repo .nix files, deterministic) up to each depth, then a per-rep nonce AFTER the
      filler: rep 1 pays the prefill (measured), reps 2..n reuse the cached prefix and measure
      decode at that depth. Records prompt_n, cache_n, pp/tg tok/s, draft stats, GPU state.
  bench.py alternate PRESET [--a 55000] [--b 120000] [--turns 6] [--n 800]
      Two conversations A and B take turns on the single slot, each turn adds ~1k tokens of
      new user text — the pattern that evicted the prompt cache on 2026-10-15. Metric: wall
      time per turn and cache_n/prompt_n on every switch.
  bench.py greedy PRESET [--n 400]
      Fixed prompts at temperature 0 / top_k 1; tokens saved for `compare A.jsonl B.jsonl`.
      Speculative decoding must give the same text (numeric batch noise allowed late).
  bench.py compare FILE_A FILE_B
"""
import json, os, sys, time, glob, hashlib, argparse, urllib.request

URL = os.environ.get("NAS_URL", "http://100.64.0.1:8090")
ST = os.environ.get("NAS_STATUS", "http://100.64.0.1:8093/status")
OUT = os.environ.get("OUT", "/tmp/ai-bench")
REPO = os.path.dirname(os.path.abspath(__file__)) + "/../../../.."
CHARS_PER_TOKEN = 3.1   # measured on this filler with Qwen3.8's tokenizer is ~3.1; prompt_n is recorded anyway

_filler = None
def filler(tokens):
    global _filler
    if _filler is None:
        parts = []
        for f in sorted(glob.glob(REPO + "/system/**/*.nix", recursive=True)):
            with open(f, errors="replace") as fh:
                parts.append(f"=== {os.path.relpath(f, REPO)} ===\n{fh.read()}\n")
        _filler = "".join(parts)
    need = int(tokens * CHARS_PER_TOKEN)
    s = _filler
    while len(s) < need:
        s += _filler
    return s[:need]

def gpu():
    try:
        g = json.load(urllib.request.urlopen(ST, timeout=5)).get("gpu", {})
        return {k: g.get(k) for k in ("temp_c", "power_w", "util_pct", "vram_used_mb")}
    except Exception as e:
        return {"err": str(e)}

def chat(preset, messages, n, **extra):
    body = {"model": preset, "messages": messages, "max_tokens": n, "stream": False, "seed": 42}
    body.update(extra)
    req = urllib.request.Request(URL + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"})
    t0 = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=3600))
    wall = time.time() - t0
    t = r.get("timings", {})
    m = r["choices"][0]["message"]
    return {
        "wall_s": round(wall, 2),
        "prompt_n": t.get("prompt_n"), "cache_n": t.get("cache_n"),
        "pp_tps": round(t.get("prompt_per_second") or 0, 1),
        "tg_n": t.get("predicted_n"), "tg_tps": round(t.get("predicted_per_second") or 0, 2),
        "draft_n": t.get("draft_n"), "draft_acc": t.get("draft_n_accepted"),
        "finish": r["choices"][0].get("finish_reason"),
        "completion_tokens": r.get("usage", {}).get("completion_tokens"),
        "reasoning_chars": len(m.get("reasoning_content") or ""),
        "content": m.get("content") or "", "reasoning": m.get("reasoning_content") or "",
    }

def emit(path, rec):
    os.makedirs(OUT, exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(rec) + "\n")
    short = {k: v for k, v in rec.items() if k not in ("content", "reasoning")}
    print(json.dumps(short), flush=True)

QUESTION = ("Read the configuration above. Explain in detail how the services it defines depend on each "
            "other, which ones would break first if the GPU were removed, and propose three concrete "
            "improvements with the reasoning behind each.")

def eos_bug(res, depth):
    # llama.cpp #27756: instant EOS on some Qwen3.8 prompts past ~96k tokens.
    return depth >= 96000 and (res.get("completion_tokens") or 0) < 5 and res.get("finish") == "stop"

def cmd_depth(a):
    path = f"{OUT}/depth-{a.preset}-{int(time.time())}.jsonl"
    for d in [int(x) for x in a.depths.split(",")]:
        base = filler(d) if d else ""
        for rep in range(a.reps):
            nonce = hashlib.sha1(f"{d}-{rep}-{time.time()}".encode()).hexdigest()[:12]
            user = (base + "\n\n" if base else "") + f"[run {nonce}]\n" + QUESTION
            g0 = gpu()
            res = chat(a.preset, [{"role": "user", "content": user}], a.n)
            for retry in range(2):
                if not eos_bug(res, d): break
                res["eos_bug"] = True; emit(path, {"mode": "depth", "preset": a.preset, "depth": d, "rep": rep, **res})
                nonce += "x"; user = base + "\n\n" + f"[run {nonce}]\n" + QUESTION
                res = chat(a.preset, [{"role": "user", "content": user}], a.n)
            emit(path, {"mode": "depth", "preset": a.preset, "depth": d, "rep": rep,
                        "gpu_before": g0, "gpu_after": gpu(), **res})
    print("->", path)

def cmd_alternate(a):
    path = f"{OUT}/alternate-{a.preset}-{int(time.time())}.jsonl"
    convs = {"A": [{"role": "user", "content": filler(a.a) + "\n\n" + QUESTION}],
             "B": [{"role": "user", "content": filler(a.b)[::-1][:int(a.b * CHARS_PER_TOKEN)] + "\n\n" + QUESTION}]}
    if a.c:   # a third prefix, like Claude Code's auto-mode classifier calls (2026-10-16 transcripts)
        convs["C"] = [{"role": "user", "content": filler(a.c * 2)[-int(a.c * CHARS_PER_TOKEN):] + "\n\n" + QUESTION}]
    total = 0.0
    for turn in range(a.turns):
        for name in convs:
            if turn > 0:
                convs[name].append({"role": "user", "content": filler(1000 + 37 * turn)[-int(1000 * CHARS_PER_TOKEN):]
                                    + f"\n\nTurn {turn}: continue the analysis with the new material above."})
            res = chat(a.preset, convs[name], a.n)
            total += res["wall_s"]
            convs[name].append({"role": "assistant", "content": res["content"] or "(no text)"})
            emit(path, {"mode": "alternate", "preset": a.preset, "conv": name, "turn": turn, "gpu": gpu(), **res})
    print(f"total wall {total:.1f} s ->", path)

GREEDY_PROMPTS = [
    "Write a Python function that merges overlapping intervals, with tests.",
    "A bat and a ball cost 1.10 in total. The bat costs 1.00 more than the ball. How much is the ball? Explain.",
    "Explain the difference between a mutex and a semaphore with a C example.",
    "Write a bash script that finds the 10 largest files under a directory, skipping .git.",
    "Prove that the square root of 2 is irrational.",
    "Given a NixOS module, how would you add a systemd timer that runs a script daily? Show the Nix code.",
    "List the planets in order of mass and explain how their masses were measured.",
    "Write a SQL query for the second highest salary per department, and explain edge cases.",
    "What happens, step by step, when you type a URL in a browser and press Enter?",
    "Implement an LRU cache in Rust with O(1) operations.",
    "Translate to Spanish and Polish: 'The deploy failed because the lock file was stale.'",
    "If a train leaves at 14:05 at 80 km/h and another at 14:35 at 100 km/h on the same track, when does the second catch up?",
    "Refactor this into idiomatic Go: for i:=0;i<len(a);i++{ if a[i]%2==0 { b = append(b, a[i]*2) } }",
    "Explain how ZFS ARC differs from the Linux page cache.",
    "Write a JSON schema for a todo item with optional due date and tags.",
    "Summarise the CAP theorem and give one real system for each trade-off.",
    "Write a regex that matches IPv4 addresses and explain its limits.",
    "Explain speculative decoding in LLM inference in five sentences.",
    "Design a rate limiter for an HTTP API; compare token bucket and sliding window.",
    "What are the failure modes of a RAID-Z1 pool with 4 disks?",
]

def cmd_greedy(a):
    path = f"{OUT}/greedy-{a.preset}-{int(time.time())}.jsonl"
    for i, p in enumerate(GREEDY_PROMPTS):
        res = chat(a.preset, [{"role": "user", "content": p}], a.n, temperature=0, top_k=1)
        emit(path, {"mode": "greedy", "preset": a.preset, "i": i, **res})
    print("->", path)

def cmd_compare(a):
    def load(f):
        return {r["i"]: r["reasoning"] + "\n---\n" + r["content"] for r in map(json.loads, open(f))}
    A, B = load(a.file_a), load(a.file_b)
    same = 0
    for i in sorted(A):
        x, y = A[i], B.get(i, "")
        k = next((j for j in range(min(len(x), len(y))) if x[j] != y[j]), min(len(x), len(y)))
        ok = x == y
        same += ok
        print(f"{i:2d} {'IDENTICAL' if ok else f'diverges at char {k} of {len(x)}/{len(y)}'}")
    print(f"{same}/{len(A)} identical")

ap = argparse.ArgumentParser()
sp = ap.add_subparsers(dest="cmd", required=True)
p = sp.add_parser("depth"); p.add_argument("preset"); p.add_argument("--depths", default="0,32000,100000"); p.add_argument("--reps", type=int, default=3); p.add_argument("--n", type=int, default=1024)
p = sp.add_parser("alternate"); p.add_argument("preset"); p.add_argument("--a", type=int, default=55000); p.add_argument("--b", type=int, default=120000); p.add_argument("--c", type=int, default=0); p.add_argument("--turns", type=int, default=6); p.add_argument("--n", type=int, default=800)
p = sp.add_parser("greedy"); p.add_argument("preset"); p.add_argument("--n", type=int, default=400)
p = sp.add_parser("compare"); p.add_argument("file_a"); p.add_argument("file_b")
a = ap.parse_args()
{"depth": cmd_depth, "alternate": cmd_alternate, "greedy": cmd_greedy, "compare": cmd_compare}[a.cmd](a)

# M4: send every Ghidra C file of the dump to LLM4Decompile (paper prompt, greedy) and save
# the model's C next to it. Usage: llm.py DUMP_DIR OUT_DIR [ollama_url] [model]
# Only text goes in and out; the output is compiled and run solely inside m4.nix's eval.
import json
import os
import sys
import time
import urllib.request

dump, out = sys.argv[1], sys.argv[2]
url = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8090"
model = sys.argv[4] if len(sys.argv) > 4 else "llm4decompile-9b"
for b in sorted(os.listdir(dump)):
    os.makedirs(os.path.join(out, b), exist_ok=True)
    for fn in sorted(os.listdir(os.path.join(dump, b))):
        pseudo = open(os.path.join(dump, b, fn)).read()
        prompt = "# This is the assembly code:\n" + pseudo.strip() + "\n# What is the source code?\n"
        body = {"model": model, "prompt": prompt, "raw": True, "stream": False,
                "options": {"temperature": 0, "num_predict": 1024}}
        t = time.time()
        req = urllib.request.Request(url + "/api/generate", json.dumps(body).encode(), {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=300) as r:
            text = json.load(r).get("response", "")
        open(os.path.join(out, b, fn), "w").write(text)
        print(f"{b}/{fn} {time.time() - t:.1f}s {len(text)} chars", flush=True)

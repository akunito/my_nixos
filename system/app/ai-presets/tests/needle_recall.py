"""Long-context recall check: a filler text repeated to ~N tokens with three planted
sentences (~8 %, ~50 %, ~92 %), sent to a NAS preset; prints which sentences come back.

python3 needle_recall.py MODEL FILLER.txt COPIES  (e.g. reasoner-9b-512k llama-server-README.md 12)
2026-10-14: reasoner-9b-512k, README x12 = 411,734 tokens -> 3/3 exact, prefill 292 s."""
import json, sys, time, urllib.request
model, filler, copies = sys.argv[1], open(sys.argv[2]).read(), int(sys.argv[3])
facts = {max(1, copies // 12): "IMPORTANT FACT A: the north gate code word is AMBER-7421.",
         copies // 2: "IMPORTANT FACT B: the river boat is named Saint Ulric.",
         copies - 1 - max(1, copies // 12): "IMPORTANT FACT C: the vault opens on the 19th of March."}
doc = "".join(filler + ("\n\n" + facts[i] + "\n\n" if i in facts else "") for i in range(copies))
q = "Above is a long document. Somewhere inside it there are exactly three sentences that start with 'IMPORTANT FACT'. Quote all three sentences exactly, one per line, and nothing else."
body = {"model": model, "messages": [{"role": "user", "content": doc + "\n\n" + q}], "max_tokens": 200,
        "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
req = urllib.request.Request("http://100.64.0.1:8090/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
t = time.time()
r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
ans = r["choices"][0]["message"]["content"]
print(json.dumps({"found": sum(f in ans for f in facts.values()), "of": 3, "prompt_tokens": r["usage"]["prompt_tokens"],
                  "prefill_s": round(r["timings"]["prompt_ms"] / 1000), "prefill_tps": round(r["timings"]["prompt_per_second"]),
                  "wall_s": round(time.time() - t), "answer": ans}))

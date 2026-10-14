#!/usr/bin/env bash
# Runs ON THE NAS as root (sudo bash -s). Router-mode eviction test on port 8095, then cleanup.
set -uo pipefail
IMG="ghcr.io/ggml-org/llama.cpp@sha256:c4348afb91499b10fad12f92626c7a8ca8b69d6475d10c793b810cb61237ce00"
echo "image: $IMG"
M=/var/lib/llama-server/models; INI=/var/lib/llama-server/router-test.ini
cat > $INI <<INI
version = 1
[*]
ngl = 999
fa = on
[laya]
model = $M/Laya-BF16.gguf
c = 512
ub = 4096
b = 4096
[kev-9b]
model = $M/Kev-9B-Q8_0.gguf
c = 16384
ub = 4096
b = 4096
[reasoner]
model = $M/Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf
c = 32768
ctk = q8_0
ctv = q8_0
jinja = true
INI
docker rm -f llama-router-test >/dev/null 2>&1
docker run --rm -d --name llama-router-test --device nvidia.com/gpu=all -v /var/lib/llama-server:/var/lib/llama-server \
  -p 127.0.0.1:8095:8095 "$IMG" --host 0.0.0.0 --port 8095 --models-preset $INI --models-max 1 >/dev/null
for i in $(seq 1 60); do curl -sf http://127.0.0.1:8095/models >/dev/null && break; sleep 1; done
V() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits; }
L() { curl -s http://127.0.0.1:8095/models | tr -d '\n ' | grep -o '"id":"[^"]*"\|"value":"[^"]*"' | tr '\n' ' '; }
echo "start: models=$(L) vram=$(V)"
SO='{"state":"Ticket: the app crashes when I open invoices, demo in two hours!","questions":{"topic":{"type":"choice","instructions":"Topic?","criteria":{"bug":null,"billing":null}}}}'
for m in laya kev-9b; do
  body=$(printf '%s' "$SO" | sed "s/^{/{\"model\":\"$m\",/")
  t=$(date +%s.%N); r=$(curl -s -w ' HTTP%{http_code}' --max-time 180 http://127.0.0.1:8095/v1/systemone -H 'content-type: application/json' -d "$body")
  echo "request $m: $(printf '%.1f' $(echo "$(date +%s.%N)-$t"|bc))s ${r: -8} answer=$(echo "${r% HTTP*}" | grep -o '"choice":"[^"]*"\|"message":"[^"]*"' | head -1) models=$(L) vram=$(V)"
done
t=$(date +%s.%N); r=$(curl -s -w ' HTTP%{http_code}' --max-time 300 http://127.0.0.1:8095/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"reasoner","messages":[{"role":"user","content":"Say OK."}],"max_tokens":20,"chat_template_kwargs":{"enable_thinking":false}}')
echo "request reasoner: $(printf '%.1f' $(echo "$(date +%s.%N)-$t"|bc))s ${r: -8} text=$(echo "${r% HTTP*}" | grep -o '"content":"[^"]*"' | head -1) models=$(L) vram=$(V)"
r=$(curl -s -X POST http://127.0.0.1:8095/models/unload -H 'content-type: application/json' -d '{"model":"reasoner"}'); sleep 3
echo "unload reasoner: $r models=$(L) vram=$(V)"
r=$(curl -s -X POST http://127.0.0.1:8095/models/load -H 'content-type: application/json' -d '{"model":"laya"}'); sleep 5
echo "load laya: $r models=$(L) vram=$(V)"
docker rm -f llama-router-test >/dev/null 2>&1; rm -f $INI
echo "cleanup done vram=$(V)"

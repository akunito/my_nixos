#!/usr/bin/env bash
# measure_presets.sh PRESET... : switch through the DESK path, wait for loaded, measure.
set -uo pipefail
NAS=akunito@100.64.0.1; ST=http://100.64.0.1:8093/status
for p in "$@"; do
  t0=$(date +%s.%N)
  out=$(ssh -A -o BatchMode=yes $NAS "sudo -n /run/current-system/sw/bin/ai preset set $p" 2>&1) || { echo "$p: SET FAILED: $out"; continue; }
  state=""; for i in $(seq 1 240); do state=$(curl -s --max-time 2 $ST | jq -r .state); [ "$state" = loaded ] && break; sleep 0.5; done
  t1=$(date +%s.%N)
  s=$(curl -s --max-time 3 $ST)
  r=$(curl -s --max-time 120 http://100.64.0.1:8090/v1/chat/completions -H 'Content-Type: application/json' \
      -d '{"model":"'$p'","messages":[{"role":"user","content":"Write a Python function that reverses a string. Code only."}],"max_tokens":200,"chat_template_kwargs":{"enable_thinking":false}}')
  echo "$p: set='$out' load=$(printf '%.1f' $(echo "$t1-$t0"|bc))s state=$state $(echo "$s" | jq -c '{ctx,slots,kv,vram_mb:.gpu.vram_used_mb}') gen=$(echo "$r" | jq -c '{tps:(.timings.predicted_per_second|floor), pp:(.timings.prompt_per_second|floor), n:.usage.completion_tokens, err:.error.message}')"
done

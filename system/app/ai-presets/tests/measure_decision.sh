#!/usr/bin/env bash
# measure_decision.sh PRESET... : switch (DESK path), wait loaded, VRAM, systemone text (+image), save raw responses.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); OUT=${OUT:-/tmp/ai-preset-results}; mkdir -p $OUT
NAS=akunito@100.64.0.1; ST=http://100.64.0.1:8093/status; API=http://100.64.0.1:8090/v1/systemone
for p in "$@"; do
  t0=$(date +%s.%N)
  out=$(ssh -A -o BatchMode=yes $NAS "sudo -n /run/current-system/sw/bin/ai preset set $p" 2>&1) || { echo "$p: SET FAILED: $out"; continue; }
  state=""; for i in $(seq 1 240); do state=$(curl -s --max-time 2 $ST | jq -r .state); [ "$state" = loaded ] && break; sleep 0.5; done
  load=$(printf '%.1f' $(echo "$(date +%s.%N)-$t0"|bc))
  vram=$(curl -s --max-time 3 $ST | jq -r .gpu.vram_used_mb)
  if [ "$state" != loaded ]; then
    echo "$p: NOT LOADED after ${load}s (state=$state)"
    ssh $NAS "journalctl -u llama-server --since '-3min' --no-pager | grep -i -E 'error|oom|out of memory|failed|alloc' | tail -5" > $OUT/$p.journal 2>&1
    continue
  fi
  for kind in text image; do
    [ "$kind" = image ] && case $p in decider|clef) ;; *) continue;; esac
    r=$(curl -s -o $OUT/$p.$kind.json -w '%{http_code} %{time_total}' --max-time 120 $API -H 'content-type: application/json' -d @$HERE/payloads/$kind.json)
    echo "$p: load=${load}s vram=${vram}MiB $kind http/time=$r $(jq -c '{a: (.answers // .error), in: .usage.input_tokens}' $OUT/$p.$kind.json 2>/dev/null | cut -c1-400)"
  done
done

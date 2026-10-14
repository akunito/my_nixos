#!/usr/bin/env bash
# GGUF downloads for the NAS 3090 presets (system/app/ai-presets.nix) — run on NAS_PROD as root:
#   sudo systemd-run --unit=hf-download -p IOSchedulingClass=idle -p Nice=10 /run/current-system/sw/bin/bash ~/.dotfiles/system/app/llama-server/hf-download.sh
#   sudo journalctl -u hf-download -f
# 2026-10-14 later: + Qwen3.5-9B abliterated Q8_0 (9.5 GB) + its vision mmproj — the 512k-context fast reasoner (KV 32 KB/token f16, 8 full-attention layers).
# Each file goes to .part, is sha256-checked (LFS hash from the HF API, 2026-10-14) and renamed; a present+valid file is skipped.
# Models dir is the root NVMe, never a pool. Claude's auto mode refuses to run external downloads itself, hence this script.
set -u
# systemd-run gives the unit a bare PATH: `env: 'bash': No such file` on 2026-10-14. Launch with an explicit bash and fix PATH here.
export PATH=/run/current-system/sw/bin:/run/wrappers/bin:$PATH
cd /var/lib/llama-server/models || exit 1
while read -r sha url; do
  [ -n "$sha" ] || continue
  f=${url##*/}
  if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ]; then echo "OK (present) $f"; continue; fi
  echo "GET $f"
  curl -L -sS --retry 5 --retry-delay 10 -C - -o "$f.part" "$url" || { echo "FAIL download $f"; continue; }
  got=$(sha256sum "$f.part" | cut -d' ' -f1)
  if [ "$got" = "$sha" ]; then mv "$f.part" "$f"; chmod 644 "$f"; echo "OK $f"; else echo "FAIL sha256 $f got $got"; rm -f "$f.part"; fi
done <<'LIST'
9e23efec609fa777dc216d9b51f3e74bb473f6aa4163c2be8bd87f0ef5e7808a https://huggingface.co/turintech/pplx-decider-27B-Artemis-GGUF/resolve/main/pplx-decider-27B-Artemis-15.3GB.gguf
633ea0419e6cdfca52ca0d243cbbee393eb0b03afc84f720ad5ff7c2c0e03f6c https://huggingface.co/turintech/pplx-decider-27B-Artemis-GGUF/resolve/main/mmproj-pplx-decider-27B-Q8_0.gguf
9997675e4c9e9016273372b5fdedbdda7ad14285bc722949e4b9daca62bf3822 https://huggingface.co/ggml-org/Clef-GGUF/resolve/main/Clef-Q4_K_M.gguf
744ad2db24c336fc9120dd5ba06344c0601b9efd365fe96be01ce5c4e6ab64cf https://huggingface.co/ggml-org/Clef-GGUF/resolve/main/mmproj-Clef-Q8_0.gguf
edeea94939cd1575c1f984c28982170c0e47caab66e4b80993fed992519573b4 https://huggingface.co/ggml-org/Laya-GGUF/resolve/main/Laya-BF16.gguf
d30b225bfdc985d1856bb04a990be76008d0cf40dccbf78938e3069744bc614c https://huggingface.co/ggml-org/Kev-9B-GGUF/resolve/main/Kev-9B-Q8_0.gguf
9df7ce00f4df74344dd788ade97c412ef9850e58b44ff337e56fbf07be24a97f https://huggingface.co/mradermacher/Huihui-Qwen3.5-9B-abliterated-GGUF/resolve/main/Huihui-Qwen3.5-9B-abliterated.Q8_0.gguf
cf54897b6bbfa89c809fdc2b8236e0977bed70760b39ee8f11d87296e1d0e046 https://huggingface.co/mradermacher/Huihui-Qwen3.5-9B-abliterated-GGUF/resolve/main/Huihui-Qwen3.5-9B-abliterated.mmproj-Q8_0.gguf
LIST
echo "ALL DONE"

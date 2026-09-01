---
id: user-modules.ollama
summary: Ollama local LLM server configuration, RDNA4 Vulkan backend workaround, and model recommendations for RX 9070 XT.
tags: [ollama, ai, vulkan, rocm, rdna4, gpu, llm, user-modules]
related_files:
  - user/packages/user-ai-pkgs.nix
  - system/hardware/opengl.nix
  - docs/user-modules/ollama.md
key_files:
  - user/packages/user-ai-pkgs.nix
activation_hints:
  - If configuring Ollama, local LLM inference, or GPU backend selection for AI workloads
---

# Ollama Module

Configuration and usage guide for the Ollama local LLM server, including GPU backend selection and model recommendations.

## Table of Contents

- [Overview](#overview)
- [RDNA4 Vulkan Backend](#rdna4-vulkan-backend)
- [Installation](#installation)
- [Model Recommendations](#model-recommendations)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Overview

Ollama provides a local LLM inference server with an easy-to-use CLI. It is installed via the `user-ai-pkgs.nix` module when `userAiPkgsEnable = true`.

**Module Location**: `user/packages/user-ai-pkgs.nix`

**Package**: `pkgs-unstable.ollama` (Vulkan backend)

## RDNA4 Vulkan Backend

### Why Vulkan Instead of ROCm

As of ROCm 7.1.1, there is a **known deadlock** on RDNA4 GPUs (gfx1201, e.g. RX 9070 XT) during HSA agent initialization. Loading any model with `ollama-rocm` causes a hard system hang requiring a power cycle.

The fix is to use the standard `ollama` package, which uses the **Vulkan backend** (via Mesa RADV). On the RX 9070 XT, Vulkan inference is actually faster than ROCm would be, so there is no performance penalty.

### What Changed

In `user/packages/user-ai-pkgs.nix`, the package was changed from `ollama-rocm` to `ollama`.

### What Was NOT Changed (and Why)

- **`rocmSupport = true` in `flake-base.nix`** — Kept. This is a nixpkgs-wide build flag that enables ROCm for packages that support it (Blender, OpenCV, etc.). It does not force ROCm runtime usage and is not related to the Ollama hang.
- **`rocmPackages.clr.icd` in `opengl.nix`** — Kept. Provides OpenCL compute support for non-LLM workloads. Does not conflict with Vulkan.
- **No new environment variables needed** — The Vulkan stack (Mesa RADV for gfx1201) is already correctly configured. The gaming module's `NODEVICE_SELECT=1` also benefits Vulkan-based AI inference.

### When to Switch Back to ROCm

When ROCm 7.2+ lands in nixpkgs with proper gfx1201 support, change `pkgs-unstable.ollama` back to `pkgs-unstable.ollama-rocm` in `user-ai-pkgs.nix`. ROCm may offer better performance for large models due to HIP kernel optimizations. Monitor the [ROCm release notes](https://rocm.docs.amd.com/) and [nixpkgs ROCm tracking issues](https://github.com/NixOS/nixpkgs/issues?q=rocm+rdna4).

## Installation

The module is enabled via the `userAiPkgsEnable` flag in your profile config:

```nix
userSettings = {
  userAiPkgsEnable = true;
};
```

This installs both LM Studio and Ollama. See [LM Studio docs](lmstudio.md) for LM Studio configuration.

## Model Recommendations

### Hardware Budget (DESK - RX 9070 XT)

- **GPU VRAM**: 16 GB
- **System RAM**: 30 GB (CPU offload available but slow)
- **CPU**: Ryzen 7800X3D

### RX 9070 XT Vulkan Benchmarks (llama.cpp)

| Model | Size | Quant | Gen t/s | Prompt t/s | Fits VRAM? |
|-------|------|-------|---------|------------|------------|
| granite-3b | 3B | Q8_0 | 258 | 9,751 | Yes (full) |
| Mistral-7B | 7B | Q8_0 | 72 | 2,993 | Yes (full) |
| Llama-3.1-8B | 8B | Q8_0 | 69 | 2,982 | Yes (full) |
| DeepSeek-R1-8B | 8B | Q8_0 | 69 | 2,984 | Yes (full) |
| GPT-OSS-20B | 20B | Q8_0 | 152 | 3,388 | Yes (MoE, 3.6B active) |
| Qwen3-14B | 14B | Q4_K_M | ~45 | ~1,500 | Yes (full) |
| Qwen3-32B | 32B | Q4_K_M | ~15 | ~800 | No (needs ~20GB) |

### Qwen3.8-27B (agent model, added 2026-09-01)

The whole Qwen3.8 family is oversized for this card. Sizes taken from the Ollama
registry and the unsloth GGUF repo, against a 16304 MiB card:

| Build | Size | Fits? |
|-------|------|-------|
| `qwen3.8:27b` (official Ollama tag, q4_K_M + vision projector) | 17.74 GB | No — bigger than the card |
| `qwen3.8-flash-next` (125B-A6B) | ~70 GB at q4 | No |
| `qwen3.8-max` (2.4T) | — | No |
| `UD-IQ4_XS` (unsloth GGUF) | 14.25 GB | Only on a bare desktop |
| **`UD-IQ3_S`** | **12.04 GB** | **Yes — the one configured** |
| `UD-IQ3_XXS` | 10.93 GB | Yes, with more headroom (the fallback) |

Measured VRAM baseline on DESK 2026-09-01: Sway + Zen + VSCode + terminals hold
~2.9 GiB, and one Minecraft client adds another 3.9 GiB. So ~13.4 GiB is free in
a normal session and ~9.5 GiB with the game running — which is why this model is
explicitly *not* expected to be usable while gaming.

Two properties make IQ3_S workable where a normal 27B would not be: unsloth's
dynamic quants keep the sensitive layers at higher precision, and Qwen3.8 runs
linear attention (Gated DeltaNet) on 48 of its 64 layers, so its KV cache is much
smaller than a dense 27B's at the same context.

**Thinking is on by default and is turned off deliberately.** Ollama's
`/v1/chat/completions` accepts the OpenAI-standard `reasoning_effort`, and
`"none"` disables it; LiteLLM sets that per model on VPS_PROD. Leaving it on
reproduces the GLM-4.6V-Flash failure already documented in `DESK-config.nix` —
the budget is spent reasoning and the caller gets `finish_reason=length` with
empty content. Qwen's official non-thinking sampling profile (temperature 0.7,
top_p 0.80, top_k 20, min_p 0) is baked into the Modelfile, because Ollama's
OpenAI endpoint does not accept `top_k` at all.

Requires **ollama >= 0.32.12** for the hybrid Gated-DeltaNet runtime;
`nixpkgs-stable` ships 0.21.1, so `ollamaServerUseUnstable = true`.

#### Backend: Vulkan, not ROCm (switched 2026-09-01)

`nixpkgs-unstable` ships `ollama-vulkan` alongside `ollama-rocm` — same 0.32.14,
only the ggml backend differs (`ls $out/lib/ollama` shows `vulkan` vs
`rocm_v7_2`). Benchmarked on this card, 250 tokens, two runs each:

| Model | ROCm | Vulkan | Δ |
|-------|------|--------|---|
| `qwen3.8-agent` (dense 27B, IQ3_S) | 27.4 tok/s | 30.9 tok/s | +13% |
| `gpt-oss:20b` (MoE A3.6B, MXFP4) | 92.4 tok/s | 106.2 tok/s | +15% |

RADV compiles native GFX1201 shaders; ROCm reaches RDNA4 through a generic path.

**The bigger win is not speed.** ROCm reports free VRAM as though nothing else
were on the card — it answered `free="15.8 GiB"` while sysfs showed 10299 MiB —
and that is what let Ollama overcommit and fault the GPU. Vulkan reported
`13994 MiB free` against sysfs's `13994 MiB`: exact. Device pinning changes with
the backend: `GGML_VK_VISIBLE_DEVICES` instead of `HIP_VISIBLE_DEVICES` /
`ROCR_VISIBLE_DEVICES`, or the 7800X3D's iGPU is enumerated as a second device.

Switch with `ollamaServerBackend = "rocm" | "vulkan"`.

#### Things that do NOT help here

- **`OLLAMA_FLASH_ATTENTION=1`** — already on. The runner logs
  `flash_attn = auto` then `Flash Attention enabled` without any setting.
- **`OLLAMA_KV_CACHE_TYPE=q8_0`** — saves VRAM, not time, and there is little to
  save: Qwen3.8's KV cache is only 1024 MiB at 16k context because 48 of its 64
  layers are linear.
- **MTP speculative decoding** — the biggest theoretical win (+33-125% published)
  and *not reachable from Ollama*. The head ships inside our GGUF and the runner
  throws it away:
  `model has unused tensor blk.64.nextn.eh_proj.weight (43 MB) -- ignoring`
  followed by `no implementations specified for speculative decoding`. Ollama's
  Modelfile `DRAFT` command currently implements MTP for Gemma 4 only. Reaching
  it means `llama-server` with `--spec-type draft-mtp --spec-draft-n-max 2`,
  which does not serve `/api/chat` and so cannot host the villager model.

#### Measured on DESK, 2026-09-01

| | |
|---|---|
| VRAM with the model loaded | **14517 MiB** of 16304 (1787 MiB left) |
| Ollama's own projection | 11928 MiB — **~1.5 GiB short**, the vision/CLIP buffers fall outside its breakdown |
| Weights on GPU | 10616 MiB, all 66/66 layers |
| KV cache @ 16k ctx | **1024 MiB** — small because only 16 of 64 layers use full attention |
| Warm decode | **~29 tok/s** (300 tokens in 10.25 s) |
| Cold start | ~55 s |

**It cannot share the card with a game.** Proven the hard way: with a Minecraft
client holding 3.9 GiB, ROCm still reported `free="15.8 GiB"` (it does not see
other processes' allocations) while sysfs showed 10299 MiB. Ollama loaded
anyway, and amdgpu answered with

```
amdgpu 0000:03:00.0: [drm] *ERROR* Not enough memory for command submission!
```

killing the runner *and* the game's GPU context. `ollamaServerGpuOverheadBytes`
(2 GiB) now covers Ollama's own under-estimate, but nothing can correct what
ROCm reports — **use `llama-lock` before gaming**, exactly as before.

It coexists with `gpt-oss:20b` on disk but never in VRAM —
`OLLAMA_MAX_LOADED_MODELS = 1` makes Ollama evict one to load the other.
Configuration lives in `system/app/ollama-server.nix` (server) and
`profiles/DESK-config.nix` (`ollamaServerCustomModels`); build/fetch everything
with `ollama-pull`.

### Recommended Models

**Best overall: GPT-OSS-20B** — 152 t/s, MoE architecture (only 3.6B active params per token), fits in 16GB at Q8_0. Comparable to GPT-4o-mini on common benchmarks.

**Best for coding: Qwen3-14B or Qwen2.5-Coder-14B** — ~45 t/s at Q4_K_M, HumanEval ~85%, fits comfortably in 16GB.

**Best for reasoning: DeepSeek-R1-Distill-Llama-8B** — 69 t/s at Q8_0, strong chain-of-thought reasoning, full VRAM fit.

### Local vs Cloud Model Suitability

**Good locally**: Code autocompletion, single-file bug fixes, unit test generation, documentation, scripts, explaining code, Q&A, math/logic.

**Use cloud models for**: Large-scale multi-file refactoring, complex NixOS module design, architectural decisions, security auditing, 100K+ token context tasks.

## Usage

```bash
# Start the server
ollama serve &

# Pull a model
ollama pull gpt-oss:20b

# Run interactively
ollama run gpt-oss:20b "Write a Python function to find the longest palindromic substring"

# API endpoint (OpenAI-compatible)
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-oss:20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Troubleshooting

### Verify Vulkan Backend

After starting `ollama serve`, check logs for Vulkan device detection:

```bash
ollama serve 2>&1 | grep -i vulkan
# Should show "Vulkan0" or similar device name
```

### System Hangs When Loading Models

If the system freezes when loading a model, `ollama-rocm` may have been installed instead of `ollama`. Verify:

```bash
ollama --version
# Check user-ai-pkgs.nix uses pkgs-unstable.ollama (NOT ollama-rocm)
```

After fixing, rebuild with `./sync-user.sh`.

### Slow Inference

1. Verify model fits in VRAM (check table above)
2. Check GPU is detected: `vulkaninfo | grep deviceName`
3. Ensure no other GPU-heavy apps are running
4. For models exceeding 16GB VRAM, use lower quantization (Q4_K_M instead of Q8_0)

### Model Not Found

```bash
# List available models
ollama list

# Search for models
ollama search <name>

# Pull specific quantization
ollama pull model:tag
```

## Related Documentation

- [LM Studio Module](lmstudio.md) — GUI-based local LLM inference
- [GPU Monitoring](../hardware/gpu-monitoring.md) — GPU stats and monitoring tools
- [Gaming Module](gaming.md) — Vulkan/RDNA4 driver configuration (shared Vulkan stack)

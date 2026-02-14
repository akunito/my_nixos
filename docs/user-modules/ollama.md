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

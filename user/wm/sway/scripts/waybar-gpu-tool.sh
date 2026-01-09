#!/usr/bin/env bash
set -euo pipefail

# Launch the best GPU control/monitor tool depending on configured GPU type.
# Falls back to btop++ if the preferred tool isn't available.
#
# Usage:
#   waybar-gpu-tool.sh <gpuType> <kitty> <btop> [lact] [nvidia_settings] [intel_gpu_top]
#
# gpuType comes from systemSettings.gpuType (e.g. amd|intel|nvidia|other)

GPU_TYPE="${1:-}"
KITTY_BIN="${2:-}"
BTOP_BIN="${3:-}"
LACT_BIN="${4:-}"
NVIDIA_SETTINGS_BIN="${5:-}"
INTEL_GPU_TOP_BIN="${6:-}"

open_btop() {
  if [[ -n "$KITTY_BIN" ]] && [[ -x "$KITTY_BIN" ]] && [[ -n "$BTOP_BIN" ]] && [[ -x "$BTOP_BIN" ]]; then
    exec "$KITTY_BIN" --title 'btop++ (System Monitor)' -e "$BTOP_BIN"
  fi
  # Last resort: try plain btop in PATH
  exec btop
}

case "$GPU_TYPE" in
  amd)
    # LACT provides GUI/daemon control for AMDGPU.
    if [[ -n "$LACT_BIN" ]] && [[ -x "$LACT_BIN" ]]; then
      exec "$LACT_BIN"
    fi
    ;;
  nvidia)
    if [[ -n "$NVIDIA_SETTINGS_BIN" ]] && [[ -x "$NVIDIA_SETTINGS_BIN" ]]; then
      exec "$NVIDIA_SETTINGS_BIN"
    fi
    ;;
  intel)
    # intel_gpu_top is a TUI; run it inside kitty if available.
    if [[ -n "$INTEL_GPU_TOP_BIN" ]] && [[ -x "$INTEL_GPU_TOP_BIN" ]] && [[ -n "$KITTY_BIN" ]] && [[ -x "$KITTY_BIN" ]]; then
      exec "$KITTY_BIN" --title 'intel_gpu_top' -e "$INTEL_GPU_TOP_BIN"
    fi
    ;;
esac

open_btop



#!/usr/bin/env bash
set -euo pipefail

# Flatpak reconcile helper
# - Intended to be sourced by install.sh (so it can reuse sudo/password handling)
# - Can also be executed directly (will use plain sudo)
#
# Baseline file format (per profile): profiles/<PROFILE>-flatpaks.json
#   { "user": ["app.id"], "system": ["app.id"] }
#
# Safety goals:
# - If baseline missing/invalid/empty => no-op
# - If we cannot reliably read installed flatpaks (timeout/error) => no-op
# - Never overwrite baseline unless user explicitly chooses Snapshot

_flatpak_reconcile_log() {
  # shellcheck disable=SC2059
  printf "%s\n" "$*"
}

_flatpak_reconcile_have_cmd() { command -v "$1" >/dev/null 2>&1; }

_flatpak_reconcile_sudo_cmd() {
  # Prefer the caller-provided SUDO_CMD (install.sh uses this indirection).
  if [ "${SUDO_CMD:-}" != "" ]; then
    printf "%s" "$SUDO_CMD"
    return
  fi
  # If sourced from install.sh, sudo_exec may exist even if SUDO_CMD wasn't exported.
  if declare -F sudo_exec >/dev/null 2>&1; then
    printf "%s" "sudo_exec"
    return
  fi
  printf "%s" "sudo"
}

_flatpak_reconcile_timeout() {
  # Usage: _flatpak_reconcile_timeout SECONDS cmd...
  if _flatpak_reconcile_have_cmd timeout; then
    timeout "$@"
  else
    # Fallback: no timeout available
    shift
    "$@"
  fi
}

_flatpak_reconcile_json_escape() {
  # Minimal JSON string escape (handles backslash + double quote)
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf "%s" "$s"
}

_flatpak_reconcile_write_baseline_json() {
  # Args: file user_list(system newline-separated) system_list(newline-separated)
  local file="$1"
  local user_list="$2"
  local system_list="$3"

  {
    printf "{\n"
    printf "  \"user\": [\n"
    local first=true
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$first" = true ]; then first=false; else printf ",\n"; fi
      printf "    \"%s\"" "$(_flatpak_reconcile_json_escape "$line")"
    done <<<"$user_list"
    printf "\n  ],\n"
    printf "  \"system\": [\n"
    first=true
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$first" = true ]; then first=false; else printf ",\n"; fi
      printf "    \"%s\"" "$(_flatpak_reconcile_json_escape "$line")"
    done <<<"$system_list"
    printf "\n  ]\n"
    printf "}\n"
  } >"$file"
}

_flatpak_reconcile_read_baseline_scope() {
  # Args: repo_dir profile scope(user|system)
  # Output: newline-separated appIds (sorted/unique done by caller)
  local repo_dir="$1"
  local profile="$2"
  local scope="$3"
  local baseline_file="$repo_dir/profiles/${profile}-flatpaks.json"

  [ -r "$baseline_file" ] || return 1
  _flatpak_reconcile_have_cmd nix || return 2

  # Parse JSON using nix (no python/jq dependency).
  # Note: This is CLI-time impurity only; it does not affect flake purity.
  nix eval \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    --impure \
    --json \
    --expr "let d = builtins.fromJSON (builtins.readFile \"${baseline_file}\"); in (d.${scope} or [])" \
    2>/dev/null \
  | tr -d '\r' \
  | nix eval \
      --extra-experimental-features nix-command \
      --extra-experimental-features flakes \
      --impure \
      --raw \
      --expr 'builtins.concatStringsSep "\n" (builtins.fromJSON (builtins.readFile /dev/stdin))' \
      2>/dev/null \
  | sed '/^[[:space:]]*$/d' || return 3
}

_flatpak_reconcile_read_installed_scope() {
  # Args: scope(user|system)
  # Output: newline-separated appIds
  # Return codes:
  #   0: ok (output may be empty meaning "no apps installed")
  #   10: flatpak not available
  #   11: timeout/error => unreliable (caller should treat as no-op)
  local scope="$1"

  _flatpak_reconcile_have_cmd flatpak || return 10

  local out=""
  local rc=0

  if [ "$scope" = "user" ]; then
    out="$(_flatpak_reconcile_timeout 2 flatpak list --user --app --columns=application 2>/dev/null || true)"
    rc=$?
  else
    # Try without sudo first; most systems allow listing system installs unprivileged.
    out="$(_flatpak_reconcile_timeout 2 flatpak list --system --app --columns=application 2>/dev/null || true)"
    rc=$?
    if [ $rc -ne 0 ] || [ -z "${out//[[:space:]]/}" ]; then
      # If list failed, try with sudo only if we can do non-interactive sudo.
      local sudo_cmd="$(_flatpak_reconcile_sudo_cmd)"
      if $sudo_cmd -n true >/dev/null 2>&1; then
        out="$(_flatpak_reconcile_timeout 2 $sudo_cmd flatpak list --system --app --columns=application 2>/dev/null || true)"
        rc=$?
      fi
    fi
  fi

  # timeout(1) returns 124 on timeout
  if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    return 11
  fi
  # If the command truly failed (non-zero) AND produced nothing, treat as unreliable.
  if [ $rc -ne 0 ] && [ -z "${out//[[:space:]]/}" ]; then
    return 11
  fi

  printf "%s\n" "$out" | tr -d '\r' | sed '/^[[:space:]]*$/d'
  return 0
}

flatpak_reconcile() {
  # Expected vars (from install.sh): SCRIPT_DIR PROFILE SILENT_MODE
  local repo_dir="${SCRIPT_DIR:-}"
  local profile="${PROFILE:-}"
  local silent="${SILENT_MODE:-false}"
  local baseline_file=""

  if [ -z "$repo_dir" ] || [ -z "$profile" ]; then
    _flatpak_reconcile_log "flatpak-reconcile: missing SCRIPT_DIR/PROFILE; skipping."
    return 0
  fi

  # Opt-in: only run if the baseline file exists for this profile (even if empty).
  baseline_file="$repo_dir/profiles/${profile}-flatpaks.json"
  [ -r "$baseline_file" ] || return 0

  local baseline_user baseline_system
  baseline_user="$(_flatpak_reconcile_read_baseline_scope "$repo_dir" "$profile" user 2>/dev/null || true)"
  baseline_system="$(_flatpak_reconcile_read_baseline_scope "$repo_dir" "$profile" system 2>/dev/null || true)"

  baseline_user="$(printf "%s\n" "$baseline_user" | sed '/^[[:space:]]*$/d' | sort -u || true)"
  baseline_system="$(printf "%s\n" "$baseline_system" | sed '/^[[:space:]]*$/d' | sort -u || true)"

  local installed_user installed_system
  local rc_user=0 rc_system=0

  installed_user="$(_flatpak_reconcile_read_installed_scope user || rc_user=$?; true)"
  installed_system="$(_flatpak_reconcile_read_installed_scope system || rc_system=$?; true)"

  installed_user="$(printf "%s\n" "$installed_user" | sed '/^[[:space:]]*$/d' | sort -u || true)"
  installed_system="$(printf "%s\n" "$installed_system" | sed '/^[[:space:]]*$/d' | sort -u || true)"

  local user_unreliable=false
  local system_unreliable=false
  [ $rc_user -ne 0 ] && user_unreliable=true
  [ $rc_system -ne 0 ] && system_unreliable=true

  # If we couldn't reliably read either scope, do nothing (no false results).
  if [ "$user_unreliable" = true ] && [ "$system_unreliable" = true ]; then
    return 0
  fi

  local missing_user extra_user missing_system extra_system
  if [ "$user_unreliable" = true ]; then
    missing_user=""
    extra_user=""
  else
    missing_user="$(comm -23 <(printf "%s\n" "$baseline_user" | sed '/^[[:space:]]*$/d') <(printf "%s\n" "$installed_user" | sed '/^[[:space:]]*$/d') || true)"
    extra_user="$(comm -13 <(printf "%s\n" "$baseline_user" | sed '/^[[:space:]]*$/d') <(printf "%s\n" "$installed_user" | sed '/^[[:space:]]*$/d') || true)"
  fi
  if [ "$system_unreliable" = true ]; then
    missing_system=""
    extra_system=""
  else
    missing_system="$(comm -23 <(printf "%s\n" "$baseline_system" | sed '/^[[:space:]]*$/d') <(printf "%s\n" "$installed_system" | sed '/^[[:space:]]*$/d') || true)"
    extra_system="$(comm -13 <(printf "%s\n" "$baseline_system" | sed '/^[[:space:]]*$/d') <(printf "%s\n" "$installed_system" | sed '/^[[:space:]]*$/d') || true)"
  fi

  if [ -z "${missing_user}${extra_user}${missing_system}${extra_system}" ]; then
    return 0
  fi

  if [ "$silent" = true ]; then
    _flatpak_reconcile_log ""
    _flatpak_reconcile_log "Flatpak drift detected (silent mode):"
    [ "$user_unreliable" = true ] && _flatpak_reconcile_log "  - user scope: unavailable (skipping)"
    [ "$system_unreliable" = true ] && _flatpak_reconcile_log "  - system scope: unavailable (skipping)"
    [ -n "$missing_user" ] && _flatpak_reconcile_log "  - Missing (user): $(printf "%s" "$missing_user" | wc -l)"
    [ -n "$extra_user" ] && _flatpak_reconcile_log "  - Extra   (user): $(printf "%s" "$extra_user" | wc -l)"
    [ -n "$missing_system" ] && _flatpak_reconcile_log "  - Missing (system): $(printf "%s" "$missing_system" | wc -l)"
    [ -n "$extra_system" ] && _flatpak_reconcile_log "  - Extra   (system): $(printf "%s" "$extra_system" | wc -l)"
    return 0
  fi

  _flatpak_reconcile_log ""
  _flatpak_reconcile_log "Flatpak drift detected for profile ${profile}:"
  if [ -n "$missing_user" ]; then
    _flatpak_reconcile_log "Missing Flatpaks (baseline -> install) [user]:"
    printf "%s\n" "$missing_user" | sed 's/^/  - /'
  fi
  if [ -n "$extra_user" ]; then
    _flatpak_reconcile_log "Extra Flatpaks (installed -> not in baseline) [user]:"
    printf "%s\n" "$extra_user" | sed 's/^/  - /'
  fi
  if [ -n "$missing_system" ]; then
    _flatpak_reconcile_log "Missing Flatpaks (baseline -> install) [system]:"
    printf "%s\n" "$missing_system" | sed 's/^/  - /'
  fi
  if [ -n "$extra_system" ]; then
    _flatpak_reconcile_log "Extra Flatpaks (installed -> not in baseline) [system]:"
    printf "%s\n" "$extra_system" | sed 's/^/  - /'
  fi

  _flatpak_reconcile_log ""
  _flatpak_reconcile_log "Choose an action:"
  _flatpak_reconcile_log "  [1] Install missing"
  _flatpak_reconcile_log "  [2] Uninstall extra"
  _flatpak_reconcile_log "  [3] Snapshot baseline to match currently installed"
  _flatpak_reconcile_log "  [Enter] Do nothing"
  read -r choice || true

  local sudo_cmd
  sudo_cmd="$(_flatpak_reconcile_sudo_cmd)"

  case "${choice:-}" in
    1)
      if [ -n "$missing_user" ]; then
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
        printf "%s\n" "$missing_user" | xargs -r flatpak install --user -y flathub
      fi
      if [ -n "$missing_system" ]; then
        if $sudo_cmd -n true >/dev/null 2>&1; then
          $sudo_cmd flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
          printf "%s\n" "$missing_system" | xargs -r $sudo_cmd flatpak install --system -y flathub
        else
          _flatpak_reconcile_log "Skipping system Flatpak installs (sudo not available non-interactively)."
        fi
      fi
      ;;
    2)
      if [ -n "$extra_user" ]; then
        printf "%s\n" "$extra_user" | xargs -r flatpak uninstall --user -y
      fi
      if [ -n "$extra_system" ]; then
        if $sudo_cmd -n true >/dev/null 2>&1; then
          printf "%s\n" "$extra_system" | xargs -r $sudo_cmd flatpak uninstall --system -y
        else
          _flatpak_reconcile_log "Skipping system Flatpak uninstalls (sudo not available non-interactively)."
        fi
      fi
      ;;
    3)
      # Snapshot baseline file (explicit opt-in). Guard against overwriting with unknown/empty data.
      # If both installed lists are empty, require explicit confirmation to write empty.
      local snapshot_user="$installed_user"
      local snapshot_system="$installed_system"

      # If a scope is unavailable, keep its current baseline (do not clobber with unknown/empty).
      if [ "$user_unreliable" = true ]; then
        snapshot_user="$baseline_user"
      fi
      if [ "$system_unreliable" = true ]; then
        snapshot_system="$baseline_system"
      fi

      if [ -z "${snapshot_user}${snapshot_system}" ]; then
        _flatpak_reconcile_log "Installed Flatpak list is empty; refusing to overwrite baseline by default."
        printf "Force write empty baseline anyway? (y/N) "
        read -r yn || true
        case "${yn:-}" in
          [Yy]*)
            ;;
          *)
            return 0
            ;;
        esac
      fi

      _flatpak_reconcile_write_baseline_json "$baseline_file" "$snapshot_user" "$snapshot_system" || {
        _flatpak_reconcile_log "Failed to write baseline file: $baseline_file"
        return 0
      }
      _flatpak_reconcile_log "Baseline updated: $baseline_file"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # Allow running directly:
  #   SCRIPT_DIR=/path/to/repo PROFILE=DESK SILENT_MODE=false ./scripts/flatpak-reconcile.sh
  flatpak_reconcile
fi



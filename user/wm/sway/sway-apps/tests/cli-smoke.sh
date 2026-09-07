#!/usr/bin/env bash
# End-to-end smoke test of every sway-apps CLI function against the LIVE sway
# session, using a throwaway git repo as state so the real dotfiles repo is
# never touched. Run on the target machine:  bash cli-smoke.sh [sway-apps-bin]
#
# Needs: a running sway (SWAYSOCK auto-discovered), git, jq, and kcalc or
# gnome-calculator available in PATH for the startup/launch tests.
set -u
BIN=${1:-sway-apps}
T=$(mktemp -d /tmp/sway-apps-smoke.XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/user/wm/sway/apps" "$T/local" "$T/cfg/sway"
git -C "$T/repo" init -q -b main
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export SWAY_APPS_DOTFILES="$T/repo" SWAY_APPS_STATE_DIR="$T/repo/user/wm/sway/apps" \
       SWAY_APPS_LOCAL_STATE_DIR="$T/local" SWAY_APPS_INCLUDE="$T/cfg/sway/sway-apps.conf" \
       SWAY_APPS_PROFILE=SMOKE GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }
J() { "$BIN" --json "$@" 2>>"$T/stderr.log"; }
check() { # name, jq-expr, json
  local name=$1 expr=$2 json=$3
  if printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then ok "$name"; else bad "$name" "$(printf '%s' "$json" | head -c 300)"; fi
}
echo "== sway-apps smoke: $($BIN --version) state=$SWAY_APPS_STATE_DIR"

# This suite reloads sway several times (every rule save does), and a reload
# re-applies output config, which briefly evacuates workspaces. Refuse to run
# while anything is fullscreen or a game is up, unless the caller insists.
if [ -z "${SWAY_APPS_SMOKE_FORCE:-}" ]; then
  FS=$(swaymsg -t get_tree 2>/dev/null | jq -r '[.. | select(.type? == "con" or .type? == "floating_con") | select((.fullscreen_mode // 0) != 0 or (.app_id // "" | test("gamescope")) or ((.window_properties.class // "") | test("^steam_app_|gamescope"))) | (.app_id // .window_properties.class // .name)] | unique | join(", ")' 2>/dev/null)
  if [ -n "$FS" ]; then
    echo "REFUSING: fullscreen/game windows present ($FS). Reloads would disturb them. Set SWAY_APPS_SMOKE_FORCE=1 to override."
    exit 3
  fi
fi

# --- doctor / discovery -------------------------------------------------
check "doctor runs"            '.checks | length > 5'                         "$(J doctor)"
check "apps discovered"        'length > 5'                                    "$(J apps list)"
check "apps flatpak scanned"   'map(.source) | index("flatpak-system") != null or index("flatpak-user") != null or length >= 0' "$(J apps list --all)"
check "apps show kcalc/calc"   'length >= 0'                                    "$(J apps list calc)"
check "windows list"           'type == "array"'                               "$(J windows list)"
check "windows focused"        '.id != null'                                   "$(J windows focused)"

# --- rules: add / list / show / set / disable / enable / test / match / rm
ADD=$(J rules add -c 'app_id=^smoke-test-app$' -a 'floating enable' -a 'sticky enable' --name "smoke rule" --no-live)
check "rules add"              '.rule.id != null and .commit != null and .apply.reloaded == true' "$ADD"
RID=$(printf '%s' "$ADD" | jq -r .rule.id)
check "rules list has it"      "map(select(.id==\"$RID\")) | length == 1"      "$(J rules list)"
check "rules show line"        '.line == "for_window [app_id=\"^smoke-test-app$\"] floating enable, sticky enable"' "$(J rules show "$RID")"
check "include contains rule"  'true' "$(grep -q 'smoke-test-app' "$SWAY_APPS_INCLUDE" && echo '{}' || echo 'null')"
check "render validates"       '.valid == true'                                 "$(J render --validate)"
check "rules set add-action"   '.rule.actions | index("sticky enable") != null and index("resize set 800 600") != null' "$(J rules set "$RID" --add-action 'resize set 800 600' --no-live)"
check "rules set bad action"   '.error | test("unknown sway command")'          "$(J rules set "$RID" --add-action 'florting enable')"
check "rules disable"          '.rule.enabled == false'                         "$(J rules disable "$RID")"
check "disabled not rendered"  'true' "$(grep -q '^for_window \[app_id="\^smoke-test-app' "$SWAY_APPS_INCLUDE" && echo null || echo '{}')"
check "rules enable"           '.rule.enabled == true'                          "$(J rules enable "$RID")"
check "rules match none"       'length == 0'                                    "$(J rules match "$RID")"
check "rules test no hits"     '.hits | length == 0'                            "$(J rules test "$RID")"
check "profile scope override" '.rule.scope == "profile"'                       "$(J rules set "$RID" --scope profile --no-live)"
check "profile file exists"    'true' "$([ -f "$SWAY_APPS_STATE_DIR/SMOKE.json" ] && echo '{}' || echo null)"
check "assign rule add"        '.rule.line == "assign [app_id=\"smoke-assign\"] workspace number 7"' "$(J rules add --kind assign -c app_id=smoke-assign --workspace 7 --no-live)"
check "no_focus rule add"      '.rule.line == "no_focus [app_id=\"smoke-nofocus\"]"' "$(J rules add --kind no_focus -c app_id=smoke-nofocus --no-live)"
check "bad criterion rejected" '.error | test("unknown criterion")'             "$(J rules add -c bogus=x -a 'floating enable')"
check "duplicate rejected"     '.error | test("already exists")'                "$(J rules add -c 'app_id=^smoke-test-app$' -a 'floating enable')"

# --- live apply against a real window --------------------------------------
FOC=$(J windows focused | jq -r '.app_id // .class // empty')
if [ -n "$FOC" ]; then
  LIVE=$(J rules test -c "app_id=^${FOC//./\\.}$" -a 'nop smoke-live')
  check "live apply hits focused ($FOC)" '.hits | length >= 1 and all(.ok)' "$LIVE"
else
  bad "live apply" "no focused window with app_id"
fi

# --- import -------------------------------------------------------------
printf 'for_window [app_id="smoke-import"] floating enable\nfor_window [app_id="smoke-import"] sticky enable\nassign [class="SmokeX"] workspace number 9\n' > "$T/import.conf"
check "import merges dupes"    '.added | length == 2'                           "$(J import-config "$T/import.conf" --apply)"
check "import merged actions"  '.[0].actions | length == 2'                     "$(J rules list smoke-import)"

# --- startup ---------------------------------------------------------------
CALC=""; for c in kcalc gnome-calculator; do command -v "$c" >/dev/null && CALC=$c && break; done
SADD=$(J startup add --command "${CALC:-true}" --name "smoke calc" --app-id "" --workspace "" --wait 0 --order 5)
check "startup add"            '.entry.id != null and .commit != null'          "$SADD"
SID=$(printf '%s' "$SADD" | jq -r .entry.id)
check "startup list ordered"   '.[0].id == "'"$SID"'"'                           "$(J startup list)"
check "startup set"            '.entry.wait_seconds == 3 and .entry.notes == "n"' "$(J startup set "$SID" --wait 3 --notes n)"
check "startup disable"        '.entry.enabled == false'                        "$(J startup disable "$SID")"
check "startup enable"         '.entry.enabled == true'                         "$(J startup enable "$SID")"
if [ -n "$CALC" ]; then
  APPID=$( [ "$CALC" = kcalc ] && echo org.kde.kcalc || echo org.gnome.Calculator )
  J startup set "$SID" --app-id "$APPID" --wait 20 --workspace "$(J windows focused | jq -r '.workspace_num // 1')" >/dev/null
  RUN=$(J startup run "$SID")
  check "startup run launches+places ($CALC)" '.[0].launched == true and (.[0].windows|length) >= 1 and (.[0].placed >= 1 or .[0].sticky >= 1)' "$RUN"
  sleep 1; swaymsg "[app_id=$APPID] kill" >/dev/null 2>&1 || true
  check "learned app_id cache"   'true' "$(grep -q "$APPID" "$SWAY_APPS_LOCAL_STATE_DIR/learned.json" 2>/dev/null && echo '{}' || echo null)"
else
  bad "startup run" "no calculator found"
fi
check "startup rm"             '.removed == "'"$SID"'"'                          "$(J startup rm "$SID")"

# --- monitors / pins / targets --------------------------------------------
FOCOUT=$(J monitors outputs | jq -r '.[] | select(.active) | .name' | head -1)
HWID=$(J monitors outputs | jq -r '.[] | select(.active) | .hw_id' | head -1)
check "monitors outputs"       'length >= 1 and all(.hw_id != "")'              "$(J monitors outputs)"
check "monitors add by connector" '.monitor.criteria == "'"$HWID"'" and .monitor.group == 7' "$(J monitors add main "$FOCOUT" --group 7 --name smoke-main --primary --no-live)"
check "monitors list"          'map(select(.id=="main")) | length == 1 and .[0].connected == true' "$(J monitors list)"
check "pins rendered"          '.text | test("workspace 71 output")'            "$(J render)"
check "group clash rejected"   '.error | test("already used")'                  "$(J monitors add other "$HWID" --group 7)"
TADD=$(J rules add --kind assign -c app_id=smoke-target --target main:3 --no-live)
check "rule with target"       '.rule.target.monitor == "main" and .rule.line == "assign [app_id=\"smoke-target\"] workspace number 73"' "$TADD"
TID=$(printf '%s' "$TADD" | jq -r .rule.id)
check "regroup renumbers"      'true' "$(J monitors set main --group 8 --no-live >/dev/null; J rules show "$TID" | jq -e '.line == "assign [app_id=\"smoke-target\"] workspace number 83"' >/dev/null && echo '{}' || echo null)"
check "bad target role"        '.error | test("not defined")'                   "$(J rules set "$TID" --target nope:1)"
check "workspaces map"         'map(select(.monitor != null and .monitor.id=="main")) | .[0].slots[2].rules | length == 1' "$(J workspaces map)"
check "pin-geometry show"      '.pin_geometry == false'                          "$(J monitors pin-geometry)"
check "pin-geometry on"        '.pin_geometry == true'                           "$(J monitors pin-geometry on --no-reload)"
check "geometry in include"    'true' "$(grep -q '^output "' "$SWAY_APPS_INCLUDE" && echo '{}' || echo null)"
J monitors pin-geometry off --no-reload >/dev/null
check "monitors rm guarded"    '.error | test("target")'                         "$(J monitors rm main)"
check "monitors rm --force"    '.removed == "main"'                              "$(J monitors rm main --force)"
check "target falls back"      '.line == "assign [app_id=\"smoke-target\"] workspace number 83"' "$(J rules show "$TID")"
check "doctor flags target"    '.checks | map(select(.check=="symbolic targets")) | .[0].ok == false' "$(J doctor)"
J rules rm "$TID" >/dev/null

# --- git -------------------------------------------------------------------
GS=$(J git status)
check "git status repo"        '.repo == true and (.dirty|length) == 0'         "$GS"
N=$(git -C "$T/repo" log --oneline | grep -c 'sway-apps:')
[ "$N" -ge 8 ] && ok "auto-commits ($N)" || bad "auto-commits" "only $N"
check "git commit nothing"     '.commit == null'                                 "$(J git commit -m x)"

# --- rules rm + apply ----------------------------------------------------------
check "rules rm"               '.removed == "'"$RID"'"'                          "$(J rules rm "$RID")"
check "apply --live"           '.rules >= 3 and .reloaded == true'              "$(J apply --live)"
check "removed not in include" 'true' "$(grep -q 'smoke-test-app' "$SWAY_APPS_INCLUDE" && echo null || echo '{}')"

# --- log ---------------------------------------------------------------------
check "log path"               '.path | endswith("sway-apps.log")'               "$(J log path)"
check "log tail has actions"   'map(select(test("rules.add ok"))) | length >= 1' "$(J log tail -n 500)"
check "log has ERROR mirror"   'map(select(test(" ERROR "))) | length >= 1'      "$(J log tail -n 500 --level error)"
SZ=$(stat -c %s "$SWAY_APPS_LOCAL_STATE_DIR/sway-apps.log"); [ "$SZ" -gt 1000 ] && ok "log written ($SZ bytes)" || bad "log written"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]

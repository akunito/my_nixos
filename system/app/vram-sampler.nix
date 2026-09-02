# Longitudinal VRAM sampler — what the desktop ACTUALLY peaks at, in use.
#
# WHY THIS EXISTS. Every VRAM figure in this repo's comments was a snapshot of a
# STATIONARY desktop: read sysfs once, write the number down. That measures the
# idle floor and says nothing about the number that decides whether a model
# fits, which is the PEAK under real use. Switching workspaces alone moves it
# several hundred MiB, because sway faults each workspace's client buffers back
# into VRAM as they become visible — so a figure taken while nothing moved is
# the most favourable reading available, not a representative one.
#
# It also cannot answer the other half: what the ceiling would be if an unusual
# app were opened. A snapshot of a session with eight windows tells you nothing
# about the session with a game launcher, a video call and three browsers.
#
# So: sample continuously, keep the peak, and record WHICH PROCESSES held the
# memory at that peak. Then a comparison between compositors (swayUseSwayfx) is
# a comparison of two distributions over the same real workload, not of two
# lucky moments.
#
# Deliberately a SYSTEM service, not a user one: it has to survive the
# logout/login that switching compositors requires, and reading every process's
# /proc/<pid>/fdinfo needs privileges the user session does not have.
#
# Cost is negligible — a few sysfs reads per tick. The fdinfo walk is the only
# real work and it runs ONLY when a new peak is set.
#
# Read it with `vram-report`.
{ config, pkgs, lib, systemSettings, ... }:
let
  cfg = systemSettings;
  enabled = (cfg.vramSamplerEnable or false) && (cfg.gpuType or "none") == "amd";
  interval = cfg.vramSamplerIntervalSec or 5;
  stateDir = "/var/lib/vram-sampler";
  # Keep roughly a week at 5 s before the log is rotated, so a multi-day A/B
  # between compositors is not silently truncated halfway through.
  maxLines = cfg.vramSamplerMaxLines or 120000;

  # Per-process attribution from fdinfo. amdgpu reports, per DRM client:
  #   drm-resident-vram   pages actually in VRAM
  #   drm-purgeable-vram  of those, the reclaimable Mesa BO cache
  # so resident-minus-purgeable is the part that is genuinely being held. Shared
  # buffers are counted once per importer, which means the compositor's line
  # includes every client surface it composites — that is a feature here: it is
  # exactly the number that shrinks when the compositor stops reserving its own
  # framebuffers.
  breakdown = pkgs.writeShellScript "vram-breakdown" ''
    ${pkgs.python3}/bin/python3 - "$1" <<'PY'
import os, re, sys, collections
pdev = sys.argv[1]
def kib(s):
    m = re.match(r'(\d+)\s*(\w+)?', s.strip())
    return int(m.group(1)) * {'KiB':1,'MiB':1024,'GiB':1048576}.get(m.group(2) or 'KiB', 0) if m else 0
rows = collections.Counter()
for pid in filter(str.isdigit, os.listdir('/proc')):
    seen = set()
    try: fds = os.listdir(f'/proc/{pid}/fdinfo')
    except Exception: continue
    for fd in fds:
        try: t = open(f'/proc/{pid}/fdinfo/{fd}').read()
        except Exception: continue
        if 'amdgpu' not in t: continue
        kv = dict(l.split(':', 1) for l in t.splitlines() if ':' in l)
        if kv.get('drm-pdev', "").strip() != pdev: continue
        cid = kv.get('drm-client-id', "").strip()
        if cid in seen: continue
        seen.add(cid)
        try: comm = open(f'/proc/{pid}/comm').read().strip()
        except Exception: comm = '?'
        rows[comm] += kib(kv.get('drm-resident-vram', '0')) - kib(kv.get('drm-purgeable-vram', '0'))
for comm, v in rows.most_common(12):
    if v > 0: print(f'    {comm:<24}{v/1024:9.1f} MiB')
PY
  '';

  sampler = pkgs.writeShellScript "vram-sampler-run" ''
    set -u
    cat=${pkgs.coreutils}/bin/cat
    date=${pkgs.coreutils}/bin/date

    # Biggest amdgpu card, same selection the rest of the repo uses.
    CARD=""; TOTAL=0
    for d in /sys/class/drm/card*/device; do
      t=$($cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
      if [ "$t" -gt "$TOTAL" ]; then TOTAL=$t; CARD=$d; fi
    done
    [ -z "$CARD" ] && { echo "vram-sampler: no amdgpu card"; exit 0; }
    PDEV=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "$CARD")")

    ${pkgs.coreutils}/bin/mkdir -p ${stateDir}
    LOG=${stateDir}/samples.csv
    PEAK=${stateDir}/peak.txt
    [ -s "$LOG" ] || echo "ts,vram_mib,gtt_mib,busy_pct,compositor,windows" > "$LOG"

    # The peak is per-compositor: comparing swayfx's peak against sway's is the
    # entire point, so a run under the other one must not overwrite it.
    read_peak() { ${pkgs.gnugrep}/bin/grep -m1 "^$1 " ${stateDir}/peaks 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}'; }

    while :; do
      USED=$($cat "$CARD/mem_info_vram_used" 2>/dev/null || echo 0)
      GTT=$($cat "$CARD/mem_info_gtt_used" 2>/dev/null || echo 0)
      BUSY=$($cat "$CARD/gpu_busy_percent" 2>/dev/null || echo 0)
      UMIB=$(( USED / 1048576 ))

      # Which compositor is running right now — this is what makes the log an
      # A/B rather than one undifferentiated pile of numbers.
      COMP="none"
      SPID=$(${pkgs.procps}/bin/pgrep -x sway 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
      if [ -n "$SPID" ]; then
        COMP=$(${pkgs.coreutils}/bin/readlink -f "/proc/$SPID/exe" 2>/dev/null \
                 | ${pkgs.gnugrep}/bin/grep -oE 'sway(fx)?-unwrapped-[0-9.]+' || echo "sway?")
      fi

      # Window count as a crude proxy for "how much was open" — a peak with 4
      # windows and a peak with 20 are not the same event.
      WINS=$(${pkgs.procps}/bin/pgrep -c -f 'kitty|chromium|zen|code|electron|alacritty|obsidian' 2>/dev/null || echo 0)

      echo "$($date +%s),$UMIB,$(( GTT / 1048576 )),$BUSY,$COMP,$WINS" >> "$LOG"

      OLD=$(read_peak "$COMP"); OLD=''${OLD:-0}
      if [ "$UMIB" -gt "$OLD" ]; then
        ${pkgs.gnused}/bin/sed -i "/^$COMP /d" ${stateDir}/peaks 2>/dev/null || true
        echo "$COMP $UMIB" >> ${stateDir}/peaks
        {
          echo "=== new peak for $COMP: $UMIB MiB of $(( TOTAL / 1048576 )) MiB at $($date '+%F %T') ==="
          echo "    gtt $(( GTT / 1048576 )) MiB, gpu $BUSY%, $WINS client processes"
          ${breakdown} "$PDEV"
          echo
        } >> "$PEAK"
      fi

      # Bound the log without a logrotate dependency.
      L=$(${pkgs.coreutils}/bin/wc -l < "$LOG")
      if [ "$L" -gt ${toString maxLines} ]; then
        ${pkgs.coreutils}/bin/tail -n $(( ${toString maxLines} / 2 )) "$LOG" > "$LOG.tmp"
        ${pkgs.coreutils}/bin/mv "$LOG.tmp" "$LOG"
      fi

      ${pkgs.coreutils}/bin/sleep ${toString interval}
    done
  '';

  report = pkgs.writeShellScriptBin "vram-report" ''
    ${pkgs.python3}/bin/python3 - "$@" <<'PY'
import collections, os, sys, time
LOG = "${stateDir}/samples.csv"
if not os.path.exists(LOG):
    print("no samples yet — is vram-sampler.service running?"); sys.exit(0)
by = collections.defaultdict(list)
first = {}; last = {}
for line in open(LOG):
    p = line.strip().split(',')
    if len(p) < 6 or p[0] == 'ts': continue
    try: ts, v, g, b, comp, w = int(p[0]), int(p[1]), int(p[2]), int(p[3]), p[4], int(p[5])
    except ValueError: continue
    by[comp].append((v, g, w))
    first.setdefault(comp, ts); last[comp] = ts
def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(len(xs) * q))]
print(f'{"compositor":<28}{"samples":>9}{"hours":>7}{"median":>9}{"p95":>8}{"PEAK":>8}{"peak GTT":>10}')
for comp in sorted(by, key=lambda c: -max(x[0] for x in by[c])):
    rows = by[comp]
    if comp == 'none': continue
    vs = [r[0] for r in rows]
    peak = max(vs)
    pg = max(r[1] for r in rows if r[0] == peak)
    hrs = (last[comp] - first[comp]) / 3600.0
    print(f'{comp:<28}{len(rows):>9}{hrs:>7.1f}{pct(vs,0.5):>9}{pct(vs,0.95):>8}{peak:>8}{pg:>10}')
print("\nall figures MiB. median/p95 are what you live with; PEAK is what decides")
print("whether a model fits. Per-process breakdown at each peak:")
print(f"  cat ${stateDir}/peak.txt")
tot = 0
try: tot = int(open('/sys/class/drm/card1/device/mem_info_vram_total').read()) // 1048576
except Exception: pass
if tot:
    print(f"\ncard is {tot} MiB; headroom for a model = {tot} - PEAK")
PY
  '';
in
{
  config = lib.mkIf enabled {
    systemd.services.vram-sampler = {
      description = "Sample GPU VRAM use over time (peak tracking)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${sampler}";
        Restart = "always";
        RestartSec = 10;
        Nice = 19;
        IOSchedulingClass = "idle";
        StateDirectory = "vram-sampler";
      };
    };
    environment.systemPackages = [ report ];
  };
}

# Local meeting recording + transcription
#   - Dual-channel capture: default sink monitor ("Them") + default mic ("Me")
#   - Transcribe each WAV separately with whisper.cpp (Vulkan/AMD), multilingual auto-detect
#   - Merge segments interleaved by timestamp into a single labeled transcript.txt
#   - Keeps BOTH the WAVs and the transcript under ~/Nextcloud/myLibrary/MyMeetings/<timestamp>/
#     (so they sync via Nextcloud)
#
# Commands (DESK only, gated by userSettings.meetingTranscribeEnable):
#   meeting              record + auto-transcribe on Ctrl-C (one-shot)
#   meeting-record       start dual capture, Ctrl-C to stop & finalize
#   meeting-transcribe   whisper.cpp on both WAVs -> JSON/SRT -> merged transcript.txt
#   meeting-merge        interleave two whisper JSONs into a labeled transcript
{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  userSettings,
  systemSettings,
  ...
}:

let
  cfgEnable = (userSettings.meetingTranscribeEnable or false);

  # whisper.cpp built with Vulkan for AMD GPU acceleration (RADV already configured on DESK).
  whisperVulkan = pkgs.whisper-cpp.override { vulkanSupport = true; };
  WHISPER = lib.getExe' whisperVulkan "whisper-cli";

  # Multilingual model pinned into the Nix store (declarative, reproducible). ~3.1 GiB.
  # large-v3 (full, not turbo): markedly better on accented/non-native English + rare
  # vocabulary than the turbo variant. Hash via: nix-prefetch-url <url>
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin";
    sha256 = "1qnijhsv47x1vx2vixy4jr8n0k6q8ham9ggrqh1m53dr82s85lb4";
  };

  FFMPEG = lib.getExe pkgs.ffmpeg;
  JQ = lib.getExe pkgs.jq;
  PACTL = lib.getExe' pkgs.pulseaudio "pactl";

  # Common PATH for bare coreutils/date/mkdir/ls/awk (repo gotcha: writeShellScript has no coreutils on PATH).
  binPath = lib.makeBinPath [ pkgs.coreutils pkgs.gnused pkgs.gawk pkgs.pulseaudio pkgs.ffmpeg pkgs.jq ];

  meetingsRoot = "${config.home.homeDirectory}/Nextcloud/myLibrary/MyMeetings";

  # -------------------------------------------------------------------------
  # meeting-record : start dual capture into a timestamped dir, stop on Ctrl-C
  # -------------------------------------------------------------------------
  meeting-record = pkgs.writeShellScriptBin "meeting-record" ''
    #!/bin/sh
    set -eu
    export PATH="${binPath}:$PATH"

    PACTL='${PACTL}'
    FFMPEG='${FFMPEG}'

    TS="$(date +%Y-%m-%d_%H-%M-%S)"
    DIR="''${1:-${meetingsRoot}/$TS}"
    mkdir -p "$DIR"

    # Resolve current PipeWire defaults at runtime (handles Bluetooth/headset changes).
    SINK="$("$PACTL" get-default-sink)"
    MON="''${SINK}.monitor"
    SRC="$("$PACTL" get-default-source)"

    echo "meeting-record: dir   = $DIR"  >&2
    echo "meeting-record: them  = $MON"  >&2
    echo "meeting-record: me    = $SRC"  >&2
    echo "meeting-record: recording... press Ctrl-C to stop." >&2

    # Two independent ffmpeg processes -> two mono 16 kHz WAVs (ideal for whisper).
    # Separate processes so a glitch on one channel can't corrupt the other.
    "$FFMPEG" -hide_banner -loglevel warning -nostdin \
      -f pulse -i "$MON" -ac 1 -ar 16000 -c:a pcm_s16le "$DIR/them.wav" &
    PID_THEM=$!
    "$FFMPEG" -hide_banner -loglevel warning -nostdin \
      -f pulse -i "$SRC" -ac 1 -ar 16000 -c:a pcm_s16le "$DIR/me.wav" &
    PID_ME=$!

    # Record metadata for reference.
    {
      echo "timestamp=$TS"
      echo "sink=$SINK"
      echo "monitor=$MON"
      echo "source=$SRC"
    } > "$DIR/recording.meta"

    # Clean stop: send SIGINT to ffmpeg so it writes a valid WAV trailer, then wait.
    stop() {
      echo "meeting-record: stopping, finalizing WAVs..." >&2
      kill -INT "$PID_THEM" "$PID_ME" 2>/dev/null || true
      wait "$PID_THEM" 2>/dev/null || true
      wait "$PID_ME"   2>/dev/null || true
      echo "meeting-record: saved to $DIR" >&2
      echo "$DIR"            # contract: dir is the LAST stdout line
      exit 0
    }
    trap stop INT TERM

    # Block until either process dies (or we get a signal).
    wait "$PID_THEM" "$PID_ME"
    stop
  '';

  # -------------------------------------------------------------------------
  # meeting-merge : interleave two whisper JSONs into transcript.txt
  #   args: <me.json> <them.json> <out.txt>
  # -------------------------------------------------------------------------
  meeting-merge = pkgs.writeShellScriptBin "meeting-merge" ''
    #!/bin/sh
    set -eu
    export PATH="${binPath}:$PATH"
    JQ='${JQ}'

    ME_JSON="$1"; THEM_JSON="$2"; OUT="$3"

    # Tag each segment with a speaker, concat both, sort by start offset (ms),
    # then format as [HH:MM:SS] Speaker: text. Zero-pad via (n+100|tostring)[1:].
    "$JQ" -rn \
      --slurpfile me   "$ME_JSON" \
      --slurpfile them "$THEM_JSON" '
        ( ($me[0].transcription   // []) | map({spk:"Me",   from:.offsets.from, text:.text}) )
      + ( ($them[0].transcription // []) | map({spk:"Them", from:.offsets.from, text:.text}) )
      | sort_by(.from) | .[]
      | (.from/1000|floor) as $t
      | ($t/3600|floor) as $h | (($t%3600)/60|floor) as $m | ($t%60) as $s
      | "[\(($h+100|tostring)[1:]):\(($m+100|tostring)[1:]):\(($s+100|tostring)[1:])] \(.spk): \(.text|gsub("^\\s+|\\s+$";""))"
      ' > "$OUT"

    echo "$OUT"
  '';

  # -------------------------------------------------------------------------
  # meeting-transcribe : run whisper on both WAVs -> JSON + SRT, then merge
  #   arg: <dir>  (defaults to newest dir under the meetings root)
  # -------------------------------------------------------------------------
  meeting-transcribe = pkgs.writeShellScriptBin "meeting-transcribe" ''
    #!/bin/sh
    set -eu
    export PATH="${binPath}:$PATH"
    WHISPER='${WHISPER}'
    MODEL='${whisperModel}'
    FFMPEG='${FFMPEG}'

    DIR="''${1:-}"
    if [ -z "$DIR" ]; then
      DIR="$(ls -dt ${meetingsRoot}/*/ 2>/dev/null | head -n1 || true)"
    fi
    [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "meeting-transcribe: no dir given and none found" >&2; exit 1; }
    DIR="''${DIR%/}"

    # Optional initial prompt to prime domain vocabulary (proper nouns, jargon).
    # Priority: $DIR/prompt.txt  >  $MEETING_PROMPT env var  >  none.
    PROMPT=""
    if [ -f "$DIR/prompt.txt" ]; then
      PROMPT="$(cat "$DIR/prompt.txt")"
    elif [ -n "''${MEETING_PROMPT:-}" ]; then
      PROMPT="$MEETING_PROMPT"
    fi

    transcribe_one() {
      WAV="$1"; BASE="$2"
      [ -f "$WAV" ] || { echo "meeting-transcribe: missing $WAV" >&2; return 0; }

      # Silence gate: skip near-silent channels so Whisper can't hallucinate phrases
      # like "you"/"Thank you" on a quiet/empty channel (e.g. solo test, or long pauses
      # on the remote side). Real speech always peaks well above -35 dB.
      MAXVOL="$("$FFMPEG" -hide_banner -nostats -i "$WAV" -af volumedetect -f null - 2>&1 \
        | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p' | head -n1)"
      if [ -n "$MAXVOL" ] && awk -v v="$MAXVOL" 'BEGIN { exit !(v < -35) }'; then
        echo "meeting-transcribe: $WAV near-silent (max ''${MAXVOL} dB) — skipping" >&2
        printf '{"transcription":[]}\n' > "$BASE.json"
        return 0
      fi

      echo "meeting-transcribe: $WAV (Vulkan GPU)..." >&2
      # -l auto : multilingual detection (default would be 'en')
      # -sns    : suppress non-speech tokens
      # -bs/-bo : beam search (already the build default; explicit for clarity)
      # -mc 0   : do NOT carry previous-text context. Critical: without this, large-v3
      #           can spiral into repetition loops (a whole tail of duplicated lines),
      #           especially once an initial prompt is in play. Costs a little prompt
      #           potency but removes the catastrophic failure mode.
      set -- -m "$MODEL" -f "$WAV" -l auto -sns -bs 5 -bo 5 -mc 0 -oj -osrt -of "$BASE"
      # Optional vocabulary priming. --carry-initial-prompt re-applies it to every window
      # (since -mc 0 otherwise drops it after the first). Separate args so multi-word
      # prompts don't word-split.
      [ -n "$PROMPT" ] && set -- "$@" --carry-initial-prompt --prompt "$PROMPT"
      "$WHISPER" "$@"
    }

    transcribe_one "$DIR/me.wav"   "$DIR/me"
    transcribe_one "$DIR/them.wav" "$DIR/them"

    if [ -f "$DIR/me.json" ] && [ -f "$DIR/them.json" ]; then
      meeting-merge "$DIR/me.json" "$DIR/them.json" "$DIR/transcript.txt"
      echo "meeting-transcribe: wrote $DIR/transcript.txt" >&2
    else
      echo "meeting-transcribe: one or both JSONs missing; check WAVs" >&2
      exit 1
    fi
  '';

  # -------------------------------------------------------------------------
  # meeting : record, then auto-transcribe on stop
  # -------------------------------------------------------------------------
  meeting = pkgs.writeShellScriptBin "meeting" ''
    #!/bin/sh
    set -eu
    export PATH="${binPath}:$PATH"
    DIR="$(meeting-record | tail -n1)"
    [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "meeting: recording produced no dir" >&2; exit 1; }
    meeting-transcribe "$DIR"
  '';
in
{
  config = lib.mkIf cfgEnable {
    # Only the command wrappers go on PATH. whisper-cli/ffmpeg/pactl/jq are referenced
    # by absolute store path inside the scripts, so adding them here would only risk
    # env conflicts (e.g. DESK already ships ffmpeg-full -> duplicate bin/ffmpeg).
    home.packages = [
      meeting-record
      meeting-transcribe
      meeting-merge
      meeting
    ];
  };
}

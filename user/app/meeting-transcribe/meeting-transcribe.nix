# Local meeting recording + transcription
#   - Dual-channel capture: default sink monitor ("Them") + default mic ("Me")
#   - Transcribe each WAV separately with whisper.cpp (Vulkan/AMD), multilingual auto-detect
#   - Merge segments interleaved by timestamp into a single labeled transcript.txt
#   - Keeps BOTH the WAVs and the transcript under ~/Nextcloud/myLibrary/MyMeetings/<timestamp>/
#     (so they sync via Nextcloud)
#
# DESK_W11 (NixOS-WSL, userSettings.meetingWindowsCaptureEnable): WSL cannot hear Windows
# (WSLg's pulse monitor carries Linux apps only) and cannot use the GPU (dzn segfaults or
# finds no device), so meeting-record drives win/ (meetcap.exe, WASAPI) and whisper runs
# on the CPU after the call. Everything downstream of the two WAVs is this same file.
# Plan + measurements: docs/akunito/plans/desk-w11-meeting-captions.md
#
# Commands (gated by userSettings.meetingTranscribeEnable):
#   meeting [--local]    record + auto-transcribe on Ctrl-C (one-shot)
#   meeting-record       start dual capture, Ctrl-C to stop & finalize
#   meeting-transcribe [--local] [dir]
#                        whisper.cpp on both WAVs -> JSON/SRT -> merged transcript.txt
#   With userSettings.meetingLocalWhisperOnDemand, whisper runs on this machine only with
#   --local; without it both commands print the command to run and load nothing.
#   meeting-merge        interleave two whisper JSONs into a labeled transcript
#   meeting-stop         (DESK_W11) stop the running recording from another shell
#   meeting-win-install  (DESK_W11) test + publish win/ to %LOCALAPPDATA%\MeetCap
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
  winCapture = (userSettings.meetingWindowsCaptureEnable or false);
  # GPU whisper inside meetcap.exe (Whisper.net, Vulkan): 60 s clip in 7-10 s against 67 s on
  # the WSL CPU. Off = whisper-cli on the CPU, the fallback that needs nothing on Windows
  # but the recorder.
  winWhisper = winCapture && (userSettings.meetingWindowsWhisperEnable or false);
  # The model loads on this machine's GPU only when asked for with --local (4.3 GiB of
  # VRAM for large-v3, on a box that is also the gaming box). Without it `meeting` records
  # and stops, and `meeting-transcribe` prints the command instead of running it. The
  # default backend will be the whisper service on the NAS once its GPU is in; until then
  # there is none, so "not available" is the only answer it can give.
  localOnDemand = (userSettings.meetingLocalWhisperOnDemand or false);
  winDir = "/mnt/c/Users/${systemSettings.wslWindowsUser}/AppData/Local/MeetCap";
  MEETCAP = "${winDir}/meetcap.exe";

  # Measured on DESK_W11, 60 s clip, large-v3: -t 12 = 67 s, -t 8 = 71 s, default (4) slower.
  # -ng keeps the Vulkan build off dzn, which segfaults (mesa 25.2.6) when it gets a device.
  whisperCpuArgs = lib.optionalString winCapture ''-ng -t "$(nproc)"'';

  # One channel -> $BASE.json + $BASE.srt, and the language probe. Same parameters on both
  # sides except -sns, which the exe cannot have (see win/src/MeetCap/Transcriber.cs).
  # DET = the language, or empty when whisper is not sure (p < 0.5). Measured on de-silenced
  # probes (DESK_W11, 2026-09-30): real speech 0.93-0.99, even 1 s of it; mic noise with
  # nobody talking "en" 0.25 - and transcribing that channel as English produced 15 lines
  # of a cooking video.
  detectLang =
    if winWhisper then ''
      DET="$("$MEETCAP" detect-lang "$(wslpath -w "$SAMPLE")" 2>/dev/null | tr -d '\r' | head -n1)"
    '' else ''
      DET="$("$WHISPER" -m "$MODEL" -f "$SAMPLE" -l auto -dl ${whisperCpuArgs} 2>&1 \
        | sed -n 's/.*auto-detected language: \([a-z][a-z]\) (p = \([0-9.]*\)).*/\1 \2/p' | head -n1 \
        | awk '$2 >= 0.5 { print $1 }')"
    '';
  runWhisper =
    if winWhisper then ''
      # --out is built from the directory: wslpath refuses a path that does not exist yet.
      set -- transcribe "$(wslpath -w "$WAV")" --lang "$LANG" \
        --out "$(wslpath -w "$(dirname "$BASE")")\\$(basename "$BASE")"
      [ -n "$PROMPT" ] && set -- "$@" --prompt "$PROMPT"
      "$MEETCAP" "$@"
    '' else ''
      # -l LANG : detected/overridden language (never raw -l auto; see above)
      # -sns    : suppress non-speech tokens
      # -bs/-bo : beam search (already the build default; explicit for clarity)
      # -mc 0   : do NOT carry previous-text context. Critical: without this, large-v3
      #           can spiral into repetition loops (a whole tail of duplicated lines),
      #           especially once an initial prompt is in play. Costs a little prompt
      #           potency but removes the catastrophic failure mode.
      set -- -m "$MODEL" -f "$WAV" -l "$LANG" -sns -bs 5 -bo 5 -mc 0 -oj -osrt -of "$BASE" ${whisperCpuArgs}
      # Optional vocabulary priming. --carry-initial-prompt re-applies it to every window
      # (since -mc 0 otherwise drops it after the first). Separate args so multi-word
      # prompts don't word-split.
      [ -n "$PROMPT" ] && set -- "$@" --carry-initial-prompt --prompt "$PROMPT"
      "$WHISPER" "$@"
    '';

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
  # meeting-record (DESK_W11) : same contract, capture done by meetcap.exe on Windows
  #
  # The stub WSL runs for a Windows exe must never receive a signal: SIGINT to it kills
  # the Windows process outright (measured: gone in 3 s, no handler ran), leaving WAVs
  # with a stale header. Ctrl-C goes to the whole foreground process group, and being a
  # background job does not shield the stub (measured: it died with the group, WAVs not
  # finalized), so it runs in its own session (setsid) and the trap asks the exe to stop
  # through `meetcap stop`, a named event. recording.done is the proof that it finalized.
  # MEETING_RENDER / MEETING_MIC pick an endpoint by name (`meetcap.exe devices`).
  # -------------------------------------------------------------------------
  meeting-record-win = pkgs.writeShellScriptBin "meeting-record" ''
    set -eu
    export PATH="${binPath}:/sbin:$PATH"
    MEETCAP='${MEETCAP}'
    [ -x "$MEETCAP" ] || { echo "meeting-record: $MEETCAP missing, run meeting-win-install" >&2; exit 1; }

    TS="$(date +%Y-%m-%d_%H-%M-%S)"
    DIR="''${1:-${meetingsRoot}/$TS}"
    mkdir -p "$DIR"

    set -- record "$(wslpath -w "$DIR")"
    [ -n "''${MEETING_RENDER:-}" ] && set -- "$@" --render "$MEETING_RENDER"
    [ -n "''${MEETING_MIC:-}" ]    && set -- "$@" --mic "$MEETING_MIC"

    echo "meeting-record: dir   = $DIR" >&2
    echo "meeting-record: recording... press Ctrl-C to stop." >&2

    stop() { "$MEETCAP" stop >&2 || true; }
    trap stop INT TERM HUP

    '${lib.getExe' pkgs.util-linux "setsid"}' "$MEETCAP" "$@" >&2 </dev/null &
    PID=$!
    # wait returns early each time the trap runs
    while kill -0 "$PID" 2>/dev/null; do wait "$PID" 2>/dev/null || true; done

    [ -f "$DIR/recording.done" ] || { echo "meeting-record: recorder did not finalize, WAVs in $DIR may be short" >&2; exit 1; }
    echo "meeting-record: saved to $DIR" >&2
    echo "$DIR"            # contract: dir is the LAST stdout line
  '';

  # Stops a recording from anywhere (another terminal, a Claude session); `meeting` then
  # carries on to the transcription as if Ctrl-C had been pressed.
  meeting-stop = pkgs.writeShellScriptBin "meeting-stop" ''
    exec '${MEETCAP}' stop
  '';

  # -------------------------------------------------------------------------
  # meeting-win-install : publish win/ to the Windows side. Not a nix build: NuGet
  # restore needs the network, same as AkuWM. Run after any change under win/.
  # -------------------------------------------------------------------------
  meeting-win-install = pkgs.writeShellScriptBin "meeting-win-install" ''
    set -eu
    export PATH="${binPath}:$PATH"
    export DOTNET_ROOT='${pkgs.dotnet-sdk_8}/share/dotnet' DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cp -r ${./win}/. "$TMP/"
    chmod -R u+w "$TMP"
    '${pkgs.dotnet-sdk_8}/bin/dotnet' test "$TMP/tests/MeetCap.Tests"
    '${pkgs.dotnet-sdk_8}/bin/dotnet' publish "$TMP/src/MeetCap" -c Release -r win-x64 --self-contained -o '${winDir}'
    # The model has to sit on NTFS: through \\wsl.localhost it loads in 174 s, from C:\ in 4 s.
    M='${winDir}/models/ggml-large-v3.bin'
    mkdir -p '${winDir}/models'
    if [ "$(stat -c %s "$M" 2>/dev/null || echo 0)" != "$(stat -c %s '${whisperModel}')" ]; then
      cp '${whisperModel}' "$M.tmp" && mv -f "$M.tmp" "$M"
    fi
    echo "meeting-win-install: ${winDir}"
  '';

  # -------------------------------------------------------------------------
  # meeting-merge : interleave two whisper JSONs into transcript.txt
  #   args: <me.json> <them.json> <out.txt> [me.silence.json] [them.silence.json]
  #
  # Two post-filters keep the dead air out of the transcript WITHOUT ever
  # changing how real speech is transcribed (Whisper already ran; this only
  # decides which output lines to keep):
  #   (1) per-segment silence gate — drop a line if >95% of its time window is
  #       covered by silence intervals detected on the WAV (passed in as ms
  #       pairs). Surgical: lines over real audio are byte-for-byte unchanged.
  #       The 95% (not 80%) keep-margin preserves brief real speech buried in a
  #       long sparse segment (e.g. a "¿Hola?" greeting then a 20s connect wait,
  #       which Whisper groups as one ~91%-silent segment); a true hallucination
  #       sits over ~100% silence and is still dropped.
  #       A segment with 500 ms or more of non-silent audio is kept whatever the fraction,
  #       and is stamped where its audio starts: a single "1.400" said at 0:17 of a quiet
  #       mic came back as one segment 0-17.4 s (96.6% silent), was dropped, and would
  #       have sorted to 00:00:00 (DESK_W11, 2026-09-30).
  #   (2) caption-hallucination filter — Whisper emits YouTube training
  #       artifacts over silence ("Gracias por ver el video", "Suscríbete al
  #       canal", "Subtitles by amara.org", "Thanks for watching", ...). Drop
  #       those, plus collapse runs of identical lines (keep at most 2) so a
  #       genuine repeat survives but a flood of "Gracias" does not. Also a line that is
  #       nothing but an annotation ("[Música]", "(risas)", "*suspiro*", "♪♪"): whisper-cli's
  #       -sns never emits those, the Windows GPU backend has no -sns.
  # Silence files are optional: legacy dirs whose WAVs were deleted fall back
  # to filter (2) only (silence defaults to []).
  # -------------------------------------------------------------------------
  meeting-merge = pkgs.writeShellScriptBin "meeting-merge" ''
    #!/bin/sh
    set -eu
    export PATH="${binPath}:$PATH"
    JQ='${JQ}'

    ME_JSON="$1"; THEM_JSON="$2"; OUT="$3"
    ME_SIL_FILE="''${4:-}"; THEM_SIL_FILE="''${5:-}"

    ME_SIL='[]'; THEM_SIL='[]'
    [ -n "$ME_SIL_FILE" ]   && [ -f "$ME_SIL_FILE" ]   && ME_SIL="$(cat "$ME_SIL_FILE")"
    [ -n "$THEM_SIL_FILE" ] && [ -f "$THEM_SIL_FILE" ] && THEM_SIL="$(cat "$THEM_SIL_FILE")"

    "$JQ" -rn \
      --slurpfile me   "$ME_JSON" \
      --slurpfile them "$THEM_JSON" \
      --argjson  meSil   "$ME_SIL" \
      --argjson  themSil "$THEM_SIL" '
        # normalized form (lowercase, punctuation -> space) for empty/run checks
        def norm: ((. // "") | ascii_downcase | gsub("[[:punct:]]";" ") | gsub("\\s+";" ") | gsub("^ +| +$";""));

        # caption-style hallucinations Whisper emits over silence
        def isJunk:
          ((. // "") | ascii_downcase | gsub("\\s+";" ") | gsub("^ +| +$";"")) as $t
          | ($t | test("gracias por ver"))
            or ($t | test("suscr.bete"))
            or ($t | test("subt.tulos (por|realizados)"))
            or ($t | test("amara\\.org"))
            or ($t | test("thanks for watching"))
            or ($t | test("thank you for watching"))
            or ($t | test("^cc "))
            or ($t | test("^[\\[(*][^\\])*]*[\\])*]$"))
            or ($t | test("^[♪♩♫♬ ]+$"))
            or ($t | test("subscribe to"))
            or ($t | test("bienvenidos a mi canal"))
            or ($t | test("welcome (back )?to my channel"));

        # fraction of [a,b] (ms) covered by the silence intervals
        def overlapFrac($a; $b; $sil):
          (($b - $a) | if . < 1 then 1 else . end) as $len
          | ([ $sil[] | (([$b, .[1]] | min) - ([$a, .[0]] | max)) | if . > 0 then . else 0 end ] | add // 0) / $len;

        def silentMs($a; $b; $sil):
          [ $sil[] | (([$b, .[1]] | min) - ([$a, .[0]] | max)) | if . > 0 then . else 0 end ] | add // 0;

        # end of the silence the segment starts in, if any (never past the segment)
        def speechStart($a; $b; $sil):
          ([ $sil[] | select(.[0] <= $a and .[1] > $a) | .[1] ] | max // $a) | if . >= $b then $a else . end;

        # per-channel: drop silence-covered + junk + empty, then collapse identical runs (keep <=2)
        def clean($sil):
          [ .[]
            | select( overlapFrac(.offsets.from; .offsets.to; $sil) <= 0.95
                      or ((.offsets.to - .offsets.from) - silentMs(.offsets.from; .offsets.to; $sil)) >= 500 )
            | .offsets.from = speechStart(.offsets.from; .offsets.to; $sil)
            | select( (.text | norm) != "" )
            | select( (.text | isJunk) | not ) ]
          | reduce .[] as $x ({out:[], prev:null, run:0};
              ($x.text | norm) as $n
              | if $n == .prev
                then (.run + 1) as $r
                  | (if $r < 2 then {out:(.out+[$x]), prev:$n, run:$r}
                     else {out:.out, prev:$n, run:$r} end)
                else {out:(.out+[$x]), prev:$n, run:0} end)
          | .out;

        # Tag each kept segment with a speaker, concat both, sort by start
        # offset (ms), then format as [HH:MM:SS] Speaker: text.
          ( ($me[0].transcription   // []) | clean($meSil)   | map({spk:"Me",   from:.offsets.from, text:.text}) )
        + ( ($them[0].transcription // []) | clean($themSil) | map({spk:"Them", from:.offsets.from, text:.text}) )
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
    export PATH="${binPath}:/sbin:$PATH"
    ${if winWhisper then "MEETCAP='${MEETCAP}'" else "WHISPER='${WHISPER}'\n    MODEL='${whisperModel}'"}
    FFMPEG='${FFMPEG}'

    LOCAL=${if localOnDemand then "0" else "1"}
    DIR=""
    for a in "$@"; do
      case "$a" in
        --local) LOCAL=1 ;;
        *) DIR="$a" ;;
      esac
    done
    if [ -z "$DIR" ]; then
      DIR="$(ls -dt ${meetingsRoot}/*/ 2>/dev/null | head -n1 || true)"
    fi
    [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "meeting-transcribe: no dir given and none found" >&2; exit 1; }
    DIR="''${DIR%/}"

    if [ "$LOCAL" = 0 ]; then
      echo "meeting-transcribe: the NAS whisper service is not available; nothing was loaded on this machine." >&2
      echo "meeting-transcribe: to transcribe here, on the local GPU:" >&2
      echo "    meeting-transcribe --local '$DIR'" >&2
      exit 3
    fi

    # Optional initial prompt to prime domain vocabulary (proper nouns, jargon).
    # Priority: $DIR/prompt.txt  >  $MEETING_PROMPT env var  >  none.
    PROMPT=""
    if [ -f "$DIR/prompt.txt" ]; then
      PROMPT="$(cat "$DIR/prompt.txt")"
    elif [ -n "''${MEETING_PROMPT:-}" ]; then
      PROMPT="$MEETING_PROMPT"
    fi

    # Language selection. Priority: $DIR/lang.txt > $MEETING_LANG > "auto".
    # "auto" does NOT hand the raw WAV to whisper's -l auto: whisper detects the
    # language from ONLY the first 30 s and then locks it for the whole file. On a
    # sparse channel where you are silent at the start, that 30 s is dead air over
    # which whisper hallucinates a caption-ghost in a random language (a real case:
    # a Russian "Субтитры создавал…" ghost detected ru p=0.48 and force-decoded two
    # hours of Spanish into Cyrillic). Instead, per channel below we detect on a
    # DE-SILENCED speech-only sample (es p=0.97 on the same audio). A fixed override
    # skips detection entirely.
    LANG_OPT="auto"
    if [ -f "$DIR/lang.txt" ]; then
      LANG_OPT="$(cat "$DIR/lang.txt")"
    elif [ -n "''${MEETING_LANG:-}" ]; then
      LANG_OPT="$MEETING_LANG"
    fi

    # Language of one channel, on stdout; empty when there is no confident answer. "auto"
    # detects on a de-silenced sample so leading/inter-word dead air can't force the wrong
    # language for the whole file (see LANG_OPT note above).
    probe_lang() {
      WAV="$1"; BASE="$2"
      [ "$LANG_OPT" = "auto" ] || { echo "$LANG_OPT"; return 0; }
      [ -f "$WAV" ] || return 0
      SAMPLE="$BASE.langprobe.wav"
      # start_periods=1 strips leading silence; stop_periods=-1 removes every
      # silent gap > stop_duration too, packing ~40 s of pure speech to detect on.
      "$FFMPEG" -hide_banner -loglevel error -y -i "$WAV" \
        -af "silenceremove=start_periods=1:stop_periods=-1:stop_threshold=-40dB:stop_duration=1:start_threshold=-40dB" \
        -t 40 "$SAMPLE" 2>/dev/null || true
      DET=""
      if [ -s "$SAMPLE" ]; then
        ${detectLang}
      fi
      rm -f "$SAMPLE"
      echo "$DET"
    }

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

      LANG="$3"
      echo "meeting-transcribe: $WAV (${if winWhisper then "Vulkan GPU, Windows" else if winCapture then "CPU" else "Vulkan GPU"})..." >&2
      ${runWhisper}
    }

    # Detect silence intervals on each WAV (one cheap CPU pass, no GPU). Whisper
    # has already produced its JSON from the full audio; this only feeds the
    # per-segment silence gate in meeting-merge so phantom lines emitted over
    # dead air get dropped. noise floor -40 dB, min silent run 2 s. Output is a
    # JSON array of [start_ms, end_ms] pairs (or [] if the WAV is gone/all sound).
    detect_silence() {
      WAV="$1"; OUT="$2"
      if [ ! -f "$WAV" ]; then echo "[]" > "$OUT"; return 0; fi
      "$FFMPEG" -hide_banner -nostats -i "$WAV" -af silencedetect=noise=-40dB:d=2 -f null - 2>&1 \
      | awk '
          BEGIN { printf "[" }
          /silence_start:/ { for (i=1;i<=NF;i++) if ($i=="silence_start:") s=$(i+1); open=1 }
          /silence_end:/   { for (i=1;i<=NF;i++) if ($i=="silence_end:")   e=$(i+1);
                             if (open) { printf "%s[%d,%d]", (n++?",":""), s*1000, e*1000; open=0 } }
          END { if (open) { printf "%s[%d,%d]", (n++?",":""), s*1000, 2147483647 } printf "]" }
        ' > "$OUT"
    }

    # A channel with no confident language of its own takes the other one's: both sides of
    # a call speak the same language far more often than not, and the alternative is raw
    # -l auto, which is how a silent channel gets decoded in a random one.
    ME_LANG="$(probe_lang "$DIR/me.wav" "$DIR/me")"
    THEM_LANG="$(probe_lang "$DIR/them.wav" "$DIR/them")"
    echo "meeting-transcribe: language me=''${ME_LANG:-?} them=''${THEM_LANG:-?}" >&2
    [ -n "$ME_LANG" ]   || ME_LANG="$THEM_LANG"
    [ -n "$THEM_LANG" ] || THEM_LANG="$ME_LANG"

    transcribe_one "$DIR/me.wav"   "$DIR/me"   "''${ME_LANG:-auto}"
    transcribe_one "$DIR/them.wav" "$DIR/them" "''${THEM_LANG:-auto}"

    detect_silence "$DIR/me.wav"   "$DIR/me.silence.json"
    detect_silence "$DIR/them.wav" "$DIR/them.silence.json"

    if [ -f "$DIR/me.json" ] && [ -f "$DIR/them.json" ]; then
      meeting-merge "$DIR/me.json" "$DIR/them.json" "$DIR/transcript.txt" \
        "$DIR/me.silence.json" "$DIR/them.silence.json"
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
    # Ctrl-C reaches the whole foreground group. Without a trap here bash dies with it, and
    # a `| tail` in the pipe dies too and takes the dir with it (measured on DESK_W11: the
    # recording finalized, `meeting` exited 130, nothing was transcribed). A trapped signal
    # is reset to default in children, so meeting-record still gets it and stops cleanly.
    LOCAL=""
    [ "''${1:-}" = "--local" ] && LOCAL="--local"
    trap : INT
    OUT="$(meeting-record)"
    trap - INT
    DIR="$(printf '%s\n' "$OUT" | tail -n1)"
    [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "meeting: recording produced no dir" >&2; exit 1; }
    # Exit 3 = recorded, not transcribed, and the command to do it was printed: not a failure.
    meeting-transcribe $LOCAL "$DIR" || { rc=$?; [ "$rc" = 3 ] && exit 0; exit "$rc"; }
  '';
in
{
  config = lib.mkIf cfgEnable {
    # Only the command wrappers go on PATH. whisper-cli/ffmpeg/pactl/jq are referenced
    # by absolute store path inside the scripts, so adding them here would only risk
    # env conflicts (e.g. DESK already ships ffmpeg-full -> duplicate bin/ffmpeg).
    home.packages = [
      (if winCapture then meeting-record-win else meeting-record)
      meeting-transcribe
      meeting-merge
      meeting
    ] ++ lib.optionals winCapture [ meeting-stop meeting-win-install ];
  };
}

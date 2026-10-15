# docker-image-reap — the weekly image/cache reaper behind the root `docker-image-prune`
# unit (system/app/docker.nix) and the rootless `docker-prune` user unit
# (system/app/docker-rootless-maintenance.nix). Talks to whatever daemon DOCKER_HOST names.
#
# `docker image prune` only removes DANGLING images. Old tagged images that no container
# uses were never removed: VPS_PROD had 76 images / 48 GB, 30.6 GB of it reclaimable, on
# 2026-10-15 (AINF-425). This also removes those, with a protect list, because
# `image prune -a --filter until=` has no name exclusion and dates by build time, not arrival.
#
# Removed: images no container references (stopped ones count), whose newest of Created /
# LastTagTime (= when it arrived here) is older than --days, and none of whose tags is
# protected. Then dangling images, then build cache unused for --cache-days.
# Protected:
#   plane-aku/*                   2 newest per repo + every ~/.homelab/*/.previous-image (the
#                                 image plane-deploy --rollback swaps back to — no container
#                                 references it, so without this it would go after 30 days)
#   mcr.microsoft.com/dotnet/sdk  scripts/rbuild; a new pull must not happen inside a routine
#                                 build (CLAUDE.md, VPS disk)
#   rea-sandbox:*                 REA manages these itself (ensure_image); Nix-built, so
#                                 Created is 1970 and every one would look ancient
#   itzg/minecraft-server:*       NAS AkuCraft stacks sit down with no container between the
#                                 bot's /start (compose up); a missing :latest would be
#                                 re-pulled newer, changing the Java under a modded server
#
# Removal is `docker image rm REF` without -f: dockerd refuses an image a container still
# uses, a second net under the in-use check (containers can appear between the two).
{ pkgs, docker }:

pkgs.writeShellApplication {
  name = "docker-image-reap";
  runtimeInputs = [ docker pkgs.coreutils pkgs.gawk pkgs.gnused ];
  text = ''
    days=30 cache_days=7 dry=false
    while [ $# -gt 0 ]; do
      case $1 in
        -n|--dry-run) dry=true ;;
        --days) days=$2; shift ;;
        --cache-days) cache_days=$2; shift ;;
        *) echo "usage: docker-image-reap [--dry-run] [--days N] [--cache-days N]" >&2; exit 2 ;;
      esac
      shift
    done

    # docker system df prints decimal units ("40.52GB", "94.21kB", "0B")
    df_bytes() {
      docker system df --format '{{.Type}}|{{.Size}}' \
        | awk -F'|' -v t="$1" '$1 == t { sub(/B$/, "", $2); print toupper($2) }' \
        | numfmt --from=si
    }
    used() { echo $(( $(df_bytes Images) + $(df_bytes "Build Cache") )); }
    human() { numfmt --to=si --suffix=B "$1"; }

    before=$(used)
    now=$(date +%s)
    cutoff=$(( now - days * 86400 ))

    declare -A in_use=() keep=() created=() size=() refs=()

    # A container removed between `ps` and `inspect` fails the inspect; retry on a fresh list.
    for _ in 1 2 3; do
      mapfile -t cids < <(docker ps -aq)
      [ ''${#cids[@]} -eq 0 ] && break
      if ids=$(docker container inspect -f '{{.Image}}' "''${cids[@]}" 2>/dev/null); then
        while read -r id; do in_use[$id]=1; done <<<"$ids"
        break
      fi
    done

    for f in "''${HOME:-/root}"/.homelab/*/.previous-image; do
      [ -f "$f" ] || continue
      read -r ref _ <"$f" && [ -n "$ref" ] && keep[$ref]="rollback ($f)"
    done

    mapfile -t lines < <(docker image ls --no-trunc --format '{{.ID}}|{{.Repository}}|{{.Tag}}')
    for l in "''${lines[@]}"; do
      IFS='|' read -r id repo tag <<<"$l"
      [ "$repo" = "<none>" ] || [ "$tag" = "<none>" ] && continue
      refs[$id]+="$repo:$tag "
    done

    if [ ''${#refs[@]} -gt 0 ]; then
      # The CLI hands the template LastTagTime untyped (no .Unix); it prints as
      # "2026-10-14 21:41:44.93 +0000 UTC", or 0001-01-01 when never tagged. date -d takes it
      # once the trailing zone name is cut.
      while IFS='|' read -r id c lt sz; do
        [ -n "$id" ] || continue
        c=$(date -d "$c" +%s)
        lt=$(date -d "''${lt% UTC}" +%s 2>/dev/null || echo 0)
        [ "$lt" -gt "$c" ] && c=$lt
        created[$id]=$c size[$id]=$sz
      done < <(docker image inspect -f '{{.Id}}|{{.Created}}|{{.Metadata.LastTagTime}}|{{.Size}}' "''${!refs[@]}")
    fi

    plane=()
    for id in "''${!refs[@]}"; do
      for ref in ''${refs[$id]}; do
        case $ref in
          plane-aku/*) plane+=("''${ref%:*} ''${created[$id]} $ref") ;;
          mcr.microsoft.com/dotnet/sdk:*|rea-sandbox:*|itzg/minecraft-server:*) keep[$ref]=pinned ;;
        esac
      done
    done
    if [ ''${#plane[@]} -gt 0 ]; then
      while read -r ref; do keep[$ref]="2 newest of its repo"; done < <(
        printf '%s\n' "''${plane[@]}" | sort -k1,1 -k2,2nr | awk 'n[$1]++ < 2 { print $3 }')
    fi

    removed=0 failed=0 listed=0
    for id in "''${!refs[@]}"; do
      [ -n "''${in_use[$id]:-}" ] && continue
      [ "''${created[$id]}" -lt "$cutoff" ] || continue
      skip=""
      for ref in ''${refs[$id]}; do [ -n "''${keep[$ref]:-}" ] && skip="$ref: ''${keep[$ref]}"; done
      if [ -n "$skip" ]; then echo "keep    $skip"; continue; fi
      age=$(( (now - ''${created[$id]}) / 86400 ))
      for ref in ''${refs[$id]}; do
        if $dry; then
          echo "would remove  $ref  $(human "''${size[$id]}")  ''${age}d"
        elif docker image rm "$ref" >/dev/null; then
          echo "removed  $ref  $(human "''${size[$id]}")  ''${age}d"
          removed=$((removed + 1))
        else
          failed=$((failed + 1))
        fi
      done
      listed=$((listed + ''${size[$id]}))
    done

    if $dry; then
      echo "dry run: $(human "$listed") of tagged images older than ''${days}d would go;" \
        "dangling images and build cache older than ''${cache_days}d are pruned too on a real run"
      exit 0
    fi

    docker image prune -f >/dev/null
    docker builder prune -f --filter "until=$((cache_days * 24))h" >/dev/null
    after=$(used)
    echo "freed $(human $(( before > after ? before - after : 0 ))): $removed tagged refs removed, $failed refused;" \
      "images+build cache $(human "$before") -> $(human "$after")"
    [ "$failed" -eq 0 ]
  '';
}

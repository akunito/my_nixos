#!/usr/bin/env bash
# Build our own Plane images from the fork (APLANE-15). Usage: build_images.sh [ref]
# Prints the short sha it built as the last line; images are tagged with it.
#
# Upstream's AIO Dockerfile does not build from source — it FROMs the six published
# makeplane/plane-* images and copies their artifacts into one runner. So we build those six
# ourselves and assemble the AIO on top, pointing PLANE_IMAGE_PREFIX at our tags.
#
# Not using deployments/cli/community/build.yml: its build contexts resolve one directory
# short (deployments/apps/api), so the contexts are spelled out here.
source "$(dirname "$0")/common.sh"

ref=${1:-akunito/mobile-v1.4.1}
repo=$HOME/.cache/plane-build/plane-up
prefix=plane-aku/plane
aio_image=plane-aku/aio-community

mkdir -p "$(dirname "$repo")"
[ -d "$repo/.git" ] || git clone -q https://github.com/akunito/plane-up.git "$repo"
git -C "$repo" fetch -q origin "+refs/heads/*:refs/remotes/origin/*"
git -C "$repo" checkout -q --force "$(git -C "$repo" rev-parse --verify -q "origin/$ref^{commit}" \
  || git -C "$repo" rev-parse --verify "$ref^{commit}")"
sha=$(git -C "$repo" rev-parse --short HEAD)
log "building images from $(git -C "$repo" log --oneline -1)"

cd "$repo"
build() { # service dockerfile context
  log "  image $1"
  docker build -q -t "$prefix-$1:$sha" -f "$2" "$3" >/dev/null || die "building $1 failed"
}
build backend  apps/api/Dockerfile.api      apps/api
build proxy    apps/proxy/Dockerfile.ce     apps/proxy
build live     apps/live/Dockerfile.live    .
build space    apps/space/Dockerfile.space  .
build admin    apps/admin/Dockerfile.admin  .
build frontend apps/web/Dockerfile.web      .

# build.sh only prepares dist/ (plane.env + the Caddyfile) and prints the command
cd deployments/aio/community
./build.sh --release="$sha" --image-name="$aio_image" >/dev/null || die "aio build.sh failed"
log "  assembling $aio_image:$sha"
docker build -q -t "$aio_image:$sha" -f Dockerfile \
  --build-arg "PLANE_VERSION=$sha" --build-arg "PLANE_IMAGE_PREFIX=$prefix" . >/dev/null \
  || die "assembling the aio image failed"

log "built $aio_image:$sha"
printf '%s\n' "$sha"

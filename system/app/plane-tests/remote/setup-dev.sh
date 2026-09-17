#!/usr/bin/env bash
# One-off (idempotent): add the mailpit sink to the dev stack and point the dev
# app's email env at it (APLANE-8). The instance_configurations rows — which
# are what Plane actually uses — are set by sanitize.sql on every refresh.
source "$(dirname "$0")/common.sh"

compose=$DEV_DIR/docker-compose.yml
[ -f "$compose" ] || die "$compose not found"

if grep -q "container_name: $DEV_MAILPIT" "$compose"; then
  log "mailpit already in $compose"
else
  cp -p "$compose" "$compose.bak-mailpit-$(date +%Y%m%d%H%M%S)"
  python3 - "$compose" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

service = """  plane-dev-mailpit:
    # Email sink (APLANE-8): every mail dev sends lands here, nothing is relayed.
    # UI on the VPS loopback: ssh -L 8025:127.0.0.1:8025 -p 56777 akunito@100.64.0.6
    container_name: plane-dev-mailpit
    image: axllent/mailpit:v1.31.1
    restart: unless-stopped
    security_opt: [no-new-privileges:true]
    ports:
      - "127.0.0.1:8025:8025"
    environment:
      MP_MAX_MESSAGES: "5000"
      MP_SMTP_AUTH_ACCEPT_ANY: "1"
      MP_SMTP_AUTH_ALLOW_INSECURE: "1"
    deploy:
      resources:
        limits:
          memory: 128M

  plane-dev-aio:
"""
anchor = "  plane-dev-aio:\n"
assert s.count(anchor) == 1, "plane-dev-aio anchor"
s = s.replace(anchor, service, 1)

for old, new in [
    ('      EMAIL_HOST: host.docker.internal\n', '      EMAIL_HOST: plane-dev-mailpit\n'),
    ('      EMAIL_PORT: "25"\n', '      EMAIL_PORT: "1025"\n'),
]:
    assert s.count(old) == 1, old
    s = s.replace(old, new, 1)

dep = "      plane-dev-minio: { condition: service_healthy }\n"
assert s.count(dep) == 1, "depends_on anchor"
s = s.replace(dep, dep + "      plane-dev-mailpit: { condition: service_started }\n", 1)
open(p, "w").write(s)
PY
  log "mailpit added to $compose (backup kept next to it)"
fi

cd "$DEV_DIR"
docker compose config -q || die "compose file invalid"
docker compose up -d plane-dev-mailpit
running "$DEV_MAILPIT" || die "$DEV_MAILPIT not running"
log "mailpit up; the dev app picks up the new env on the next refresh (it recreates $DEV_AIO)"

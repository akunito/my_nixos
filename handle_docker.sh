#!/bin/sh

SILENT_MODE=${1:-false}

# Fast-path: if docker isn't available, do nothing
command -v docker >/dev/null 2>&1 || exit 0

# Fast-path: if daemon isn't active, do nothing
systemctl is-active --quiet docker 2>/dev/null || exit 0

# Fast-path: no running containers => do nothing (no prompt, no noise)
RUNNING_CONTAINERS="$(docker ps -q 2>/dev/null || true)"
if [ -z "$RUNNING_CONTAINERS" ]; then
  exit 0
fi

echo ""
echo "Running Docker containers detected:"
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

if [ "$SILENT_MODE" = false ]; then
  echo ""
  printf "Stop running containers now? (Y/n) "
  read yn
else
  yn="y"
fi

case "$yn" in
  [Nn]*)
    echo "Aborting (containers left running)."
    exit 1
    ;;
  *)
    echo ""
    echo "Stopping running containers..."
    # shellcheck disable=SC2086
    docker stop $RUNNING_CONTAINERS
    echo "Containers stopped."
    ;;
esac

exit 0

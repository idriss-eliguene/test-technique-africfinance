#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 IMAGE CONTAINER_NAME APP_PORT APP_ENV" >&2
  exit 2
fi

IMAGE=$1
CONTAINER_NAME=$2
APP_PORT=$3
APP_ENV=$4

IFS= read -r GHCR_USERNAME
IFS= read -r GHCR_TOKEN

if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
fi

docker pull "$IMAGE"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  docker rm -f "$CONTAINER_NAME"
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "$APP_PORT:$APP_PORT" \
  -e APP_ENV="$APP_ENV" \
  "$IMAGE"

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  echo "Healthcheck HTTP — tentative $attempt/10"
  if curl -fsS "http://127.0.0.1:$APP_PORT/" >/dev/null; then
    exit 0
  fi
  sleep 3
done

docker ps
docker logs --tail 100 "$CONTAINER_NAME"
exit 1

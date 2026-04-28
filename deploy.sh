#!/usr/bin/env bash
# Pull latest images, restart services, prune dangling images.
# Run from spreadis-deploy/ on VPS: ./deploy.sh
set -euo pipefail

echo "→ Pulling latest images from ghcr.io..."
docker compose pull

echo "→ Restarting services..."
docker compose up -d --remove-orphans

# Caddy mounts Caddyfile as a volume — `up -d` won't restart it on file edits.
# Tried `caddy reload` (zero-downtime hot-reload) but it silently fails to apply
# changes when invoked via `docker exec`; full restart is the reliable path.
# ~2s of downtime for in-flight HTTP requests; WS clients auto-reconnect.
if docker ps --format '{{.Names}}' | grep -q '^spreadis-caddy$'; then
  echo "→ Restarting Caddy to pick up Caddyfile changes..."
  docker compose restart caddy
fi

echo "→ Pruning dangling images..."
docker image prune -f

echo "→ Status:"
docker compose ps
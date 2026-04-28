#!/usr/bin/env bash
# Pull latest images, restart services, prune dangling images.
# Run from spreadis-deploy/ on VPS: ./deploy.sh
set -euo pipefail

echo "→ Pulling latest images from ghcr.io..."
docker compose pull

echo "→ Restarting services..."
docker compose up -d --remove-orphans

# Caddy mounts Caddyfile as a volume — `up -d` won't restart it on file edits.
# Hot-reload picks up Caddyfile changes without dropping in-flight requests.
echo "→ Reloading Caddy config..."
if docker ps --format '{{.Names}}' | grep -q '^spreadis-caddy$'; then
  docker exec spreadis-caddy caddy reload --config /etc/caddy/Caddyfile 2>&1 || \
    echo "  (caddy reload skipped — container not ready yet)"
fi

echo "→ Pruning dangling images..."
docker image prune -f

echo "→ Status:"
docker compose ps
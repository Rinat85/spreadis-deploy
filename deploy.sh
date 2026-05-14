#!/usr/bin/env bash
# Pull latest images, restart services, run DB migrations, prune dangling images.
# Run from spreadis-deploy/ on VPS: ./deploy.sh
set -euo pipefail

echo "→ Pulling latest images from ghcr.io..."
docker compose pull

echo "→ Restarting services..."
docker compose up -d --remove-orphans

# Wait for PostgreSQL to be healthy before running migrations
echo "→ Waiting for spreadis-db to be healthy..."
timeout=30
while ! docker compose exec -T spreadis-db pg_isready -U spreadis -q 2>/dev/null; do
  timeout=$((timeout - 1))
  if [ "$timeout" -le 0 ]; then
    echo "  ✗ spreadis-db did not become healthy in time"
    break
  fi
  sleep 1
done

# Run Prisma migrations inside the backend container
echo "→ Running Prisma migrations..."
docker compose exec -T backend npx prisma migrate deploy 2>&1 || {
  echo "  ⚠ Prisma migrate failed — DB may need manual intervention"
}

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
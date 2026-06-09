#!/usr/bin/env bash
# Pull latest images, restart services, run DB migrations, prune dangling images.
# Run from spreadis-deploy/ on VPS: ./deploy.sh
set -euo pipefail

# Serialize concurrent deploys. The frontend and backend repos each trigger
# their own Deploy workflow; pushing to both around the same time runs two
# SSH sessions that both `git reset --hard` + `docker compose pull` on the
# same daemon and the same checkout dir at once. That race is what made one
# of a parallel pair fail with "error from registry: denied" (concurrent
# GHCR pulls getting throttled / interrupted) while a manual re-run passed.
# flock makes the second invocation wait for the first to finish (up to 5m).
exec 9>/tmp/spreadis-deploy.lock
echo "→ Acquiring deploy lock..."
if ! flock -w 300 9; then
  echo "  ✗ another deploy held the lock for >5m — aborting"
  exit 1
fi

echo "→ Pulling latest images from ghcr.io..."
# --ignore-pull-failures: one image that can't be pulled (a private package
# the VPS isn't authed for — e.g. spreadis-admin — or a transient registry
# hiccup) must not abort the whole deploy. Services that pulled fine still
# get restarted below; the failed one keeps its current running image.
docker compose pull --ignore-pull-failures

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
docker image prune -f 2>/dev/null || true

echo "→ Status:"
docker compose ps
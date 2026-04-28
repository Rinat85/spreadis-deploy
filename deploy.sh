#!/usr/bin/env bash
# Pull latest images, restart services, prune dangling images.
# Run from spreadis-deploy/ on VPS: ./deploy.sh
set -euo pipefail

echo "→ Pulling latest images from ghcr.io..."
docker compose pull

echo "→ Restarting services..."
docker compose up -d --remove-orphans

echo "→ Pruning dangling images..."
docker image prune -f

echo "→ Status:"
docker compose ps
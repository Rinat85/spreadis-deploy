# spreadis-deploy

Deploy artifacts for Spreadis (frontend + backend) on a single VPS.

## Architecture

```
                 Internet
                    │
              :80 / :443
                    │
              ┌─────────────┐
              │    Caddy    │  auto Let's Encrypt SSL
              └──────┬──────┘
        ┌────────────┴────────────┐
        ▼                         ▼
  spreadis.live             api.spreadis.live
   (frontend:3000)            (backend:3001)
   Nuxt 4 / Nitro            NestJS / Socket.IO
```

All three containers (caddy, frontend, backend) live on the `spreadis` Docker network.

## First-time deploy (on VPS)

1. **Install Docker** (Ubuntu 24.04):
   ```bash
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER
   newgrp docker
   ```

2. **Clone this repo:**
   ```bash
   git clone git@github.com:Rinat85/spreadis-deploy.git
   cd spreadis-deploy
   ```

3. **Make sure DNS A-records exist** (Namecheap or Cloudflare):
   - `spreadis.live` → VPS IP
   - `api.spreadis.live` → VPS IP
   - `www.spreadis.live` → VPS IP (optional, redirected to apex)

4. **Pull images and start:**
   ```bash
   ./deploy.sh
   ```

   Caddy will auto-fetch Let's Encrypt certs on first boot. Open
   `https://spreadis.live` to verify.

## Updating after a code change

On your local machine, after pushing to `spreadis-backend` or `spreadis-frontend`:

```bash
# Build + push image (locally — VPS lacks RAM for Nuxt build)
cd spreadis-frontend
docker build -t ghcr.io/rinat85/spreadis-frontend:latest .
docker push ghcr.io/rinat85/spreadis-frontend:latest
```

Then on VPS:
```bash
cd spreadis-deploy
./deploy.sh
```

## Local-only smoke test

Run the whole stack on your dev machine without a domain:

```bash
docker compose -f docker-compose.local.yml up
# frontend at http://localhost:3000, backend at http://localhost:3001
```

(Create `docker-compose.local.yml` later when needed.)

## Logs

```bash
docker compose logs -f               # all services
docker compose logs -f backend       # one service
docker compose logs --tail=100 caddy # last 100 lines
```

## Troubleshooting

- **Caddy can't get cert**: DNS not propagated yet or A-record wrong. Check
  `dig +short spreadis.live` from VPS — must return VPS public IP.
- **`pull access denied for ghcr.io/...`**: GHCR package is private. Either
  make it public on github.com, or `docker login ghcr.io` with a PAT.
- **Out of memory**: 2 GB VPS — make sure swap is on (`free -h`), and
  consider `mem_limit` in compose.
#!/usr/bin/env bash
# Despliega RecetaRápida en el homelab desde el Mac: copia el compose a
# ~/stacks/recetarapida, crea .env con secretos aleatorios la primera vez y
# reconstruye los contenedores. Se puede repetir sin perder datos.
#
# Uso: scripts/deploy.sh [host-ssh]     (por defecto: homelab)
set -euo pipefail

HOST="${1:-homelab}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Copiando archivos a ${HOST}:~/stacks/recetarapida"
# El shell del homelab es fish: los scripts remotos se pasan a bash por stdin.
ssh "$HOST" bash -s <<'EOF'
mkdir -p ~/stacks/recetarapida/docker/postgres
EOF
tar -C "$ROOT" -cf - docker-compose.yml .env.example docker | ssh "$HOST" 'tar -C ~/stacks/recetarapida -xf -'

echo "==> Preparando .env y levantando contenedores"
ssh "$HOST" bash -s <<'EOF'
set -euo pipefail
cd ~/stacks/recetarapida
chmod +x docker/postgres/10-init-databases.sh
if [ ! -f .env ]; then
  umask 077
  {
    echo "PUBLIC_HOST=recetarapida.ansayan.com"
    echo "POSTGRES_ADMIN_USER=postgres"
    echo "POSTGRES_ADMIN_PASSWORD=$(openssl rand -hex 24)"
    echo "AUTH_DB_PASSWORD=$(openssl rand -hex 24)"
    echo "PRESCRIPTIONS_DB_PASSWORD=$(openssl rand -hex 24)"
    echo "JWT_SECRET=$(openssl rand -hex 48)"
    echo "JWT_EXPIRATION=86400000"
    echo "REF_AUTH=main"
    echo "REF_PRESCRIPTION=main"
    echo "REF_GATEWAY=main"
  } > .env
  echo ".env creado (permisos 600)"
fi
docker compose config -q
docker compose up -d --build
docker compose ps
EOF

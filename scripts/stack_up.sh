#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/stack_up.sh'; exit 0; }
need docker; need openssl; need curl; need sed; [[ -f .env ]] || ensure_env
port="$(api_port)"
docker info >/dev/null 2>&1 || die 'Inicie Docker Desktop y habilite el motor Linux/WSL2.'
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" up -d --build --scale api=1
log 'Esperando salud HTTP (hasta cuatro minutos).'
for i in $(seq 1 120); do if curl -fsS "http://127.0.0.1:${port}/health/ready" >/dev/null 2>&1; then break; fi; sleep 2; done
curl -fsS "http://127.0.0.1:${port}/health/ready" || { "${COMPOSE[@]}" ps; "${COMPOSE[@]}" logs --no-color --tail=80 api db-setup; die 'API no quedó lista con MySQL y Redis; revise los logs.'; }
"${COMPOSE[@]}" ps

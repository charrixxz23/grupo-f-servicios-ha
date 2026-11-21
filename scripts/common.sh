#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
mkdir -p results/logs
LOG_PATH="results/logs/$(basename -- "${BASH_SOURCE[1]:-run}" .sh)_$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$LOG_PATH") 2>&1
COMPOSE=(docker compose --project-name semestral-ha --env-file .env -f docker-compose.yml)
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Falta dependencia: $1"; }
api_port() {
  local port="${API_PORT:-}"
  if [[ -z "$port" && -f .env ]]; then port="$(sed -n 's/^API_PORT=//p' .env | head -n1)"; fi
  printf '%s\n' "${port:-8082}"
}
ensure_env() {
  if [[ ! -f .env ]]; then
    umask 077; cp .env.example .env
    for key in MYSQL_ROOT_PASSWORD MYSQL_APP_PASSWORD REDIS_PASSWORD; do
      value="$(openssl rand -hex 24)"; sed -i "s/^${key}=.*/${key}=${value}/" .env
    done
    chmod 600 .env; log 'Creado .env con secretos aleatorios; no se imprime ningún secreto.'
  fi
}

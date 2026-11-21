#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/collect_evidence.sh'; exit 0; }
stamp="$(date +%Y%m%dT%H%M%S)"; dest="evidence/bundles/$stamp"; mkdir -p "$dest"
"${COMPOSE[@]}" ps >"$dest/compose-ps.txt" 2>&1 || true
if [[ -f .env ]]; then
  config="$("${COMPOSE[@]}" config)"
  while IFS='=' read -r key value; do
    [[ "$key" == *PASSWORD* && -n "$value" ]] || continue
    config="${config//"$value"/[REDACTED]}"
  done < .env
  printf '%s\n' "$config" >"$dest/compose-config-redacted.yml"
fi
for service in api lb assets redis-primary redis-replica1 redis-replica2 sentinel1 sentinel2 sentinel3 mysql1 mysql2 mysql3 db-setup; do "${COMPOSE[@]}" logs --no-color --tail=500 "$service" >"$dest/${service}.log" 2>&1 || true; done
cp -f results/*.csv results/*.json "$dest/" 2>/dev/null || true
cp -f results/raw/*.csv results/raw/*.json "$dest/" 2>/dev/null || true
cp -f results/logs/*.log "$dest/" 2>/dev/null || true
for f in .env; do [[ ! -f "$f" ]] || echo 'Secret file omitted by design.'; done
echo "Evidencias recopiladas en $dest (sin copiar .env). Revise manualmente secretos en logs antes de compartir."

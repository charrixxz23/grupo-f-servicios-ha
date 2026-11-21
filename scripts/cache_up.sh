#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/cache_up.sh'; exit 0; }
[[ -f .env ]] || die 'Ejecute scripts/stack_up.sh primero.'
"${COMPOSE[@]}" up -d redis-primary redis-replica1 redis-replica2 sentinel1 sentinel2 sentinel3
quorum_ok=0
for i in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli -p 26379 -a "$REDIS_PASSWORD" SENTINEL ckquorum ha-cache 2>/dev/null | grep -q OK' >/dev/null 2>&1; then quorum_ok=1; break; fi
  sleep 2
done
[[ "$quorum_ok" == 1 ]] || die 'Sentinel no obtuvo quórum dentro de 120 segundos.'
master_ip="$("${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli --raw -p 26379 -a "$REDIS_PASSWORD" SENTINEL get-master-addr-by-name ha-cache 2>/dev/null | head -n1')"
master_service=''
for service in redis-primary redis-replica1 redis-replica2; do
  id="$("${COMPOSE[@]}" ps -q "$service" | head -n1)"
  ips="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$id")"
  [[ " $ips " == *" $master_ip "* ]] && { master_service="$service"; break; }
done
[[ -n "$master_service" ]] || die "No se pudo mapear el master Sentinel $master_ip a un servicio Redis."
"${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli -p 26379 -a "$REDIS_PASSWORD" SENTINEL master ha-cache | sed -E "/password/d"'
replication="$("${COMPOSE[@]}" exec -T "$master_service" sh -ec 'redis-cli -a "$REDIS_PASSWORD" INFO replication | grep -E "^(role|connected_slaves):"')"
printf 'servicio_master=%s\n%s\n' "$master_service" "$replication"
[[ "$replication" == *'role:master'* ]] || die 'Sentinel master no reporta role:master.'
[[ "$replication" == *'connected_slaves:2'* ]] || die 'El master Redis no tiene sus dos réplicas conectadas.'

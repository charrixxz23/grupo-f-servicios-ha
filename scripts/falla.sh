#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/falla.sh app|redis|mysql'; exit 0; }
scenario="${1:-}"; [[ "$scenario" =~ ^(app|redis|mysql)$ ]] || die 'Use app, redis o mysql.'
[[ -f .env ]] || die 'Falta .env; ejecute stack_up.sh.'
mkdir -p results; run="$(date +%Y%m%dT%H%M%S)_${scenario}"; csv="results/failover_${run}.csv"; logf="results/failover_${run}.log"
url="http://127.0.0.1:$(api_port)"; echo 'timestamp,status,latency_ms,replica' > "$csv"
paused_redis=''
restore() { if [[ -n "$paused_redis" ]]; then docker unpause "$paused_redis" >/dev/null 2>&1 || true; paused_redis=''; fi; "${COMPOSE[@]}" up -d --scale api=3 api mysql1 mysql2 mysql3 redis-primary redis-replica1 redis-replica2 sentinel1 sentinel2 sentinel3 >/dev/null 2>&1 || true; }
cleanup() { local status=$?; trap - EXIT INT TERM; if [[ -n "${monitor:-}" ]]; then kill "$monitor" 2>/dev/null || true; wait "$monitor" 2>/dev/null || true; fi; restore; exit "$status"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"${COMPOSE[@]}" up -d --scale api=3 api lb mysql1 mysql2 mysql3 db-setup redis-primary redis-replica1 redis-replica2 sentinel1 sentinel2 sentinel3
for i in $(seq 1 90); do curl -fsS "$url/health" >/dev/null 2>&1 && break; sleep 2; done
before="$(curl -fsS "$url/api/status")"; printf 'before=%s\n' "$before" | tee "$logf"
cache_key="failover-${run}"
if [[ "$scenario" == redis ]]; then
  curl -fsS -X PUT -H 'content-type: application/json' -d "{\"key\":\"${cache_key}\",\"value\":\"survives-redis-primary-failure\"}" "$url/api/cache" >>"$logf"
  echo >>"$logf"
fi
(
  idx=0
  while :; do
    idx=$((idx+1)); start="$(date +%s%N)"; resp="$(curl -sS --max-time 4 -w $'\n%{http_code}' -H 'content-type: application/json' -d "{\"id\":\"${run}-${idx}\",\"value\":\"continuous-ha-probe\"}" "$url/api/records" 2>/dev/null || true)"; status="${resp##*$'\n'}"; body="${resp%$'\n'*}"; finish="$(date +%s%N)"; ms=$(( (finish-start)/1000000 )); replica="$(printf '%s' "$body" | sed -n 's/.*"replica":"\([^"]*\)".*/\1/p')"; printf '%s,%s,%s,%s\n' "$(date -Is)" "$status" "$ms" "$replica" >> "$csv"; sleep 0.15
  done
) & monitor=$!
sleep 3; failure_start="$(date +%s%3N)"
case "$scenario" in
  app) victim="$("${COMPOSE[@]}" ps -q api | head -n1)"; [[ -n "$victim" ]] || die 'No se encontró réplica API.'; echo "stopping_api=$victim" >> "$logf"; docker stop "$victim" >/dev/null; recovered=0; for i in $(seq 1 40); do if curl -fsS "$url/health" >/dev/null 2>&1; then recovered=1; break; fi; sleep 0.25; done; docker start "$victim" >/dev/null; [[ "$recovered" == 1 ]] || die 'El balanceador no atendió salud desde una réplica superviviente.' ;;
  redis)
    sentinel_master() { "${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli --raw -p 26379 -a "$REDIS_PASSWORD" SENTINEL get-master-addr-by-name ha-cache 2>/dev/null | head -n1'; }
    sentinel_flags() { "${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli --raw -p 26379 -a "$REDIS_PASSWORD" SENTINEL master ha-cache 2>/dev/null | grep -A1 "^flags$" | tail -1'; }
    old_master_ip="$(sentinel_master)"; victim=''
    for service in redis-primary redis-replica1 redis-replica2; do
      id="$("${COMPOSE[@]}" ps -q "$service" | head -n1)"
      ips="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$id")"
      [[ " $ips " == *" $old_master_ip "* ]] && { victim="$service"; break; }
    done
    [[ -n "$victim" ]] || die "No se pudo mapear el primario Sentinel $old_master_ip a un servicio Redis."
    echo "sentinel_master_before=$old_master_ip pausing_redis=$victim" >>"$logf"
    paused_redis="$("${COMPOSE[@]}" ps -q "$victim" | head -n1)"
    [[ -n "$paused_redis" ]] || die "No se encontró contenedor Redis para $victim."
    docker pause "$paused_redis" >>"$logf"; promoted=0; role=''; new_master_ip=''
    for i in $(seq 1 120); do
      new_master_ip="$(sentinel_master)"; role="$(sentinel_flags)"
      if [[ -n "$new_master_ip" && "$new_master_ip" != "$old_master_ip" && "$role" == *master* && "$role" != *disconnected* && "$role" != *s_down* && "$role" != *o_down* ]]; then promoted=1; break; fi
      sleep 1
    done
    echo "sentinel_promoted=$promoted new_master_ip=${new_master_ip:-unknown} role=${role:-unknown}" >>"$logf"
    new_master_service=''
    for service in redis-primary redis-replica1 redis-replica2; do
      id="$("${COMPOSE[@]}" ps -q "$service" | head -n1)"
      ips="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$id")"
      [[ " $ips " == *" $new_master_ip "* ]] && { new_master_service="$service"; break; }
    done
    [[ -n "$new_master_service" ]] || die "No se pudo mapear el nuevo master Sentinel $new_master_ip a un servicio Redis."
    cache_after=''; for i in $(seq 1 20); do cache_after="$("${COMPOSE[@]}" exec -T "$new_master_service" sh -ec "redis-cli --raw -a \"\$REDIS_PASSWORD\" GET '$cache_key'" 2>/dev/null || true)"; [[ "$cache_after" == 'survives-redis-primary-failure' ]] && break; sleep 1; done
    preserved=0; [[ "$cache_after" == *'survives-redis-primary-failure'* ]] && preserved=1
    echo "cache_after_promotion=$cache_after cache_value_preserved=$([[ "$preserved" == 1 ]] && echo true || echo false) cache_verified_on=$new_master_service" >>"$logf"
    [[ "$promoted" == 1 && "$preserved" == 1 ]] || die 'Redis no completó promoción con conservación del valor.'
    docker unpause "$paused_redis" >>"$logf"; paused_redis='' ;;
  mysql) primary="$(curl -fsS "$url/api/status" | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p' | head -n1)"; [[ "$primary" =~ ^mysql[123]$ ]] || die "No se pudo identificar el primario MySQL (respuesta: $primary)."; echo "stopping_mysql=$primary" >> "$logf"; "${COMPOSE[@]}" stop "$primary" >>"$logf"; recovered=0; for i in $(seq 1 60); do code="$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' -H 'content-type: application/json' -d "{\"id\":\"${run}-recovery\",\"value\":\"write-after-election\"}" "$url/api/records" 2>/dev/null || true)"; if [[ "$code" == 201 ]]; then recovered=1; break; fi; sleep 1; done; echo "mysql_write_recovered=$recovered" >>"$logf"; [[ "$recovered" == 1 ]] || die 'MySQL no recuperó escrituras dentro de 60 segundos.'; "${COMPOSE[@]}" up -d "$primary" >/dev/null ;;
esac
failure_end="$(date +%s%3N)"; echo "recovered_at_ms=$failure_end estimated_mttr_ms=$((failure_end-failure_start))" | tee -a "$logf"
kill "$monitor" 2>/dev/null || true; wait "$monitor" 2>/dev/null || true
awk -F, 'NR>1{n++; if($2==200 || $2==201)ok++; else err++} END{printf "samples=%d success=%d errors=%d\n",n,ok,err}' "$csv" | tee -a "$logf"
if [[ "$scenario" == mysql ]]; then
  confirmed="$(awk -F, 'NR>1 && $2==201{n++} END{print n+0}' "$csv")"
  primary_after=""
  for i in $(seq 1 60); do
    primary_after="$(curl -fsS "$url/api/status" 2>/dev/null | sed -n 's/.*"hostname":"\(mysql[123]\)".*/\1/p' | head -n1)"
    [[ "$primary_after" =~ ^mysql[123]$ ]] && break
    sleep 1
  done
  [[ "$primary_after" =~ ^mysql[123]$ ]] || die 'No se pudo identificar el primario MySQL después de la elección.'
  stored=""
  for i in $(seq 1 60); do
    stored="$("${COMPOSE[@]}" exec -T "$primary_after" sh -ec "mysqladmin ping -uroot -p\"\$MYSQL_ROOT_PASSWORD\" --silent >/dev/null && mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -Nse \"SELECT COUNT(*) FROM ha_lab.records WHERE id LIKE '${run}-%' AND id <> '${run}-recovery'\"" 2>/dev/null || true)"
    [[ "$stored" =~ ^[0-9]+$ ]] && break
    sleep 1
  done
  [[ "$stored" =~ ^[0-9]+$ ]] || die "No se pudo consultar la integridad en $primary_after."
  echo "primary_after=$primary_after confirmed_writes=$confirmed persisted_records=$stored integrity_match=$([[ "$stored" -eq "$confirmed" ]] && echo true || echo false)" | tee -a "$logf"
  [[ "$stored" -eq "$confirmed" ]] || die "Integridad MySQL no coincide: confirmadas=$confirmed persistidas=$stored."
fi
echo 'restoration_requested=true' | tee -a "$logf"

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/process_audit.sh [servicio=api]'; exit 0; }
service="${1:-api}"; id="$("${COMPOSE[@]}" ps -q "$service" | head -n1)"; [[ -n "$id" ]] || die "No hay contenedor activo: $service"
docker exec "$id" sh -ec 'echo "Servicio: $(cat /proc/1/comm), PID 1"; ps -ef 2>/dev/null || true; echo "tasks PID 1:"; ls /proc/1/task 2>/dev/null || true; echo "hilos PID 1: $(ls /proc/1/task 2>/dev/null | wc -l)"; echo "procesos/hilos disponibles:"; cat /proc/1/status | grep -E "^(Name|Pid|PPid|Threads):"'
if docker exec "$id" sh -c 'ps -L -p 1 >/dev/null 2>&1'; then
  docker exec "$id" sh -ec 'ps -L -p 1; top -H -b -n 1 -p 1 | head -20; ps -eLf | head -30'
else
  echo 'Esta imagen no incluye procps; use ls /proc/1/task y la lista docker top de abajo.'
fi
docker top "$id" -eo pid,ppid,comm,args

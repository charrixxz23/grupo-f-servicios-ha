#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/kernel_audit.sh [servicio=api]'; exit 0; }
service="${1:-api}"; id="$("${COMPOSE[@]}" ps -q "$service" | head -n1)"; [[ -n "$id" ]] || die "No hay contenedor activo: $service"
docker exec "$id" sh -ec 'echo "pid1=$(cat /proc/1/comm)"; for f in cpu.max memory.max memory.high memory.current pids.max pids.current cpu.stat memory.events memory.pressure; do printf "%s\n" "--- $f ---"; cat "/sys/fs/cgroup/$f" 2>/dev/null || echo unavailable; done; printf "oom_score_adj="; cat /proc/1/oom_score_adj 2>/dev/null || true; printf "\nthreads="; ls /proc/1/task 2>/dev/null | wc -l'
echo 'Host-side container configuration (Docker resource limits):'
docker inspect --format 'Name={{.Name}} NanoCpus={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}} MemoryReservation={{.HostConfig.MemoryReservation}} PidsLimit={{.HostConfig.PidsLimit}} OOMScoreAdj={{.HostConfig.OomScoreAdj}}' "$id"

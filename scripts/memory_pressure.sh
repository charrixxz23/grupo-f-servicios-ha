#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/memory_pressure.sh high|oom'; exit 0; }
mode="${1:-}"; [[ "$mode" =~ ^(high|oom)$ ]] || die 'Use high u oom.'
case "$mode" in
  high)
    [[ -f .env ]] || die 'Ejecute stack_up.sh primero.'
    name="semestral-ha-pressure-$(date +%s)"; stamp="$(date +%Y%m%dT%H%M%S)"; out="results/pressure_high_${stamp}.csv"; mkdir -p results/raw
    echo 'timestamp,health_latency_s,memory_high,memory_current,memory_pressure,memory_events' >"$out"
    echo 'Presión aislada: contenedor descartable 128 MiB max / 48 MiB high (reservation). Se ejecuta carga API concurrente de 20 s.'
    docker run -d --network none --name "$name" --memory 128m --memory-swap 128m --memory-reservation 48m --cpus 0.5 --pids-limit 32 polinux/stress-ng:latest --vm 1 --vm-bytes 72M --vm-keep --timeout 20s --metrics-brief >/dev/null
    high_limit="$(docker exec "$name" cat /sys/fs/cgroup/memory.high 2>/dev/null || echo unavailable)"
    echo "memory.high efectivo en contenedor descartable: $high_limit (reserva Docker: 48 MiB)."
    DURATION=20s CONCURRENCY=25 REPLICAS=3 RESULT_NAME="pressure_high_${stamp}" "${COMPOSE[@]}" --profile tools run --rm -e DURATION -e CONCURRENCY -e REPLICAS -e RESULT_NAME loadgen node /work/load.mjs & loader=$!
    while kill -0 "$loader" 2>/dev/null; do
      psi="$(docker exec "$name" sh -ec 'tr "\\n" ";" </sys/fs/cgroup/memory.pressure 2>/dev/null || echo unavailable' 2>/dev/null || echo finished)"
      events="$(docker exec "$name" sh -ec 'tr "\\n" ";" </sys/fs/cgroup/memory.events 2>/dev/null || echo unavailable' 2>/dev/null || echo finished)"
      current="$(docker exec "$name" cat /sys/fs/cgroup/memory.current 2>/dev/null || echo finished)"
      latency="$(curl -sS -o /dev/null -w '%{time_total}' --max-time 3 "http://127.0.0.1:$(api_port)/health" 2>/dev/null || echo timeout)"
      printf '%s,%s,%s,%s,"%s","%s"\n' "$(date -Is)" "$latency" "$high_limit" "$current" "$psi" "$events" >>"$out"; sleep 1
    done
    wait "$loader"; docker logs "$name" 2>&1 | tail -30; docker rm -f "$name" >/dev/null 2>&1 || true
    echo "presión y latencia registradas en $out; p99 de carga en results/raw/pressure_high_${stamp}.json" ;;
  oom)
    name="semestral-ha-oom-$(date +%s)"; mkdir -p results; out="results/oom_${name}.log"; echo 'OOM aislado en contenedor desechable de 96 MiB (nunca la BD).'
    docker run -d --network none --name "$name" --memory 96m --memory-swap 96m --pids-limit 32 polinux/stress-ng:latest --vm 1 --vm-bytes 256M --vm-keep --timeout 15s --metrics-brief >/dev/null
    while [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)" == true ]]; do
      docker exec "$name" sh -ec 'cat /sys/fs/cgroup/memory.events' >>"$out" 2>/dev/null || true; sleep 0.5
    done
    docker inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' "$name" | tee -a "$out"
    docker logs "$name" 2>&1 | tail -50 | tee -a "$out"; docker rm "$name" >/dev/null
    if dmesg -T >/dev/null 2>&1; then dmesg -T | tail -30 >>"$out"; else echo 'dmesg unavailable from WSL/Docker Desktop terminal' >>"$out"; fi
    echo "Evidencia guardada en $out" ;;
esac

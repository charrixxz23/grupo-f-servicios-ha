#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/load.sh [1|2|3] [repeticiones=3] [duración=30s] [concurrencia=25]'; exit 0; }
n="${1:-3}"; reps="${2:-3}"; duration="${3:-30s}"; concurrency="${4:-25}"
[[ "$n" =~ ^[123]$ && "$reps" =~ ^[1-9][0-9]*$ ]] || die 'Parámetros inválidos.'
need python3
"${COMPOSE[@]}" up -d --scale "api=$n" api lb
loader=''; sampler=''
cleanup() { local status=$?; trap - EXIT INT TERM; [[ -z "$sampler" ]] || { kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true; }; [[ -z "$loader" ]] || { kill "$loader" 2>/dev/null || true; wait "$loader" 2>/dev/null || true; }; exit "$status"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p results/raw
for rep in $(seq 1 "$reps"); do
  name="scale${n}_rep${rep}_$(date +%Y%m%dT%H%M%S)"
  log "Carga $rep/$reps; $n réplicas; $duration; concurrencia $concurrency."
  resources="results/raw/${name}_resources.csv"; echo 'timestamp,container,cpu_percent,memory_usage,pids,processes,threads_pid1' >"$resources"
  DURATION="$duration" CONCURRENCY="$concurrency" REPLICAS="$n" RESULT_NAME="$name" "${COMPOSE[@]}" --profile tools run --rm -e DURATION -e CONCURRENCY -e REPLICAS -e RESULT_NAME loadgen node /work/load.mjs >"results/logs/${name}.log" 2>&1 & loader=$!
  (
    while kill -0 "$loader" 2>/dev/null; do
      while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        stats="$(docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.PIDs}}' "$id" 2>/dev/null || true)"
        [[ -n "$stats" ]] || continue
        tasks="$(docker exec "$id" sh -ec 'printf "%s," "$(find /proc -maxdepth 1 -type d -name "[0-9]*" | wc -l)"; ls /proc/1/task 2>/dev/null | wc -l' 2>/dev/null | tr -d '\n' || true)"
        printf '%s,%s,%s\n' "$(date -Is)" "$stats" "$tasks" >>"$resources"
      done < <("${COMPOSE[@]}" ps -q)
      sleep 1
    done
  ) & sampler=$!
  wait "$loader"
  kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true
  loader=''; sampler=''
  cat "results/logs/${name}.log"
done
python3 scripts/summarize.py all

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/sondeo.sh [duración_segundos=60] [intervalo_segundos=0.2]'; exit 0; }
duration="${1:-60}"; interval="${2:-0.2}"
[[ "$duration" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'Use duración entera positiva e intervalo numérico positivo.'
awk -v interval="$interval" 'BEGIN { exit !(interval > 0) }' || die 'El intervalo debe ser mayor que cero.'
port="$(api_port)"; mkdir -p results; out="results/sondeo_$(date +%Y%m%dT%H%M%S).csv"
echo 'timestamp,status,latency_ms,replica' > "$out"; end=$((SECONDS+duration)); errors=0; total=0
while (( SECONDS < end )); do
  total=$((total+1)); start="$(date +%s%N)"; response="$(curl -sS --max-time 3 -w $'\n%{http_code}' "http://127.0.0.1:${port}/health" 2>/dev/null || true)"
  code="${response##*$'\n'}"; body="${response%$'\n'*}"; finish="$(date +%s%N)"; ms=$(( (finish-start)/1000000 )); replica="$(printf '%s' "$body" | sed -n 's/.*"replica":"\([^"]*\)".*/\1/p')"
  [[ "$code" == 200 ]] || errors=$((errors+1)); printf '%s,%s,%s,%s\n' "$(date -Is)" "$code" "$ms" "$replica" >> "$out"; sleep "$interval"
done
echo "Solicitudes=$total errores=$errors CSV=$out"

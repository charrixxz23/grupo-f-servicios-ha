#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/scale.sh 1|2|3'; exit 0; }
n="${1:-}"; [[ "$n" =~ ^[123]$ ]] || die 'Indique 1, 2 o 3 réplicas.'
"${COMPOSE[@]}" up -d --scale "api=$n" api lb
sleep 6  # nginx resolver TTL configured to 5 s
"${COMPOSE[@]}" ps api
for i in $(seq 1 12); do curl -fsS "http://127.0.0.1:$(api_port)/health"; echo; done

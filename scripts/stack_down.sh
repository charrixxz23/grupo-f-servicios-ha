#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/stack_down.sh'; exit 0; }
echo 'Se detendrán los contenedores de este proyecto; los volúmenes persistentes se conservan.'
"${COMPOSE[@]}" down

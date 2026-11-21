#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/db_up.sh'; exit 0; }
[[ -f .env ]] || die 'Ejecute scripts/stack_up.sh primero.'
"${COMPOSE[@]}" build db-setup
"${COMPOSE[@]}" up -d mysql1 mysql2 mysql3 db-setup
for i in $(seq 1 150); do
  if "${COMPOSE[@]}" ps --status exited --services | grep -qx db-setup; then break; fi
  sleep 2
done
if "${COMPOSE[@]}" ps --status exited --services | grep -qx db-setup; then
  setup_id=$("${COMPOSE[@]}" ps -aq db-setup)
  exit_code=$(docker inspect --format '{{.State.ExitCode}}' "$setup_id")
  "${COMPOSE[@]}" logs --no-color db-setup
  [[ "$exit_code" == 0 ]] || die "El inicializador del clúster terminó con código $exit_code."
else
  die 'Tiempo agotado esperando el inicializador del clúster MySQL.'
fi
"${COMPOSE[@]}" logs --no-color --tail=20 db-setup mysql1 mysql2 mysql3
online="$("${COMPOSE[@]}" exec -T mysql1 sh -ec 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -Nse "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE=\"ONLINE\""')"
primaries="$("${COMPOSE[@]}" exec -T mysql1 sh -ec 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -Nse "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE=\"ONLINE\" AND MEMBER_ROLE=\"PRIMARY\""')"
[[ "$online" == 3 && "$primaries" == 1 ]] || die "Clúster MySQL incompleto: online=$online primary=$primaries (esperados 3 y 1)."
echo "VALIDATED: MySQL online=$online primary=$primaries"

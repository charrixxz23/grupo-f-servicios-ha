#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/verify_ha.sh'; exit 0; }
base="http://127.0.0.1:$(api_port)"
curl -fsS "$base/health/ready"; echo
status="$(curl -fsS "$base/api/status")"; printf '%s\n' "$status"
[[ "$status" == *'"mysql":true'* && "$status" == *'"redis":true'* ]] || die 'API no confirma sus dos dependencias.'
static_code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/)"; [[ "$static_code" == 200 ]] || die 'Assets no responden HTTP 200.'
"${COMPOSE[@]}" exec -T sentinel1 sh -ec 'redis-cli -p 26379 -a "$REDIS_PASSWORD" SENTINEL ckquorum ha-cache 2>/dev/null | grep -q OK' || die 'Sentinel no tiene quórum.'
online="$("${COMPOSE[@]}" exec -T mysql1 sh -ec 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -Nse "SELECT COUNT(*) FROM performance_schema.replication_group_members WHERE MEMBER_STATE=\"ONLINE\""')"
[[ "$online" == 3 ]] || die "Miembros ONLINE de MySQL: $online (se requieren 3)."
key="verify-$(date +%s)"; payload="{\"id\":\"$key\",\"value\":\"persisted\"}"
write="$(curl -fsS -H 'content-type: application/json' -d "$payload" "$base/api/records")"; printf '%s\n' "$write"
readback="$(curl -fsS "$base/api/records/$key")"; [[ "$readback" == *'"value":"persisted"'* ]] || die 'La lectura no coincide con el registro escrito.'
echo "VALIDATED: API, assets, MySQL online=$online, Redis quorum, write/read-back=$key"

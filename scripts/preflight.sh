#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"; cd "$ROOT"
mkdir -p results/logs; exec > >(tee -a "results/logs/preflight_$(date +%Y%m%dT%H%M%S).log") 2>&1
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/preflight.sh'; exit 0; }
for cmd in docker bash awk sed openssl; do command -v "$cmd" >/dev/null || { echo "Falta comando: $cmd" >&2; exit 1; }; done
docker info >/dev/null 2>&1 || { echo 'Docker Engine no responde. Inicie Docker Desktop con backend Linux y vuelva a ejecutar.' >&2; exit 2; }
docker compose version
if [[ -r /sys/fs/cgroup/cgroup.controllers ]]; then echo "cgroups: $(cat /sys/fs/cgroup/cgroup.controllers)"; else echo 'No se ve cgroup v2 en esta terminal'; fi
docker info --format 'Engine={{.ServerVersion}} OS={{.OperatingSystem}} CgroupVersion={{.CgroupVersion}} CgroupDriver={{.CgroupDriver}}'
command -v free >/dev/null && free -h || true
df -h "$ROOT"
echo 'Preflight completado. Esta salida no verifica los servicios.'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"; cd "$ROOT"; mkdir -p results/logs; exec > >(tee -a "results/logs/io_audit_$(date +%Y%m%dT%H%M%S).log") 2>&1
[[ "${1:-}" == --help ]] && { echo 'Uso: bash scripts/io_audit.sh'; exit 0; }
for cmd in df free; do command -v "$cmd" >/dev/null || { echo "Falta $cmd" >&2; exit 1; }; done
df -hT; df -i; free -h; grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo
for cmd in iostat pidstat; do if command -v "$cmd" >/dev/null; then echo "== $cmd =="; "$cmd" -dx 1 2 2>/dev/null || "$cmd" -d 1 2 2>/dev/null || true; else echo "$cmd ausente: instale el paquete sysstat en WSL para medición de E/S."; fi; done

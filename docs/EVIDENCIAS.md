# Guía de capturas auténticas

Abra una terminal **Ubuntu (WSL2)**. Use esta carpeta en todas las capturas:

```bash
cd /ruta/al/grupo-f-servicios-ha
export PS1='\[\e[1;36m\][UTP-HA | WSL2 | \u]\[\e[0m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '
```

Mantenga visible el PS1 y el prompt en las capturas. Capture la terminal con **Win+Shift+S** y guarde los PNG indicados en `evidence/capturas/`. Ejecute primero `bash scripts/stack_up.sh`; las pruebas con medidas sólo se capturan después de que sus archivos reales estén en `results/`. Nunca edite resultados para que aparenten éxito.

| # / archivo PNG | Terminal y comando listo para pegar | Salida esperada / qué demuestra | Módulo / requisito |
|---|---|---|---|
| 01 `01_entorno_docker.png` | WSL2, raíz: `bash scripts/preflight.sh` | Docker Engine, cgroup v2, RAM y filesystem detectados. | II: entorno y cgroups |
| 02 `02_arquitectura_servicios.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml ps` | Servicios Compose y salud real. | HA: topología |
| 03 `03_ps1_personalizado.png` | WSL2, raíz: `printf '%s\\n' "$PS1"; pwd; id` | Prompt identifica laboratorio, WSL y usuario. | I: contexto de medición |
| 04 `04_procesos_hilos.png` | WSL2, raíz: `bash scripts/process_audit.sh api` | PID, procesos/tareas del contenedor API. Repita con `lb`, `redis-primary`, `mysql1`. | I: procesos e hilos |
| 05 `05_cgroups_cpu.png` | WSL2, raíz: `bash scripts/kernel_audit.sh api` | `cpu.max` y `cpu.stat` efectivos. Repita con `mysql1`. | II: cuota y uso CPU |
| 06 `06_cgroups_memoria.png` | WSL2, raíz: `bash scripts/kernel_audit.sh mysql1` | `memory.max`, `memory.high`, `memory.current`. | II: cgroup memoria |
| 07 `07_cgroups_pids.png` | WSL2, raíz: `bash scripts/kernel_audit.sh redis-primary` | `pids.max`, `pids.current`. | II: límite de tareas |
| 08 `08_oom_score_adj.png` | WSL2, raíz: `bash scripts/kernel_audit.sh mysql1` y luego `bash scripts/kernel_audit.sh redis-primary` | Valores de ajuste para priorización OOM. No es inmunidad. | II: OOM |
| 09 `09_memoria_high_psi.png` | WSL2, raíz: `bash scripts/memory_pressure.sh high` | Guarda `memory.high`, `memory.current`, latencia de salud, PSI, `memory.events` y p99 de API. En este Docker Desktop el valor observado fue `memory.high=max` y PSI 0: muestre también la limitación documentada, sin afirmar throttling que no ocurrió. | II: presión moderada, PSI y límite observado |
| 10 `10_memoria_max_oom.png` | WSL2, raíz: `bash scripts/memory_pressure.sh oom` | OOM sólo en contenedor desechable; conserva `OOMKilled`, exit y logs. `dmesg` puede estar restringido. | II: `memory.max`/OOM |
| 11 `11_disco_filesystem.png` | WSL2, raíz: `df -hT; df -i; docker volume ls --filter name=semestral-ha` | FS y volúmenes de persistencia. | III: filesystem |
| 12 `12_iostat.png` | WSL2, raíz: `iostat -dx 1 3` | Lecturas, escrituras, await, `%util`; requiere paquete `sysstat`. | III: latencia/saturación E/S |
| 13 `13_pidstat.png` | WSL2, raíz: `pidstat -d 1 3` | E/S por procesos visibles en WSL; explique la VM Docker y montajes. | III: actividad por proceso |
| 14 `14_escalado_una_replica.png` | WSL2, raíz: `bash scripts/scale.sh 1` | Réplica única responde por el LB. | I / escalabilidad |
| 15 `15_escalado_tres_replicas.png` | WSL2, raíz: `bash scripts/scale.sh 3` | Tres contenedores API y hostname variable en respuestas. | I / escalabilidad |
| 16 `16_comparacion_p99.png` | WSL2, raíz: ejecutar sucesivamente `bash scripts/load.sh 1 3 30s 25`, `bash scripts/load.sh 2 3 30s 25`, `bash scripts/load.sh 3 3 30s 25`; después `cat results/summary.csv` | RPS y p95/p99 promediados de al menos tres corridas por tamaño. Compare también archivos JSON individuales. | Escalabilidad / p99 |
| 17 `17_redis_replication.png` | WSL2, raíz: `bash scripts/cache_up.sh` | Sentinel quórum, primario y réplicas en `INFO replication`. | HA caché |
| 18 `18_mysql_replication.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml exec mysql1 mysql -uroot -p -e "SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE FROM performance_schema.replication_group_members"` | Tres miembros, un primario y secundarios ONLINE; contraseña interactiva. | HA base de datos |
| 19 `19_fallo_app.png` | Terminal A WSL2, raíz: `bash scripts/sondeo.sh 45 0.2`; durante el sondeo, Terminal B: `bash scripts/falla.sh app`; al final: `tail -n 8 results/failover_*_app.csv` | Muestra respuestas de prueba y registros mientras cae una API. | Failover app |
| 20 `20_fallo_redis.png` | WSL2, raíz: `bash scripts/falla.sh redis` | Inyección, CSV, errores HTTP observados y estimado MTTR. | Failover Redis |
| 21 `21_promocion_redis.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml exec -T sentinel1 sh -ec 'redis-cli --raw -p 26379 -a "$REDIS_PASSWORD" SENTINEL master ha-cache | grep -A1 "^flags$" | tail -1'` | Flags del master actual elegido por Sentinel. | I: hilos / HA Redis |
| 22 `22_fallo_mysql.png` | WSL2, raíz: `bash scripts/falla.sh mysql` | Caída controlada de primario, sondeo POST y CSV. | Failover MySQL |
| 23 `23_promocion_mysql.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml exec mysql1 mysql -uroot -p -e "SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE FROM performance_schema.replication_group_members"` | Miembros y primario tras recuperación; contraseña interactiva. | HA MySQL |
| 24 `24_sondeo_http.png` | WSL2, raíz: `bash scripts/sondeo.sh 30 0.2` | Conteo HTTP, latencia y CSV real. | Disponibilidad |
| 25 `25_mttr.png` | WSL2, raíz: `rg 'estimated_mttr_ms|samples=' results/failover_*.log` | Duración estimada por escenario y muestras observadas. | SRE / MTTR |
| 26 `26_integridad_datos.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml exec mysql1 mysql -uroot -p -e "SELECT COUNT(*) AS records, MIN(id), MAX(id) FROM ha_lab.records"` | Filas persistidas observadas después del fallo; contrástelas con el CSV de POST 2xx. | III / persistencia |
| 27 `27_estado_final.png` | WSL2, raíz: `docker compose --env-file .env -f docker-compose.yml ps; curl -fsS http://127.0.0.1:8082/api/status; curl -fsS http://127.0.0.1:8082/health` | Estado final, lectura y salud. | Validación integral |

> **Seguridad de credenciales:** para MySQL, prefiera ejecutar el cliente y dejar que solicite `Enter password:`. No use `-p$(...)` en una captura compartible, ya que la contraseña podría aparecer en el historial o en la línea de comandos. Para Sentinel el secreto se encuentra dentro del contenedor y el comando lo toma del entorno; revise la captura antes de compartirla.

`docs/RESULTADOS.md` distingue pendiente y validado. Las capturas 09, 10, 12–16 y 19–26 sólo se toman después de ejecutar el experimento correspondiente y guardar los archivos reales.

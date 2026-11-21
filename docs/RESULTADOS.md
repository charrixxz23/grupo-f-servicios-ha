# Resultados y estado de validación

Resultados observados en WSL2 Ubuntu 6.18.58.1 con Docker Desktop Engine 29.9.2, cgroups v2, 3 CPU visibles y 5.8 GiB de memoria asignada a WSL. Windows reporta 31.2 GiB físicos; los contenedores compiten por el límite de WSL, no por toda esa memoria. Las cifras provienen de los archivos de `results/`; no son estimaciones de producción.

## Validación

| Elemento | Estado | Resultado / límite |
|---|---|---|
| Docker Compose y scripts | Validado | Configuración Compose resuelta; Bash/Node/Python se ejecutaron en WSL. |
| API, Nginx LB y assets | Validado | `/health/ready`, API, balanceo y estáticos respondieron. El puerto HTTP del proyecto es `127.0.0.1:8082`; `8080` estaba ocupado por un servicio ajeno y quedó intacto. |
| MySQL HA | Validado | InnoDB Cluster, 3 miembros ONLINE, un primario; prueba real de caída y reelección. |
| Redis HA | Validado | 3 Sentinel con quórum 2, primario y 2 réplicas; caída real del primario elegido y promoción. |
| Escrituras SQL tras failover | Validado | Ensayo final: 21 de 21 POST exitosos persistidos, `integrity_match=true`. |
| Prueba de disponibilidad de API | Validado | Caída de una réplica: 19/19 sondeos exitosos, 0 fallos observados. |
| Pruebas de escala | Validado | 3 repeticiones de 10 s por escala, concurrencia 10; 9 corridas, 0 errores y 0 respuestas no 2xx. |
| Cgroups v2 CPU/memoria/PIDs | Validado | Valores efectivos leídos y contrastados con `docker inspect`; archivos PSI/events presentes. |
| Procesos e hilos | Validado | Auditorías de API, Nginx, Redis y MySQL con `/proc`, `ps` y `docker top`. Los conteos varían con actividad. |
| E/S y memoria del host | Validado con límite | `df`, `free`, `/proc/meminfo`, `iostat` y `pidstat` disponibles. Las métricas son de WSL/VM y no atribuyen E/S de forma inequívoca a cada volumen Docker. |
| Presión `memory.high` | Parcialmente validado | Servicio siguió respondiendo; p99 de carga 210 ms, pero el cgroup mostró `memory.high=max`, PSI 0 y `memory.events high=0`. El archivo cgroup es de solo lectura dentro del contenedor, aunque Docker declara reserva de 48 MiB. No se afirma que se haya provocado throttling `memory.high`. |
| OOM aislado | Validado | Solo contenedor desechable de 96 MiB; `oom_kill` aumentó, Docker reportó `OOMKilled=true`, y `dmesg -T` mostró `CONSTRAINT_MEMCG` y procesos `stress-ng-vm` terminados. La API y MySQL quedaron intactos. |
| Capturas de pantalla | Pendiente del usuario | La guía secuencial está en `docs/EVIDENCIAS.md`; las capturas deben tomarse desde la terminal real y no se generan artificialmente. |

## Escalabilidad

Cada escenario ejecutó tres corridas de 10 s con concurrencia 10, idéntica consulta `/api/status`, calentamiento de 3 s y carga local. Promedios de `results/summary.csv`:

| Réplicas API | RPS promedio | Latencia media | p95 promedio | p99 promedio | Errores / no 2xx |
|---:|---:|---:|---:|---:|---:|
| 1 | 550.4 | 18.29 ms | 40.16 ms | 64.30 ms | 0 / 0 |
| 2 | 564.7 | 17.82 ms | 42.17 ms | 70.05 ms | 0 / 0 |
| 3 | 507.6 | 19.74 ms | 44.51 ms | 73.14 ms | 0 / 0 |

La segunda réplica aumentó el RPS promedio 2.6% frente a una; tres réplicas quedaron 7.8% por debajo de una. En esta carga pequeña no se observó escalado lineal; el cliente, el límite de 3 CPU de WSL, Docker Desktop y el acceso por disco Windows pueden dominar. La conclusión es específica a este ensayo. Consulte el gráfico [escalabilidad.svg](../results/escalabilidad.svg) y los JSON/CSV por corrida.

Una corrida separada durante presión de memoria concurrente usó 25 conexiones durante 20 s: 8,240 solicitudes, 412 RPS, p99 210.2 ms y 0 errores. La prueba no produjo PSI ni `memory.events high`, así que sirve como medición de carga simultánea, no como evidencia de throttling por `memory.high`.

## Failover medido

| Escenario | Recuperación observada | Sondeos exitosos | Fallos | Integridad |
|---|---:|---:|---:|---|
| API, caída de una réplica | 1.554 s | 19/19 | 0 | Las réplicas restantes atendieron todo el sondeo. |
| Redis, caída del primario actual | 14.435 s | 27/29 HTTP 201 | 2 conexiones fallidas (`000`); ningún 5xx observado | Sentinel promovió un nodo distinto; el valor de caché confirmado en ambas réplicas sobrevivió. |
| MySQL, caída del primario | 5.202 s | 21/21 | 0 | 21/21 escrituras confirmadas persistidas en el primario electo. |

MTTR aquí es una medida del script desde que detiene el servicio hasta que detecta el criterio de recuperación; no mide cada etapa interna del consenso. Los dos fallos del escenario Redis se conservan en el CSV. Una primera ejecución perdió el valor cuando el endpoint confirmaba con un solo acuse; los artefactos quedaron guardados. Se corrigió a `WAIT 2 1500`, se verificó el nodo Redis que Sentinel realmente consideraba primario y el ensayo final conservó el valor. Esta espera no ofrece durabilidad síncrona ante pérdida simultánea de nodos o energía.

## Límites y lectura del kernel

La API se observó con 11 hilos; MySQL con 76 durante la auditoría posterior; Redis con 9; Nginx LB se configura con un worker. Los conteos corresponden a instantes concretos, y MySQL crea hilos de fondo adicionales.

La API mostró `cpu.max=100000 100000`, `memory.max=402653184` (384 MiB), `pids.max=128`, `oom_score_adj=250`. MySQL mostró `cpu.max=100000 100000`, `memory.max=1610612736` (1.5 GiB), `pids.max=256`, `oom_score_adj=-500`. `memory.high=max` en ambos contenedores. El host WSL mostró alrededor de 2.1 GiB disponibles de un presupuesto de 5.8 GiB durante la auditoría. `iostat` y `pidstat` registraron actividad baja entre muestras; el conjunto no demuestra saturación sostenida de CPU o disco como cuello de botella.

El objetivo de cero HTTP 5xx se cumplió en los CSV finales, aunque Redis tuvo dos conexiones sin respuesta (HTTP `000`) durante la elección. No se declara cero errores de disponibilidad ni RPO cero. Los archivos de cada ejecución, incluyendo intentos fallidos y corregidos, se conservan en `results/` y `results/logs/` para revisión.

## Revalidación automatizada de scripts — 2026-11-19

Tras endurecer los scripts, se repitieron comprobaciones de disponibilidad, integridad y recuperación. API: 17/17 sondeos HTTP exitosos, recuperación estimada 0.622 s. MySQL: 17 escrituras confirmadas entre 18 muestras, recuperación 4.527 s; las 17 escrituras quedaron en el primario electo (`integrity_match=true`). Redis: Sentinel promovió `redis-primary`, el valor con dos acuses se leyó en el nuevo primario; 20/22 escrituras HTTP 201 y dos conexiones fallidas (`000`), recuperación estimada 11.611 s. Estos valores son una revalidación separada y no reemplazan los ensayos de 10 s usados para la comparación de escalabilidad. También pasó una carga breve de verificación (1 s, concurrencia 2, 480 solicitudes, cero errores/no 2xx); se excluye de `results/summary.csv` para mantener comparables las nueve corridas originales.

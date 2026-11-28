# Servicios en producción con alta disponibilidad (HA)

Proyecto semestral de **Sistemas Operativos (0689)** — Universidad Tecnológica de Panamá (UTP), Grupo 1SF134 · **Grupo F**.  
El repositorio contiene el código del laboratorio, los scripts reproducibles de despliegue, carga, failover y auditoría del kernel, la documentación técnica, el informe final (PDF y DOCX) y la presentación.

## Arquitectura

- **Balanceador (Nginx):** enruta el tráfico HTTP (`127.0.0.1:8082`) hacia las réplicas activas de la API.
- **API (Node.js):** escalable horizontalmente de 1 a 3 réplicas con descubrimiento dinámico de primarios.
- **Assets estáticos (Nginx):** servidor separado (`127.0.0.1:8081`) respaldado por el *page cache* del kernel.
- **Caché HA (Redis + Sentinel):** 1 primario, 2 réplicas y 3 nodos Sentinel (quórum = 2) con promoción automática.
- **Base de datos HA (MySQL 8.4):** 3 miembros en **InnoDB Group Replication** (*single-primary*).
- **Control del sistema operativo:** límites por servicio con **cgroups v2** (`cpu.max`, `memory.max`, `pids.max`), protección relativa `oom_score_adj` y 6 volúmenes Docker persistentes nombrados.

> El despliegue corre en un solo equipo virtualizado (WSL2/Docker Desktop o VM Linux); por ello la replicación demuestra *failover* lógico entre servicios, pero no elimina el punto único de falla físico del host.

## Requisitos

- Entorno Linux con **cgroups v2** habilitados (Windows 11 + WSL2 Ubuntu + Docker Desktop, o máquina virtual Ubuntu 24.04 con Docker Engine).
- Docker Engine y **Docker Compose v2**, `bash`, `curl`, `openssl` y `python3`.
- Paquete `sysstat` (`iostat`, `pidstat`) y `procps` para auditorías de procesos y E/S.

## Inicio rápido

Desde la terminal Linux (WSL2 o VM), clona el repositorio y ejecuta:

```bash
cd grupo-f-servicios-ha
bash scripts/preflight.sh
bash scripts/stack_up.sh
bash scripts/verify_ha.sh
```

El primer arranque crea un archivo `.env` local con credenciales aleatorias generadas con `openssl`. No compartas ese archivo (`.env` está excluido en `.gitignore` y `.env.example` solo contiene valores de referencia).

## Scripts principales y operación

| Script | Función |
|---|---|
| `scripts/preflight.sh` | Comprueba Docker, Compose, cgroups v2, memoria y disco antes del despliegue. |
| `scripts/stack_up.sh` | Genera `.env` (si no existe), construye y levanta el stack completo. |
| `scripts/cache_up.sh` | Levanta y valida Redis + Sentinel (quórum = 2 y 2 réplicas conectadas). |
| `scripts/db_up.sh` | Inicializa y valida MySQL 8.4 Group Replication (3 miembros `ONLINE`, 1 `PRIMARY`). |
| `scripts/verify_ha.sh` | Verifica salud HTTP, assets, quórum Sentinel, 3 nodos MySQL y escritura/lectura real. |
| `scripts/scale.sh 1\|2\|3` | Escala la API horizontalmente sin detener MySQL ni Redis y comprueba balanceo. |
| `scripts/load.sh [n] [reps] [dur] [conc]` | Ejecuta pruebas de carga repetidas y calcula promedios con `scripts/summarize.py`. |
| `scripts/falla.sh app\|redis\|mysql` | Inyecta fallos controlados bajo sondeo continuo y mide MTTR, errores e integridad. |
| `scripts/sondeo.sh [seg] [intervalo]` | Sondea disponibilidad HTTP continua y registra latencia y errores en CSV. |
| `scripts/process_audit.sh [servicio]` | Audita procesos e hilos reales (Módulo I: `/proc/1/task`, `ps -L`, `top -H`). |
| `scripts/kernel_audit.sh [servicio]` | Audita cgroups v2 y `oom_score_adj` (Módulo II: `cpu.max`, `memory.max`, `pids.max`). |
| `scripts/memory_pressure.sh high\|oom` | Ejecuta las pruebas aisladas de presión de memoria y OOM Killer en contenedor desechable. |

*(Los módulos auxiliares `scripts/common.sh` y `scripts/summarize.py` son dependencias internas utilizadas por los scripts anteriores).*

## Entregables y documentación

- [Informe del proyecto (PDF)](docs/Grupo_F_Proyecto_Semestral_HA.pdf)
- [Informe del proyecto (DOCX)](docs/Grupo_F_Proyecto_Semestral_HA.docx)
- [Presentación (PPTX)](docs/Grupo_F_Presentacion_HA.pptx)
- [Guía de evidencias](EVIDENCIAS.md)
- Documentación técnica adicional en `docs/` (`ARQUITECTURA.md`, `KERNEL.md`, `EXPERIMENTOS.md`, `FAILOVER.md`, `RESULTADOS.md`).

> **Nota de privacidad:** En la versión pública del informe incluida en este repositorio se omitieron los números de cédula de los integrantes por privacidad, dado que el repositorio es de acceso público. Asimismo, el archivo `.env` real, los registros crudos (`results/raw/`) y las bitácoras locales (`*.log`) se excluyen del control de versiones.

# Guía de sustentación

## Módulo I: procesos e hilos

**¿Qué es una tarea de Linux?** Proceso o hilo planificable que tiene un TID; `/proc/PID/task` enumera hilos del proceso. **¿Por qué Redis parece monohilo?** El event loop principal serializa el comando; threads I/O y BIO cubren I/O y trabajo de fondo, por eso hay tareas auxiliares. **¿Qué cambia al escalar API?** Se crean procesos/containers adicionales y conexiones concurrentes a Router/Redis; no se multiplica necesariamente el rendimiento si MySQL/host es el cuello.

Demuestre con `bash scripts/process_audit.sh api`, `docker top`, `ps -eLf` y `/proc`. Los conteos son del momento medido.

## Módulo II: cgroups y OOM

**¿Qué hace `cpu.max`?** Limita cuota de CPU en un período del cgroup. **¿Qué diferencia `memory.high` y `memory.max`?** `high` provoca reclaim y throttling; `max` es el límite duro que puede iniciar OOM dentro del grupo. **¿`oom_score_adj` protege por completo a MySQL?** No, sólo pondera selección del OOM killer.

Demuestre `bash scripts/kernel_audit.sh mysql1`, explique `cpu.stat`, `memory.events`, PSI y por qué la prueba destructiva se limita a un contenedor de prueba.

## Módulo III: memoria y E/S

**¿Dónde viven los datos?** MySQL en named volumes `/var/lib/mysql`, Redis en named volumes `/data`; la capa overlay es efímera. **¿Qué hace page cache?** Conserva páginas de archivos para lecturas futuras; puede reducir I/O físico de assets. **¿Cómo identificó un cuello de botella?** Compare RPS/p99 con cuota CPU, memoria/PSI, conexiones e `iostat` (`await`, `%util`), no por intuición.

Demuestre `bash scripts/io_audit.sh`, `df -hT`, `free -h` e informe las limitaciones de VHDX/NTFS/OneDrive.

## Alta disponibilidad

Explique por qué tres votos permiten mayoría 2/3, la diferencia de Sentinel y el descubrimiento writable de MySQL en cada API, el costo de la replicación asíncrona, reconexión y transacciones ambiguas. Nunca prometa RPO=0 ni cero errores si los CSV de ensayo no los muestran. Describa el MTTR como medida de extremo a extremo del cliente.

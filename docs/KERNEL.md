# Procesos, hilos, cgroups y almacenamiento

## Procesos e hilos (Módulo I)

Nginx usa un master y un worker (`worker_processes 1` en `nginx/nginx.conf`) para comparar escenarios pequeños. Node ejecuta un proceso por contenedor y un event loop; consultas asíncronas y libuv usan el pool nativo, cuyo tamaño depende de la operación y configuración. Redis ejecuta un event loop principal y threads auxiliares de I/O/BIO; `--io-threads 2` está declarado. MySQL usa un proceso `mysqld`, threads InnoDB fijos y threads adicionales según conexiones. Conteos reales cambian por versión, imagen y actividad: no son valores codificados en el informe.

En WSL, use `ps -eLf`, `ps -L -p PID`, `top -H -p PID`, `ls /proc/PID/task`; dentro de un contenedor, inspeccione PID 1 y `docker top`. El namespace de PID limita lo visible en cada contenedor, mientras Docker Desktop muestra los PID del host de VM.

## cgroups v2 (Módulo II)

En cgroup v2: `cpu.max` expresa cuota/período; `memory.max` limita memoria; `memory.high` inicia reclamación/throttling; `pids.max` limita tareas; `memory.current`, `pids.current`, `cpu.stat`, `memory.events` y `memory.pressure` exponen estado. `scripts/kernel_audit.sh servicio` lee los valores efectivos del cgroup raíz del contenedor y los compara con `docker inspect`. La plataforma puede montar un cgroup namespace privado. Confirme que los archivos existen; no infiera el límite desde la configuración declarada.

`oom_score_adj` negativo protege relativamente a los tres miembros MySQL; valores positivos hacen Redis y API más sacrificables que las bases. El proceso todavía puede morir si el grupo agota su presupuesto o el host entra en OOM.

La presión `high`/`oom` sólo corre en contenedores desechables. En esta ejecución, Docker Desktop reportó una reserva de 48 MiB, pero `/sys/fs/cgroup/memory.high` mostró `max` y el montaje cgroup del contenedor fue de solo lectura; por eso el ensayo moderado no activó `memory.events high` ni PSI. Se clasifica parcialmente validado. La prueba OOM aislada sí incrementó `oom_kill` y `dmesg -T` mostró `CONSTRAINT_MEMCG`/`Memory cgroup out of memory`; el proceso principal del contenedor terminó con código 0 aunque se marcó `OOMKilled=true`, porque stress-ng completó tras el OOM de su trabajador. WSL2 puede ocultar registros del kernel anfitrión y su PSI puede reflejar actividad agregada de la VM.

## Memoria, filesystem y E/S (Módulo III)

El overlayfs aloja capas de imagen y sistema efímero del contenedor; los named volumes guardan `/var/lib/mysql` y `/data` de Redis y sobreviven a `compose down`. Page Cache acelera archivos de assets; una lectura posterior puede no producir acceso físico. `df -hT`, `df -i`, `free -h`, `/proc/meminfo`, `iostat -dx` y `pidstat -d` describen filesystem, memoria y E/S. En Docker Desktop, el I/O visto por WSL puede incluir VHDX y el mount de OneDrive/NTFS; anote ese límite al interpretar `%util` y `await`.

## PS1 para capturas

```bash
export PS1='\[\e[1;36m\][UTP-HA | WSL2 | \u]\[\e[0m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '
```

La ruta del proyecto incluye espacios y tildes; use comillas al cambiar de directorio.

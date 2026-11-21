# Diseño experimental reproducible

Antes de comparar, ejecute `scripts/preflight.sh`; mantenga el mismo endpoint, duración, concurrencia y carga de fondo. Ejecute `scripts/scale.sh N` y luego `scripts/load.sh N 3 30s 25` para N=1,2,3. El generador consulta `/api/status`, registra cada latencia observada, HTTP no 2xx y fallos de conexión y escribe JSON/CSV en `results/raw/`; el resumen conserva y agrupa todas las corridas `scale*_rep*.json`. Se validaron tres repeticiones por escala en 10 s y concurrencia 10; use 30 s/25 para una medición académica más larga. El tráfico es real y de una sola máquina, por eso mide el techo del cliente/host compartido y no capacidad de producción.

## Failover

Ejecute `scripts/sondeo.sh 60 0.2` en una terminal, y `scripts/falla.sh app|redis|mysql` en otra. El script de falla envía POST idempotentes a la API, mide estado HTTP/latencia y reinicia el recurso afectado. Guarde CSV y logs. Un ensayo sólo acredita cero errores si todas las solicitudes registradas fueron exitosas y la integridad posterior coincide; la condición de salida del script no basta.

## Presión de memoria

`scripts/memory_pressure.sh high` y `oom` limitan el ejercicio a un contenedor descartable; no operan sobre la base de datos. Compare PSI/eventos antes y durante carga en ese cgroup. En este Docker Desktop, `memory.high` fue `max` y el cgroup no permitió escritura, por lo que la prueba moderada no produjo throttling PSI (`high=0`); reporte esa limitación y la prueba de continuidad/p99 como parcial. La prueba OOM verifica `State.OOMKilled`, conserva `memory.events` y, en este host, pudo leer registros `CONSTRAINT_MEMCG` con `dmesg -T`.

## Variables a reportar

Anote versión Docker/Compose, kernel, cgroup, CPUs/RAM disponibles, versiones de imágenes, carga/duración, número de réplicas, tiempos de calentamiento, cada repetición y toda falla. El cuello de botella sólo se atribuye después de observar CPU throttling, memoria/PSI, conexiones, `await`/`%util` y RPS/p99.

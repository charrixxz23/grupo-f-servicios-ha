# Servicios en producción con alta disponibilidad

Proyecto semestral de Sistemas Operativos (UTP), Grupo F. El repositorio contiene el código del laboratorio, scripts de automatización y auditoría, documentación, informe PDF y presentación.

## Arquitectura

- Nginx como balanceador de la API Node.js y una capa Nginx separada para contenido estático.
- Escalado horizontal de una a tres réplicas de API.
- Redis con tres nodos y Sentinel para elección del primario.
- MySQL InnoDB Cluster de tres miembros con Group Replication.
- Auditorías de procesos e hilos, cgroups v2, memoria/OOM y entrada/salida de disco.
- Volúmenes Docker nombrados para persistencia.

El despliegue corre en un solo equipo virtualizado (WSL2/Docker Desktop); por eso, la replicación mejora la recuperación de servicios, pero no elimina el punto único de falla del host.

## Requisitos

- Windows 11, WSL2 Ubuntu y Docker Desktop con contenedores Linux.
- Docker Compose v2, `curl` y `openssl` en Ubuntu.
- `sysstat` (`iostat`, `pidstat`) para las mediciones de E/S.
- Cgroups v2 habilitados en el daemon Docker.

## Inicio

Desde Ubuntu en WSL2, clona este repositorio y ejecuta:

```bash
cd grupo-f-servicios-ha
bash scripts/preflight.sh
bash scripts/stack_up.sh
bash scripts/verify_ha.sh
```

El primer arranque crea un archivo `.env` local con credenciales aleatorias. No compartas ese archivo. `.env.example` solo contiene valores de ejemplo.

## Scripts requeridos y operación

```bash
bash scripts/stack_up.sh
bash scripts/cache_up.sh
bash scripts/db_up.sh
bash scripts/load.sh 1 3 30s 25
bash scripts/falla.sh app    # También admite redis y mysql
bash scripts/sondeo.sh 60 0.2
```

Los scripts auxiliares en `scripts/` preparan el entorno, escalan servicios, recopilan evidencias y auditan procesos, cgroups, memoria y E/S. Los datos generados por nuevas pruebas quedan en `results/`; los registros crudos locales no se publican.

## Entregables

- [Informe del proyecto (PDF)](docs/Grupo_F_Proyecto_Semestral_HA.pdf)
- [Presentación (PPTX)](docs/Grupo_F_Presentacion_HA.pptx)
- [Guía de evidencias](EVIDENCIAS.md)
- Documentación adicional en `docs/`.

El informe de publicación omite los números de cédula de los integrantes. El archivo `.env` real, registros crudos y paquetes ZIP locales se excluyen del repositorio.

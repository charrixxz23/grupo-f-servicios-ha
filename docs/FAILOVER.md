# Failover y recuperación

## API

Escala a 3 API, inicia `sondeo.sh` y ejecuta `falla.sh app`. Docker detiene una instancia; Nginx pasivo la retira al observar fallas y continúa con las restantes. El sondeo de salud y las escrituras de prueba no son equivalentes: revise ambos CSV.

## Redis

Tres Sentinels con quórum 2 detectan el primario tras 5 s y promueven una réplica. IORedis redescubre el master usando el nombre lógico. El endpoint de escritura espera los acuses de las dos réplicas (`WAIT 2 1500`) antes de responder éxito; las escrituras sin ambos acuses se devuelven como error. Esto reduce la ventana de pérdida, pero la replicación sigue siendo asíncrona y AOF cada segundo no asegura confirmación durable síncrona. Si una réplica no responde, la API rechaza la escritura tras el límite. `falla.sh redis` pausa el contenedor primario para conservar su nombre DNS en la red mientras Sentinel elige el nuevo primario; después comprueba directamente allí el valor previamente escrito y reanuda el nodo. Su duración estimada cubre desde la inyección hasta la promoción y esa comprobación de datos, no la reconexión de cada cliente API. Reporte además el rol Sentinel, el servicio promovido, valor de prueba y errores del sondeo.

## MySQL

Group Replication con 3 miembros; el grupo conserva mayoría con 2 nodos. Cada API descubre el primario consultando `read_only` en los tres nombres DNS de servicio y actualiza su pool en cuanto vence la caché de 2 s o falla la conexión. InnoDB Cluster evita que un miembro aislado gane solo el primario cuando no alcanza mayoría, pero particiones y recuperación de clientes aún pueden causar transacciones fallidas/ambiguas. La API usa IDs estables para POST repetible. Compare los IDs insertados y recibidos antes/después. No declare RPO cero sin una garantía que cubra commits durables y confirmación al cliente.

## MTTR / restauración

El valor que escribe `falla.sh` es una estimación observacional, con un criterio de recuperación distinto por módulo: API, primer `GET /health` tras detener una réplica; MySQL, primer `POST` exitoso tras detener el primario y verificación de registros; Redis, promoción Sentinel y lectura del valor en el nuevo primario. No equivale al instante exacto en que cada cliente recuperó todas sus operaciones. El trap intenta reponer todos los nodos del stack; confirme estado con `docker compose ps`, `/api/status`, `SENTINEL master ha-cache` y `performance_schema.replication_group_members`. No borre volúmenes. Si el iniciador de DB falla tras una reinicialización, preserve logs y diagnostique antes de repetir.

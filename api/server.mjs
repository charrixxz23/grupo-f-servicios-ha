import http from 'node:http';
import os from 'node:os';
import crypto from 'node:crypto';
import mysql from 'mysql2/promise';
import Redis from 'ioredis';

const port = Number(process.env.PORT || 3000);
const sentinels = (process.env.REDIS_SENTINELS || '').split(',').filter(Boolean).map(v => { const [host, p] = v.split(':'); return { host, port: Number(p) }; });
const redis = new Redis({ sentinels, name: process.env.REDIS_MASTER_NAME || 'ha-cache', password: process.env.REDIS_PASSWORD, sentinelPassword: process.env.REDIS_PASSWORD, sentinelRetryStrategy: n => Math.min(n * 250, 3000), retryStrategy: n => Math.min(n * 100, 2000), maxRetriesPerRequest: 2, enableReadyCheck: true });
const mysqlNodes = (process.env.MYSQL_NODES || 'mysql1:3306,mysql2:3306,mysql3:3306').split(',').map(value => { const [host, p] = value.split(':'); return { host, port: Number(p || 3306) }; });
const mysqlOptions = { user: process.env.MYSQL_USER || 'ha_app', password: process.env.MYSQL_PASSWORD, database: process.env.MYSQL_DATABASE || 'ha_lab', connectTimeout: 2000, enableKeepAlive: true, keepAliveInitialDelay: 0 };
let pool = null, writerHost = null, writerExpiresAt = 0, discoveringWriter = null;
async function getWriterPool(force = false) {
  if (!force && pool && Date.now() < writerExpiresAt) return pool;
  if (discoveringWriter) return discoveringWriter;
  discoveringWriter = (async () => {
    for (const node of mysqlNodes) {
      let connection;
      try {
        connection = await mysql.createConnection({ ...mysqlOptions, host: node.host, port: node.port });
        const [rows] = await connection.query('SELECT @@global.read_only AS read_only, @@global.report_host AS hostname');
        if (Number(rows[0].read_only) === 0) {
          if (!pool || writerHost !== node.host) {
            const oldPool = pool; pool = mysql.createPool({ ...mysqlOptions, host: node.host, port: node.port, waitForConnections: true, connectionLimit: 12, queueLimit: 50 }); writerHost = node.host;
            if (oldPool) void oldPool.end().catch(() => {});
          }
          writerExpiresAt = Date.now() + 2000;
          return pool;
        }
      } catch {}
      finally { if (connection) await connection.end().catch(() => {}); }
    }
    throw new Error('No writable MySQL InnoDB Cluster member found');
  })();
  try { return await discoveringWriter; }
  finally { discoveringWriter = null; }
}
async function dbRun(method, sql, params = []) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt++) {
    try { const activePool = await getWriterPool(attempt > 0); return await activePool[method](sql, params); }
    catch (err) {
      lastError = err; const oldPool = pool; pool = null; writerHost = null; writerExpiresAt = 0;
      if (oldPool) await oldPool.end().catch(() => {});
      if (attempt < 2) await new Promise(resolve => setTimeout(resolve, 200 * (attempt + 1)));
    }
  }
  throw lastError;
}
let dbReady = false;
async function initDb() {
  for (let attempt = 1; attempt <= 90; attempt++) {
    try {
      await dbRun('query', `CREATE TABLE IF NOT EXISTS records (id VARCHAR(100) PRIMARY KEY, value TEXT NOT NULL, created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6))`);
      dbReady = true; return;
    } catch (err) { if (attempt === 90) console.error(`Database initialization did not complete (${err.code || 'error'})`); await new Promise(r => setTimeout(r, 2000)); }
  }
}
void initDb();
const json = (res, status, body) => { const data = JSON.stringify(body); res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data), 'cache-control': 'no-store' }); res.end(data); };
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'GET' && (url.pathname === '/health' || url.pathname === '/health/live')) return json(res, 200, { status: 'ok', replica: os.hostname(), pid: process.pid });
  if (req.method === 'GET' && url.pathname === '/health/ready') {
    try { await redis.ping(); await dbRun('query', 'SELECT 1'); return json(res, 200, { status: 'ready', replica: os.hostname(), mysql: true, redis: true }); }
    catch { return json(res, 503, { status: 'not_ready', replica: os.hostname() }); }
  }
  if (req.method === 'GET' && url.pathname === '/api/status') {
    let db = false, cache = false, dbPrimary = null, redisPrimary = null;
    try { const [rows] = await dbRun('query', 'SELECT @@global.report_host AS hostname, @@global.read_only AS read_only'); db = true; dbPrimary = rows[0]; } catch {}
    try { const info = await redis.info('replication'); cache = true; redisPrimary = info.split('\r\n').find(x => x.startsWith('role:'))?.slice(5); } catch {}
    return json(res, 200, { replica: os.hostname(), pid: process.pid, mysql: db, mysqlNode: dbPrimary, redis: cache, redisRole: redisPrimary });
  }
  if (req.method === 'POST' && url.pathname === '/api/records') {
    let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 65536) return json(res, 413, { error: 'body too large' }); }
    let input; try { input = JSON.parse(body); } catch { return json(res, 400, { error: 'invalid JSON' }); }
    const id = String(input.id || crypto.randomUUID()); const value = String(input.value ?? '');
    if (!id || id.length > 100 || value.length > 10000) return json(res, 400, { error: 'invalid id or value' });
    try {
      await dbRun('execute', 'INSERT INTO records(id,value) VALUES(?,?) ON DUPLICATE KEY UPDATE value=VALUES(value)', [id, value]);
      try { await redis.set(`record:${id}`, value); } catch {}
      return json(res, 201, { id, value, replica: os.hostname(), persisted: true });
    } catch (err) { return json(res, 503, { error: 'database temporarily unavailable', code: err.code || 'DB_ERROR', replica: os.hostname() }); }
  }
  if (req.method === 'GET' && url.pathname.startsWith('/api/records/')) {
    const id = decodeURIComponent(url.pathname.slice('/api/records/'.length));
    try { const [rows] = await dbRun('execute', 'SELECT id,value,created_at,updated_at FROM records WHERE id=?', [id]); if (!rows.length) return json(res, 404, { error: 'not found' }); return json(res, 200, { ...rows[0], replica: os.hostname() }); }
    catch (err) { return json(res, 503, { error: 'database temporarily unavailable', code: err.code || 'DB_ERROR' }); }
  }
  if (req.method === 'GET' && url.pathname === '/api/cache') { try { const value = await redis.get(url.searchParams.get('key') || 'demo'); return json(res, 200, { value, redisRole: await redis.info('replication').then(s => s.match(/role:(\w+)/)?.[1]), replica: os.hostname() }); } catch { return json(res, 503, { error: 'cache temporarily unavailable' }); } }
  if (req.method === 'PUT' && url.pathname === '/api/cache') { let body=''; for await (const c of req) body += c; let x; try { x=JSON.parse(body); } catch { return json(res,400,{error:'invalid JSON'}); } try { await redis.set(String(x.key || 'demo'), String(x.value ?? '')); const replicasAcknowledged = await redis.wait(2, 1500); if (replicasAcknowledged < 2) return json(res,503,{error:'replica acknowledgement timed out',stored:true,replicasAcknowledged}); return json(res,200,{stored:true,replicasAcknowledged,replica:os.hostname()}); } catch { return json(res,503,{error:'cache temporarily unavailable'}); } }
  json(res, 404, { error: 'not found' });
});
server.listen(port, '0.0.0.0');
process.on('SIGTERM', () => { server.close(() => { if (pool) void pool.end(); redis.disconnect(); process.exit(0); }); setTimeout(() => process.exit(1), 5000).unref(); });

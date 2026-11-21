import fs from 'node:fs';
import os from 'node:os';
const target = process.env.TARGET || 'http://lb:8080';
const durationMs = Number.parseInt(process.env.DURATION || '30s') * (String(process.env.DURATION || '30s').endsWith('s') ? 1000 : 1);
const concurrency = Number(process.env.CONCURRENCY || 25);
const replicas = Number(process.env.REPLICAS || 3);
const warmUntil = Date.now() + 3000;
while (Date.now() < warmUntil) {
  try { const r = await fetch(`${target}/api/status`, {signal: AbortSignal.timeout(3000)}); await r.arrayBuffer(); } catch {}
}
const stopAt = Date.now() + durationMs;
const times = []; let requests = 0, errors = 0, non2xx = 0;
await Promise.all(Array.from({length: concurrency}, async () => {
  while (Date.now() < stopAt) {
    const start = performance.now();
    try { const response = await fetch(`${target}/api/status`, { signal: AbortSignal.timeout(5000) }); await response.arrayBuffer(); if (!response.ok) non2xx++; }
    catch { errors++; }
    times.push(performance.now() - start); requests++;
  }
}));
times.sort((a,b)=>a-b);
const pct = p => times[Math.min(times.length - 1, Math.max(0, Math.ceil(times.length * p) - 1))] || 0;
const result = {timestamp:new Date().toISOString(),target,duration_s:durationMs/1000,concurrency,replicas,requests,rps:requests/(durationMs/1000),errors,non2xx,mean_ms:times.reduce((a,b)=>a+b,0)/(times.length||1),p50_ms:pct(.5),p95_ms:pct(.95),p99_ms:pct(.99),max_ms:times.at(-1)||0,host:os.hostname()};
fs.mkdirSync('/results/raw',{recursive:true});
const name = process.env.RESULT_NAME || `load_${replicas}rep_${Date.now()}`;
fs.writeFileSync(`/results/raw/${name}.json`,JSON.stringify(result,null,2)+'\n');
const header='timestamp,target,duration_s,concurrency,replicas,requests,rps,errors,non2xx,mean_ms,p50_ms,p95_ms,p99_ms,max_ms\n';
const row=[result.timestamp,result.target,result.duration_s,result.concurrency,result.replicas,result.requests,result.rps,result.errors,result.non2xx,result.mean_ms,result.p50_ms,result.p95_ms,result.p99_ms,result.max_ms].join(',')+'\n';
fs.writeFileSync(`/results/raw/${name}.csv`,header+row);
console.log(JSON.stringify(result,null,2));

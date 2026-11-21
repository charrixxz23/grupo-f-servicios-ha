import csv, glob, json, statistics, sys
n = sys.argv[1] if len(sys.argv)>1 else 'all'
data=[]
for p in sorted(glob.glob('results/raw/scale*_rep*.json')):
 with open(p, encoding='utf-8') as f: d=json.load(f)
 if n == 'all' or str(d.get('replicas')) == n: data.append(d)
if not data: raise SystemExit('No hay resultados para resumir; ejecute load.sh.')
fields=['replicas','runs','mean_rps','mean_latency_ms','mean_p95_ms','mean_p99_ms','mean_errors','mean_non2xx']
groups={}
for d in data: groups.setdefault(d['replicas'], []).append(d)
rows=[]
for replicas,items in sorted(groups.items()): rows.append({'replicas':replicas,'runs':len(items),'mean_rps':statistics.mean(x['rps'] for x in items),'mean_latency_ms':statistics.mean(x['mean_ms'] for x in items),'mean_p95_ms':statistics.mean(x['p95_ms'] for x in items),'mean_p99_ms':statistics.mean(x['p99_ms'] for x in items),'mean_errors':statistics.mean(x['errors'] for x in items),'mean_non2xx':statistics.mean(x['non2xx'] for x in items)})
with open('results/summary.csv','w',newline='',encoding='utf-8') as f:
 w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
print(','.join(fields))
for x in rows: print(','.join(str(x[k]) for k in fields))

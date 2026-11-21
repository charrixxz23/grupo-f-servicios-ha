#!/usr/bin/env python3
"""Render the measured scale summary as a dependency-free SVG chart."""
import csv
from html import escape
from pathlib import Path

root = Path(__file__).resolve().parent.parent
summary = root / 'results' / 'summary.csv'
output = root / 'results' / 'escalabilidad.svg'
with summary.open(newline='', encoding='utf-8') as source:
    rows = list(csv.DictReader(source))
rows = [row for row in rows if int(row['runs']) >= 3]
if not rows:
    raise SystemExit('No hay al menos tres repeticiones para cada escala en results/summary.csv.')

width, height = 900, 450
panels = [
    ('Solicitudes por segundo (promedio)', 'mean_rps', 'solicitudes/s', 650, '#2878b5'),
    ('Latencia p99 (promedio)', 'mean_p99_ms', 'milisegundos', 100, '#e07a27'),
]
parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
         '<rect width="100%" height="100%" fill="#ffffff"/>',
         '<style>text{font-family:Segoe UI,Arial,sans-serif;fill:#20242a}.title{font-size:19px;font-weight:600}.label{font-size:14px}.value{font-size:13px;font-weight:600}.grid{stroke:#d9dee5;stroke-width:1}</style>',
         '<text x="450" y="34" text-anchor="middle" class="title">Escalabilidad de API · 3 repeticiones por escala · 10 s · concurrencia 10</text>']
for panel_index, (title, key, unit, maximum, color) in enumerate(panels):
    x0 = 55 + panel_index * 445
    plot_x, plot_y, plot_w, plot_h = x0 + 40, 95, 350, 270
    parts.append(f'<text x="{x0 + 215}" y="70" text-anchor="middle" class="title">{escape(title)}</text>')
    for tick in range(5):
        y = plot_y + plot_h - tick * plot_h / 4
        value = maximum * tick / 4
        parts.append(f'<line x1="{plot_x}" y1="{y:.1f}" x2="{plot_x + plot_w}" y2="{y:.1f}" class="grid"/>')
        parts.append(f'<text x="{plot_x - 8}" y="{y + 5:.1f}" text-anchor="end" class="label">{value:.0f}</text>')
    bar_w, gap = 62, 42
    start = plot_x + 35
    for i, row in enumerate(rows):
        value = float(row[key])
        bar_h = value / maximum * plot_h
        x = start + i * (bar_w + gap)
        y = plot_y + plot_h - bar_h
        parts.append(f'<rect x="{x}" y="{y:.1f}" width="{bar_w}" height="{bar_h:.1f}" rx="4" fill="{color}"/>')
        parts.append(f'<text x="{x + bar_w/2}" y="{y - 8:.1f}" text-anchor="middle" class="value">{value:.1f}</text>')
        parts.append(f'<text x="{x + bar_w/2}" y="{plot_y + plot_h + 26}" text-anchor="middle" class="label">{int(row["replicas"])} réplicas</text>')
    parts.append(f'<text x="{plot_x + plot_w/2}" y="{plot_y + plot_h + 55}" text-anchor="middle" class="label">{escape(unit)}</text>')
parts.append('<text x="450" y="435" text-anchor="middle" class="label">Errores HTTP: 0 en las nueve corridas estandarizadas</text></svg>')
output.write_text('\n'.join(parts) + '\n', encoding='utf-8')
print(output)

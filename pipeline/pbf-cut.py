#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cuts data/osm/ba.json (roads), ba-rail.json (subte + premetro) and
ba-tren-rail.json (the suburban railways) out of the Geofabrik
argentina-latest.osm.pbf — the same JSON shape Overpass returns ('elements':
ways with tags, node ids and geometry), so build.mjs cannot tell the
difference. Written 7.09.2026 when overpass-api.de served the 25 road tiles
at one every few minutes; the boxes are the ones download.sh queries.
Files that already exist are left alone.
"""
import json, os, re, sys
import osmium

ROOT = os.path.join(os.path.dirname(__file__), '..')
PBF = os.path.join(ROOT, 'data', 'argentina-latest.osm.pbf')
HW = re.compile(r'^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$')
# name, file, box (S, W, N, E), tag test
JOBS = [
    ('roads', 'ba.json', (-35.15, -59.05, -34.05, -57.75), lambda t: (t.get('highway') or '') and HW.match(t.get('highway'))),
    ('subte + premetro', 'ba-rail.json', (-34.71, -58.56, -34.52, -58.33), lambda t: re.match(r'^(subway|tram|light_rail|construction|disused)$', t.get('railway') or '')),
    ('trenes', 'ba-tren-rail.json', (-36.00, -59.60, -34.05, -57.80), lambda t: re.match(r'^(rail|light_rail|construction|disused)$', t.get('railway') or '')),
]
jobs = [j for j in JOBS if not os.path.exists(os.path.join(ROOT, 'data/osm', j[1]))]
print('do zrobienia:', [j[0] for j in jobs], flush=True)
if not jobs:
    sys.exit(0)
if not os.path.exists(PBF):
    sys.exit(f'brak {PBF}')
os.makedirs(os.path.join(ROOT, 'data/osm'), exist_ok=True)
FS = min(j[2][0] for j in jobs); FW = min(j[2][1] for j in jobs); FN = max(j[2][2] for j in jobs); FE = max(j[2][3] for j in jobs)
out = {j[1]: [] for j in jobs}


class H(osmium.SimpleHandler):
    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        hits = [j for j in jobs if j[3](tags)]
        if not hits:
            return
        geom, ids = [], []
        la0, la1, lo0, lo1 = 90.0, -90.0, 180.0, -180.0
        for n in w.nodes:
            try:
                lo, la = n.lon, n.lat
            except osmium.InvalidLocationError:
                continue
            ids.append(n.ref)
            geom.append({'lat': la, 'lon': lo})
            if la < la0: la0 = la
            if la > la1: la1 = la
            if lo < lo0: lo0 = lo
            if lo > lo1: lo1 = lo
        if len(geom) < 2 or la1 < FS or la0 > FN or lo1 < FW or lo0 > FE:
            return
        el = {'type': 'way', 'id': w.id, 'nodes': ids, 'tags': tags, 'geometry': geom}
        for name, f, (s, w_, n_, e), _ in hits:
            if la1 >= s and la0 <= n_ and lo1 >= w_ and lo0 <= e:
                out[f].append(el)


print('czytam', os.path.basename(PBF), flush=True)
H().apply_file(PBF, locations=True, idx='flex_mem')
for name, f, _, _ in jobs:
    json.dump({'version': 0.6, 'generator': 'pbf-cut.py (Geofabrik argentina-latest)', 'elements': out[f]}, open(os.path.join(ROOT, 'data/osm', f), 'w'))
    print(f'{name}: {len(out[f])} ways -> {f}', flush=True)
print('gotowe', flush=True)

#!/usr/bin/env bash
# Downloads input data: the three Buenos Aires GTFS feeds, OSM networks
# (Overpass), MapLibre GL. Everything is cached — re-running only fetches what
# is missing.
#
# THREE feeds, because three authorities publish them:
#   colectivos  the AMBA bus network — 1052 route entries, 192 operators
#   subte       Subte A–H and the two Premetro lines (SBASE)
#   trenes      the seven suburban railways (Trenes Argentinos)
# All three come from the city's transport API portal, data.buenosaires.gob.ar.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs-bus data/gtfs-subte data/gtfs-tren data/osm/tiles web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too (Brașov, 16.08.2026: a 65 kB
# fragment containing the string was taken for a finished download and the city
# was silently skipped). The floor is per-extract: a road tile runs to tens of
# thousands of ways, the whole Subte to a few hundred.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

# 1) GTFS — the three feeds
if [ ! -f data/gtfs-bus/routes.txt ]; then
  echo "== GTFS colectivos =="
  curl -fL --retry 3 --max-time 1800 -o data/ba-bus.zip \
    "https://cdn.buenosaires.gob.ar/datosabiertos/datasets/transporte-y-obras-publicas/colectivos/gtfs.zip"
  unzip -o data/ba-bus.zip -d data/gtfs-bus
fi
if [ ! -f data/gtfs-subte/routes.txt ]; then
  echo "== GTFS subte =="
  curl -fL --retry 3 --max-time 600 -o data/ba-subte.zip \
    "https://cdn.buenosaires.gob.ar/datosabiertos/datasets/sbase/subte-viajes-molinetes/subte_gtfs.zip"
  unzip -o data/ba-subte.zip -d data/gtfs-subte
fi
if [ ! -f data/gtfs-tren/routes.txt ]; then
  echo "== GTFS trenes =="
  curl -fL --retry 3 --max-time 600 -o data/ba-tren.zip \
    "https://cdn.buenosaires.gob.ar/datosabiertos/datasets/transporte-y-obras-publicas/trenes/trenes-gtfs.zip"
  unzip -o data/ba-tren.zip -d data/gtfs-tren
fi

# 2) OSM roadways — a 5 × 5 grid of tiles over a 60 km radius around the
#    Obelisk, which holds 98.7 % of the 43 594 stops. The far tail (one line
#    reaches Tandil, 238 km out) is deliberately outside: a bbox that held it
#    would be 127 × 300 km of road network for a handful of runs.
#    Small tiles are not an optimisation but a requirement — Overpass returns
#    504 on anything large, and the mirrors rate-limit a fast loop, so the
#    pauses below matter as much as the tiling.
if [ ! -f data/osm/ba.json ]; then
  echo "== Overpass (roads, 25 tiles) =="
  HW='^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$'
  LATS=(-35.15 -34.93 -34.71 -34.49 -34.27 -34.05)
  LONS=(-59.05 -58.79 -58.53 -58.27 -58.01 -57.75)
  i=0; ok_all=1
  for r in 0 1 2 3 4; do
    for c in 0 1 2 3 4; do
      i=$((i+1))
      # 20 is the floor, not 2000: tiles 14, 15, 19 and 23 lie mostly over the
      # Río de la Plata and hold under 200 ways each — a higher floor rejects
      # a perfectly good answer
      ok_json "data/osm/tiles/t$i.json" 20 && continue
      Q="[out:json][timeout:300];way(${LATS[$r]},${LONS[$c]},${LATS[$((r+1))]},${LONS[$((c+1))]})[\"highway\"~\"$HW\"];out geom;"
      got=0
      for pass in 1 2 3; do
        echo "-- tile $i/25, pass $pass"
        curl -sS --max-time 300 -o "data/osm/tiles/t$i.json" --data-urlencode "data=$Q" \
          "https://overpass-api.de/api/interpreter" 2>/dev/null
        ok_json "data/osm/tiles/t$i.json" 20 && { got=1; break; }
        rm -f "data/osm/tiles/t$i.json"; sleep 60
      done
      [ "$got" = 1 ] || ok_all=0
      sleep 20
    done
  done
  [ "$ok_all" = 1 ] || { echo "Overpass (roads): tiles failed" >&2; exit 1; }
  node -e '
    const fs = require("fs");
    const seen = new Set(); const els = [];
    for (let i = 1; i <= 25; i++) {
      for (const e of JSON.parse(fs.readFileSync(`data/osm/tiles/t${i}.json`)).elements) {
        if (!seen.has(e.id)) { seen.add(e.id); els.push(e); }
      }
    }
    fs.writeFileSync("data/osm/ba.json", JSON.stringify({ version: 0.6, elements: els }));
    console.log(`roads merged: ${els.length} ways`);
  '
fi

# 2b) OSM — Subte tunnels and the Premetro tracks, over the city proper.
if [ ! -f data/osm/ba-rail.json ]; then
  echo "== Overpass (subte + premetro) =="
  QS='[out:json][timeout:300];way(-34.71,-58.56,-34.52,-58.33)["railway"~"^(subway|tram|light_rail|construction|disused)$"];out geom;'
  curl -sS --max-time 300 -o data/osm/ba-rail.json --data-urlencode "data=$QS" \
    "https://overpass-api.de/api/interpreter"
  ok_json data/osm/ba-rail.json 100 || { rm -f data/osm/ba-rail.json; echo "Overpass (subte): failed" >&2; exit 1; }
fi

# 2c) OSM — the suburban railways, over a far wider box than the roads: Roca
#     runs to Chascomús 120 km south and Mitre to Zárate 90 km north. A
#     rail-only query stays light even over 220 × 160 km.
if [ ! -f data/osm/ba-tren-rail.json ]; then
  echo "== Overpass (trenes) =="
  QT='[out:json][timeout:300];way(-36.00,-59.60,-34.05,-57.80)["railway"~"^(rail|light_rail|construction|disused)$"];out geom;'
  curl -sS --max-time 300 -o data/osm/ba-tren-rail.json --data-urlencode "data=$QT" \
    "https://overpass-api.de/api/interpreter"
  ok_json data/osm/ba-tren-rail.json 500 || { rm -f data/osm/ba-tren-rail.json; echo "Overpass (trenes): failed" >&2; exit 1; }
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/osm/ba.json data/osm/ba-rail.json data/osm/ba-tren-rail.json 2>/dev/null || true

# Buenos Aires Public Transport — interactive map

Interactive, poster-grade map of the public transport network of **Buenos
Aires**: the AMBA colectivos, the Subte and Premetro, and the suburban
railways — 302 lines and **53 506 km** of drawn network, the largest of the
family by a wide margin.

## Live

Not published yet — this map is built and reviewed locally.

Three feeds, because three authorities publish them, split into four cfgs:

| mode | source | lines | graph |
|---|---|---|---|
| colectivos | AMBA bus feed, 192 operators | 288 líneas | OSM roadways |
| Subte | SBASE | A, B, C, D, E, H in their official colours | `railway=subway` |
| Premetro | SBASE | PM-C, PM-S | tram tracks |
| trenes | Trenes Argentinos | Mitre, Roca, Sarmiento, San Martín, Belgrano Sur, Tren de la Costa | mainline rail |

Build quirks worth knowing:

* **Every ramal is drawn, not one route per line.** A *línea* is a trunk that
  fans out into branches: 96 has 35 of them, 60 has 20, 620 has 19, and 199 of
  the 292 line numbers branch at all. The sibling maps draw one representative
  run per (line, direction) because a line there has one route with the odd
  short-turn; doing that here would show a third of the city's coverage while
  looking complete. So all **2 066 shapes** are drawn under the same 292 line
  numbers — a ramal is not a separate line to a passenger, it is the same
  number with a different tail.
* **1 052 route entries, 292 line numbers.** The key is the leading digits;
  the 18 lettered services (AZUL1, ROJA, VERDE, NORTE11, OE16V, SUR10…) keep
  their names.
* **Four lines are deliberately outside the map: AZUL1, AZUL2, ROJA and
  VERDE.** They are the town buses of Junín — 232 to 238 km from the Obelisk —
  which the AMBA feed carries in the same bundle. The road extract covers a
  60 km radius, which holds 98.7 % of the 43 594 stops; a bbox that reached
  Junín would be 127 × 300 km of road network for four lines. The same applies
  to ramal 276I, which runs out to 134 km. They are absent, not broken.
* **The metro predicate is cfg membership, not a name test.** The family asks
  whether a line matches `/^M[0-9]/`, which is no use where the metro is
  lettered A–H — it would either miss every Subte line or swallow a colectivo.
  Here the metro cfg fills a key set and the downstream tests read that.
* **Spanish is written in the Latin alphabet**, so this map runs without the
  second, transliterated label line its Greek, Bulgarian and Serbian siblings
  carry.

Numbers from the build: median matching error 2.0 m, 95th percentile 3.5 m,
worst 22.2 m across 2 129 runs; 584 breaks and 37 917 raw metres, which is
0.07 % of the network.

## Pipeline

`npm run download` fetches the three GTFS feeds, the OSM roadways in a 5 × 5
grid of tiles and the two rail extracts. The tiling is a requirement, not an
optimisation: Overpass returns 504 on anything large and rate-limits a fast
loop, so the pauses matter as much as the tile size. Two tiles over the Río de
la Plata hold under 200 ways each, which is why the acceptance floor is 20 and
not 2 000.

`npm run build` map-matches every line (HMM/Viterbi on a graph of 1 067 912
road segments) and writes GeoJSON to `data/out/`. It takes about 13 minutes.
`npm run serve` hosts the map at http://localhost:8149.

Data: Buenos Aires Ciudad open data (colectivos, SBASE, Trenes Argentinos) ·
base map © OpenFreeMap / OpenMapTiles / OpenStreetMap contributors.

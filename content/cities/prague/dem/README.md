# Praha – výšky (DEM mimo git)

Tento adresář je v `.gitignore` (kromě tohoto souboru). `citypack` krok `elevation` čte první
`*.asc`, pokud `city.yaml` má `elevation_sources: [local, …]` (`docs/citypack.md`, Terén).

## Stav (2026-11-23)
Balíček Prahy staví z **AWS Terrain Tiles** (EU-DEM/SRTM, ~25 m, povrchový model,
`elevation_is_bare_earth: false`). Lokální mřížka zatím není: ČÚZK DMR 4G i 5G jsou jen mračna bodů
LAZ v S-JTSK a na stroji, kde se balíček staví, chybí PDAL/GDAL.

## Zdroj
- ČÚZK DMR 5G (holý terén, ~1 m), ATOM po listech SM5: `https://atom.cuzk.gov.cz/DMR5G-SJTSK/DMR5G-SJTSK.xml`
  (nebo DMR 4G, mřížka 5 m: `https://atom.cuzk.gov.cz/DMR4G-SJTSK/DMR4G-SJTSK.xml`).
- Licence: otevřená data ČÚZK, CC BY 4.0, uvádět „© ČÚZK“ (ATOM: „žádné podmínky neplatí“).
- Výřez: listy SM5 pokrývající `content/cities/prague/area.geojson` + 500 m (Praha 1, 2, Letná,
  Holešovice, Karlín, Žižkov, Vinohrady, Smíchov, Vyšehrad). Listy najde OpenSearch služby
  (`OSD-DMR5G-SJTSK.xml`) podle bboxu, nebo `georss:polygon` u položek feedu.

## Převod (PDAL + GDAL)
```
brew install pdal gdal
# 1. Stáhnout ZIPy listů z datasetFeeds/…_<LIST>.xml a rozbalit *.laz do jednoho adresáře.
# 2. Body holého terénu (třída 2) na mřížku 2 m v S-JTSK:
pdal pipeline - <<'EOF'
[ {"type":"readers.las","filename":"laz/*.laz","override_srs":"EPSG:5514"},
  {"type":"filters.range","limits":"Classification[2:2]"},
  {"type":"writers.gdal","filename":"dmr_sjtsk.tif","resolution":2,"output_type":"idw","window_size":3} ]
EOF
# 3. Do WGS84 jako ESRI ASCII grid (≈ 2 m):
gdalwarp -t_srs EPSG:4326 -tr 0.00003 0.00002 -r bilinear dmr_sjtsk.tif dmr_wgs84.tif
gdal_translate -of AAIGrid dmr_wgs84.tif content/cities/prague/dem/prague_dmr.asc
```
Pak v `city.yaml`: `elevation_sources: [local]`, `elevation_is_bare_earth: true` a v
`internal/dem/doc.go` / `pack.go` atribuce „Výšky: © ČÚZK, DMR 5G (CC BY 4.0)“. Postavit
`citypack -force build prague` a porovnat náhled `preview/prague_relief.png`.

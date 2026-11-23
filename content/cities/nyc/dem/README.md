# New York – výšky (DEM mimo git)

Tento adresář je v `.gitignore` (kromě tohoto souboru). `citypack` krok `elevation` čte první
`*.asc`, pokud `city.yaml` má `elevation_sources: [local, …]` (`docs/citypack.md`, Terén).

## Stav (2026-11-23)
Balíček staví z **AWS Terrain Tiles** (USGS 3DEP 1/3″, veřejné dílo, holý terén):
`elevation_sources: [terrain_tiles]`. Dlaždice se cachují v `run/citypack/nyc/tiles/`.

## Lepší zdroj (licence neověřená)
- NYC 1 foot DEM (2010 lidar, holý terén, hydro-flattened), NYC Open Data `dpc8-z3jc`
  (integer raster, zip ~3,3 GB). Podmínky: NYC Open Data Terms of Use; výslovná licence u datasetu
  chybí (`plans/M5_TEREN_PRIRODA.md`, Zdroje). Dokud ji Ol1n neschválí, nepoužívat.

## Převod (GDAL), až bude licence ověřená
```
brew install gdal
# výřez = bbox content/cities/nyc/area.geojson + 500 m (<W> <S> <E> <N> ve stupních),
# převzorkování na ~2 m a WGS84 jako ESRI ASCII grid
gdalwarp -t_srs EPSG:4326 -te <W> <S> <E> <N> -tr 0.000024 0.000018 -r bilinear \
  <stažený DEM> nyc_dem_wgs84.tif
gdal_translate -of AAIGrid nyc_dem_wgs84.tif content/cities/nyc/dem/nyc_dem.asc
```
Pak `elevation_sources: [local, terrain_tiles]` (čte se první dostupný zdroj, takže dlaždice
zůstanou jen jako záloha), `elevation_is_bare_earth: true` a `citypack -force build nyc`.

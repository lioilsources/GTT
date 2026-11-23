# M5 – Terén, voda a zeleň, plynulá jízda (pod-plán)

Zadání Ol1na 2026-11-23: „přidal jsem další plány do Prompts/02–04 přidávající nové věci k už
existujícím, až dokončíš to, na čem teď pracuješ, implementuj plán pro obě města, pokračuj
Tokiem“. Zdroje: `Prompts/02-METROPOLE_TERRAIN_PLAN.md` (terén), `03-METROPOLE_NATURE_PLAN.md`
(voda a zeleň), `04-METROPOLE_FLOW_PLAN.md` (plynulá jízda; má přednost před 02 a 03).
Navazuje na M2 (minihry S9 dobíhají), M3 (Praha) a M4 (Tokio).

**Cíl:** New York, Praha a pak Tokio mají skutečný reliéf, vodu a zeleň se stromy; jízda je
plynulá – strom zpomalí, zeď navede, zaseknuté auto se samo vyprostí.

Specifikace: `specs/terrain.md`, `specs/nature.md`, `specs/flow.md` (v1). Čísla
`content/tuning.yaml` → `terrain`, `slope_physics`, `camera.topdown`, `camera.chase`, `nature`,
`flow`; barvy `design/tokens.json` → `color.water`, `color.green`; texty `flowToRoad`,
`flowStuck10`, `terrainGrade`, `terrainAltitude`, `natureTow`, `cameraChase`, `cameraTopdown`.

## Výchozí volby (dokud Ol1n neřekne jinak)
| # | Otázka | Default |
|---|---|---|
| K1 | Výchozí kamera | A: shora v obou klientech, šikmo jako přepínač ve W |
| K2 | Převýšení terénu | 2,0, doladit v T3 |
| K3 | První kopcovité město | Praha |
| K4 | Poškozují skoky auto? | ne, jen ztráta rychlosti |
| V1 | Les | průjezdný (rozhodnuto plánem FLOW, F1) |
| V2 | Lodě | v N2 |
| V3 | Jména vody a parků | místní jazyk (Tokio: Hepburn, `specs/cities.md` přepis jako u silnic) |
| V4 | Roční období | ne |
| P1 | Stromy | všechny měkké |
| P2 | Zpomalení v lese | 60 % |
| P3 | Limit zaseknutí | 1 za 10 minut |
| — | Referenční auto scénářů | `sedan_regent` (plán uvádí `sedan_01`, takové v repu není) |

## Kroky (v tomto pořadí, každý samostatná feature: sdílená vrstva → W a F → parita)

| Id | Fáze | Obsah | Akceptace |
|---|---|---|---|
| **M5-S1** | FL1 | **Nárazy a vyproštění v obou klientech** (`specs/flow.md`: zeď – klouzání a odraz, stopa, automatické vyproštění 8 m / 20 m / silnice, tlačítko „Na silnici“, počítadlo zaseknutí v ladicím overlay, `stuck.log`). Bez dat, hned. Parita F-069, scénáře `scenarios/flow/wall_30`, `wall_head_on`, `corner_3x` | scénáře se zdí v toleranci v obou klientech; ruční průjezd Midtownem bez zaseknutí |
| **M5-S2** | T0 | **Výšky v datech – New York**: krok `elevation` (dem → clean → profile → pins → exaggerate → grade_clamp → conform → shade), `lod`, pole v `.proto`, validate, preview (stínovaná mapa, 10 nejprudších ulic), testy na syntetickém terénu (rovina, kužel, hřeben, údolí s mostem) se zlatými výstupy | `citypack validate nyc` projde; náhled ukazuje nájezdy mostů a Uptown; balíček bez výšek dál funguje v obou klientech |
| **M5-S3** | N0 + FL0 | **Voda, zeleň a štěrbiny v datech – New York**: krok `nature` (classify, cut, trees, shore, labels, spots `area_name`, lod), stromy z 2015 Street Tree Census, uzavření štěrbin pod 7 m a `micro_only` uličky | náhled: Central Park má lesy, louky a vodu na správných místech, Hudson/East River/Harlem River mají jména, stromy podél ulic; validate bez stromu na silnici, v budově a ve vodě, počet uzavřených štěrbin vypsán |
| **M5-S4** | T0/N0/FL0 | **Praha**: DMR 5G (ČÚZK), stromy z pražských dat (viz Zdroje), Vltava a ostrovy, Petřín, Letná, Stromovka, Riegrovy sady | validate prague projde; žádná průjezdná ulice nad `max_grade`; pěší schodiště (např. Zámecké schody) jsou `stairs`, ne silnice |
| **M5-S5** | T0/N0/FL0 | **Tokio**: výšky z GSI (licence viz Zdroje) nebo AWS Terrain Tiles; Sumida, příkopy paláce, Ueno, Shiba park, Hama-rikyū | validate tokyo projde; balíček pod 40 MB |
| **M5-S6** | T1 | **Svahy a skoky v obou klientech** (`specs/terrain.md`: `groundZ`, síla svahu, skok, promítání ve F, nápovědy shora: stínování, šipky, stín auta, HUD sklon a výška, oddálení) | scénáře `scenarios/terrain/` v toleranci; kontrolní tabulka skoků v unit testu ±2 %; přejezd Brooklynského mostu je znát na rychlosti i obraze; 60 fps |
| **M5-S7** | N1 | **Voda a zeleň v obou klientech** shora (`specs/nature.md`: třídy, mělčina, jména, koruny s průhledností, povrchy a přilnavost, pád do vody a odtah, mapa v telefonu) | scénáře `scenarios/nature/`; slepý test 3 lidí: řeka a park do 2 s; 60 fps |
| **M5-S8** | FL2 | **Les a měkké stromy v obou klientech** (`specs/flow.md` kap. strom a les) | scénáře `forest_200`, `tree_head_on`; průjezd Central Parkem napříč lesem bez vyproštění |
| **M5-S9** | T2 + N2 | **Šikmý pohled ve W**: síť terénu, mosty a tunely s profilem, `lod` prstenec, voda k horizontu, zelené hmoty, lodě, přepínač kamery | 60 fps v šikmém pohledu na obou telefonech; přepnutí za jízdy bez záseku; z Brooklynského mostu je čitelná řeka i panorama |
| **M5-S10** | T3 | **Ladění kopců v Praze**: `exaggeration`, `gravity`, sklony; minihry z reliéfu (Sprint jako sjezd, Drift v serpentinách), vyhlídky jako fotomísta, razítko „nejprudší ulice“ | Ol1n potvrdí Petřín, Letnou a Hradčany |
| **M5-S11** | FL1 | **`metro stuckmap`** + počítadlo zaseknutí v `plans/progress.yaml` | mapa a top 10 z `stuck.log` |
| **M5-S12** | T4 | Šikmý pohled ve F | jen na zadání Ol1na po bráně G1 |

Akceptace milníku: M5-A1 validate všech tří měst s výškami a přírodou, M5-A2 scénáře terénu,
přírody a flow v toleranci v obou klientech, M5-A3 60 fps shora s reliéfem a stromy na obou
telefonech (šikmo ve W), M5-A4 nejvýš 1 zaseknutí za 10 minut (dogfooding Ol1n), M5-A5 Ol1n
potvrdí kopce Prahy, M5-A6 slepý test řeky a parku.

## Zdroje dat a licence (OVĚŘ = před kódem ověřit; stav hledání 2026-11-23)

| Zdroj | Pro | Licence / podmínky | Stav |
|---|---|---|---|
| NYC 1 foot DEM (2010 lidar, holý terén, hydro-flattened), NYC Open Data `dpc8-z3jc`; novější NYC Topobathymetric DEM 2017 (NYS GIS, `elevation.its.ny.gov`) | NYC výšky | NYC Open Data Terms of Use (veřejný přístup, data.gov ho vede jako „Non-Federal, jiné podmínky“); výslovná licence u datasetu chybí. Integer raster 3,3 GB zip | **OVĚŘ** podmínky na data.cityofnewyork.us; do té doby AWS Terrain Tiles (USGS 3DEP 1/3″ = veřejné dílo) |
| ČÚZK DMR 5G (ATOM služba po listech SM5, S-JTSK nebo ETRS89-TM, LAZ/body) | Praha výšky | otevřená data ČÚZK, **CC BY 4.0**, uvádět „© ČÚZK“ | ověřeno (podmínky ČÚZK); formát LAZ → potřeba převodu bodů na mřížku (PDAL nebo vlastní čtečka) |
| GSI 基盤地図情報 数値標高モデル 5m/10m | Tokio výšky | Pravidla GSI jsou kompatibilní s CC BY 4.0; redistribuce jako datové sady může vyžadovat souhlas podle zákona o zeměměřictví (Survey Act). Hotový balíček nese odvozenou mřížku 8 m, ne surová data | **OVĚŘ** u GSI, zda odvozená herní mřížka potřebuje souhlas; jinak AWS Terrain Tiles |
| AWS Terrain Tiles (Terrarium PNG, `s3.amazonaws.com/elevation-tiles-prod`) | záloha všude | otevřená data; atribuce podle zdrojů dlaždic (tilezen/joerd `attribution.md`: USGS 3DEP, SRTM, ETOPO1, GMTED, …) | ověřeno; atribuce na obrazovku „O mapách“ |
| Overture `base`: `water` (subtype river/ocean/lake/…, class; `physical` = jen popisky), `land` (subtype), `land_use` (subtype + class z OSM `landuse`), `land_cover` (subtype forest/grass/crop/… z ESA WorldCover) | voda, zeleň | ODbL (OSM) a CC BY 4.0 (ESA WorldCover); stejný režim jako ostatní mapová data | **OVĚŘ** přesné hodnoty class v release 2026-11-18.0 (DuckDB `SELECT DISTINCT subtype, class`) |
| NYC 2015 Street Tree Census (`uvpi-gqnh`): druh, průměr kmene, poloha, ~680 tis. stromů | NYC stromy | NYC Open Data Terms of Use; GBIF vede kopii jako CC0, město licenci výslovně neuvádí | **OVĚŘ** na data.cityofnewyork.us; pro atribuci „NYC Parks, 2015 Street Tree Census“ |
| Praha: sdílená data o zeleni (IPR Praha, centrální sklad z pasportů zeleně a dendrologických průzkumů), Golemio | Praha stromy | IPR open geodata CC BY („podkladová data © IPR Praha“); pokrytí stromů v open datech nejisté | **OVĚŘ** dataset stromů na geoportalpraha.cz / opendata.praha.eu; jinak OSM `natural=tree`, `tree_row` |
| Tokio stromy | Tokio | OSM body a stromořadí | Poissonův disk v parcích |

Atribuce každého použitého zdroje přibude na obrazovku „O mapách“ (`specs/passport.md`
Atribuce) se stejným PR, který zdroj zapojí.

## DEM mimo git
- `content/cities/<id>/dem/` je v `.gitignore`; `content/cities/<id>/dem/README.md` (v gitu)
  popisuje stažení: URL, dataset, výřez, převod. CI DEM nepotřebuje: balíčky se staví lokálně a
  publikují jako release jako dosud (`packs.lock`), `citypack build` bez DEM a bez dlaždic
  vynechá krok `elevation` a balíček je naplocho.
- `city.yaml`: `elevation_sources: [local, terrain_tiles]`, `elevation_is_bare_earth: true`.

## Kód dlaždic k převzetí
Plán odkazuje na „terrain-fetch v DoggioWars“; nástroj je ve skutečnosti
`/Users/ol1n/Dev/GitHub/MountainsSimulator/terrain-fetch` (Go 1.26, `package main`, Ol1nův kód).
Nejde importovat, proto se **portuje** do `tools/citypack/internal/dem/`:
- `fetch.go` – stahování Terrarium dlaždic s diskovou cache, workery, retry s backoffem
  (cache do `run/citypack/<city>/tiles/`)
- `tiles.go` – Web Mercator: `lonToPixelX`, `latToPixelY`, `metersPerPixel`, `tilesFor`,
  `autoZoom`
- `mosaic.go` – `decodeTerrarium` (výška = R·256 + G + B/256 − 32768), `mosaic`, `crop`,
  `resample` (Catmull-Rom)
- `preview.go` – `hillshade(g, mpp, azimut, výška)` pro pole `shade` i náhled
Přeskočí se Roblox/Lua/strips/colormap. Testy `terrain_test.go` (pixel math, decode, mosaic,
resample) se převezmou s nimi. Převzorkování na lokální projekci města (metry od `origin`) je nový
kód: pro každý bod 4m pracovní mřížky převod na lon/lat a bilineární vzorek mozaiky.

## Rizika
- Výkon F: promítání země každý snímek (rozpočet +2 ms, jinak mřížka 16 m pro kreslení).
- Šikmý pohled rozevírá rozdíl mezi klienty (P2, jen W) – podklad pro bránu G1.
- Konflikty barev: stávající palety měst padají do vyhrazených odstínů (`specs/nature.md`,
  tabulka konfliktů); `metro validate` zatím jen varuje, rozhodne Ol1n.
- Hrubá data: `clean`, vyhlazení profilu, ruční `deck_height_m` u ikonických mostů.
- Velikost balíčku: +~3,3 kB terénu a ≤ 1,8 kB stromů na chunk; Tokio (789 chunků) ~+4 MB.

## Stav (2026-11-23)
- Sdílená vrstva: plány v `Prompts/`, specifikace v1, tuning, tokeny, texty, parita F-069…F-074,
  položky M5 v `plans/progress.yaml`.
- Pořadí změněno: datové kroky M5-S2…S4 (jen sdílená vrstva, `tools/citypack`) šly před M5-S1,
  aby klienti dostali balíčky s výškami a přírodou hned (pole jsou přídavná, starý klient je
  ignoruje). M5-S1 a klientské kroky S6+ pokračují podle tabulky.
- M5-S2, M5-S3 hotovo: `citypack validate nyc` projde (AWS Terrain Tiles, 0 schodů, 61 764 stromů,
  9 080 uzavřených štěrbin), náhledy `preview/nyc_relief.png`, `nyc_nature.png`.
- M5-S4 čeká na Ol1na: `citypack validate prague` projde, 0 schodů (Mrázovka/Radlická vyřešená
  povolením mezí v okolí), ale výšky jsou z AWS Terrain Tiles (EU-DEM ~25 m), ne z DMR 5G: ČÚZK
  dává jen LAZ v S-JTSK a chybí PDAL/GDAL (`content/cities/prague/dem/README.md`). Stromy z OSM
  a Poissonova disku v parcích; pražský dataset stromů (IPR) zatím neověřen.
- Další krok: M5-S1 (FL1) ve W (vede) a F; po instalaci GDAL převod DMR 5G pro Prahu.

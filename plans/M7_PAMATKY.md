# M7 – Památky ve 3D (pod-plán)

Plán: `Prompts/06-METROPOLE_LANDMARKS3D_PLAN.md`. Spec: `specs/models.md` v1. Parita F-085.
Rozsah tohoto kola: jen `prague_castle` (areál Hradu s katedrálou sv. Víta, K4), fáze H0 → H2 ve W.
Defaulty kap. 11: bez textur (K2), F až po vystřelení (K3, K6).

## H0 – ověření dat (Praha, 2026-11-27)

| OVĚŘ | Zjištění |
|---|---|
| Kde se stahuje | ArcGIS Online, uživatel `opendatapraha` (portál opendata.geoportalpraha.cz). Každý mapový list 1 : 5000 má položku `BD3_Prah_<list>` typu GML (CityGML), vedle ní `_shp`, `_mp` (multipatch), `_dwg`, `_dgn`. Bez přihlášení, bez captchy: `https://www.arcgis.com/sharing/rest/content/items/<id>/data`. |
| Licence | CC BY 4.0, „data base © IPR Praha“ (stránka otevřených dat geoportalpraha.cz, `licenseInfo: CC BY` u položek). **Lze.** |
| List s Hradem | **Praha 7-1** (číslo 57-1; klad `MAP_CUR_MAP_ML_5000_P`), S-JTSK x −745 006 … −742 506, y −1 044 008 … −1 042 008. Celý areál včetně Pohořelce a Hradčanského náměstí leží v tomto jednom listu. Položka `88dc83fcd48c4ac9aec3532c19395d72`, upravená 2023-11-20. |
| Velikost | `BD3_Prah_7-1.gml` 172 481 904 B (172 MB, nekomprimované XML ISO-8859-1), sha256 `5d356c0a…dd04d50`. V `run/citypack/prague/raw/models/`, ne v gitu. |
| Souřadnice | S-JTSK / Křovák East North (EPSG:5514; v souboru `srsName="unknown"`), x, y záporné. Výšky Bpv (184–380 m v listu). WGS84 verze ke stažení není. Převod: polynom 2. stupně proložený PROJ (DuckDB `ST_Transform(..., 'EPSG:5514', <místní eqc>)`) na mřížce 5 × 5 přes obálku listu, reziduum 1 mm (afinní převod by měl 0,28 m). |
| Formát | Export CityGRID Manager 16. Plochy pod `lod3MultiSurface` (podrobné střechy), `lod3Solid` jsou jen odkazy xlink na tytéž polygony. List: 3 266 budov, 5 347 částí (`BuildingPart`), 3 220 instalací (`BuildingInstallation`: komíny, vikýře), 46 115 střešních, 77 128 stěnových a 8 092 základových ploch. `bldg:usage` na části: „sikma stresni plocha“, „vodorovna stresni plocha“, „vyznacna vez na strese“ (231×). |
| Jak je Hrad a katedrála | Katedrála je jedna budova `_70215` (pata 256,4–257,3 m Bpv, nejvyšší bod 90,3 m nad patou), věže a fiály jako části „vyznacna vez na strese“, střechy podrobně, stěny svisle od terénu. Areál Hradu = desítky samostatných budov (palác `_70087` s 1 498 trojúhelníky, západní křídlo `_70263`, Zlatá ulička, Černá věž …), každá s vlastní patou ve svahu. |
| Trojúhelníky Hradu | Výběr `content/cities/prague/models.yaml` (oblast areálu + budova památky + 2 m): 48 budov zdroje. Surově 6 702 trojúhelníků, po čištění (svaření 0,1 m, bez podlah, bez skupin pod 1,5 m) **6 231** – pod výjimkou 12 000 z kap. 8, nad výchozími 4 000 (proto `max_tris: 12000` v `models.yaml`). |
| `models.pb` Prahy | 56,8 kB po gzipu (limit 1,5 MB). Střešní plán 296 polygonů (limit 400), `replaces` 28 budov Overture. |
| Pata vs terén | Terén Prahy je zatím AWS Terrain Tiles (EU-DEM ~25 m, povrchový model) se silnicemi zarovnanými `conform`. Proti zemi zdroje (laser IPR) se na hraně hradního ostrohu rozchází o metry: pod katedrálou zdroj 256,4–257,3 m, DEM 248–253 m. Pata se proto staví jako u budov (žádný vrchol země nevisí, reliéf části převýšený jako terén); 12 z 48 částí je v mediánu zahrabaných víc než 2 m (nejvíc 10,1 m, jižní svah). `validate` to hlásí jako varování; zmizí s DMR 5G (M5-S4). |
| Karlův most | Mimo rozsah tohoto kola (mosty jsou v IPR samostatná sada „Mosty 3D“ za celou Prahu). |

Licence ostatních měst (kap. 4.1): v tomto kole neověřováno – New York **nejasné**, Tokio (PLATEAU,
PDL 1.0) **lze podle plánu, neověřeno v datech**, Moskva **nelze** (úřední model není, záloha Overture).
Doloží H0 pro H5/H6.

## H1 – pilot v datech

Krok `citypack models` (`tools/citypack/internal/steps/models.go`, čtečka `internal/citygml`),
`models.pb` v balíčku (`Manifest.models_version` 1, atribuce IPR), `validate` (rozpočty, indexy,
pata, vzdálenost od bodu památky, atribuce, `replaces`), náhled
`run/citypack/prague/preview/models/prague_castle.png` (plán shora a šikmo z jihozápadu).
Balíček bez `models.pb` dál funguje (klienti ho berou jako volitelný).

## H2 – šikmý pohled ve W

Viz `specs/models.md` (přepínání `near_m` s hysterezí, `replaces`, stíny ze střešního plánu, plán
shora). Snímky a čas snímku v PR webu.

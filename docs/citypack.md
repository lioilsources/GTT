# citypack – pipeline map

Go CLI (`tools/citypack`), každý krok jde spustit zvlášť a má cache v `run/citypack/<city>/`.
Geometrii počítá DuckDB přes CLI binárku (`duckdb`, rozšíření `spatial` a `httpfs`), takže Go zůstává
bez CGO a stejně se staví na Macu i na Sparku (ARM64). Cestu k binárce jde přepsat `DUCKDB=`.

## Kroky

Čísla pipeline (pruhy podle třídy, šířka uliček, zjednodušení, výškové pásy, prahy ploch) jsou v
`content/tuning.yaml` (`roads`, `buildings`, `ground`); chybějící klíč je chyba.

Cache nesleduje změny konfigurace: po úpravě `city.yaml`, `tuning.yaml` (šířky silnic) nebo
`landmarks.yaml` spusť `citypack -force build <city>` (stažená data zůstanou, `-refetch` je stáhne znovu).

| Krok | Vstup → výstup | Poznámka |
|---|---|---|
| `fetch` | Overture release → `raw/<vrstva>.parquet` | Z STAC indexu releasu (`collections.parquet`) vybere jen soubory, které protínají bbox oblasti. Midtown: ~5 min místo ~9 min na samotné budovy. |
| `roads` | segmenty + konektory → `graph.pb` | Rozdělí segmenty v konektorech, ořízne hranicí oblasti (konec = uzavírka), zahodí slepé mosty/tunely, nechá největší komponentu, vyznačí ponechané silnice (`road_keep_classes`, `road_keep_names`) a doplní nejkratší spojky: nejdřív bez ohledu na směr, pak po směru jízdy tam i zpět, aby se z každé ponechané silnice dalo dojet k ostatním i s jednosměrkami (silnice ven z oblasti bez cesty zpět zůstanou). Ostatní silnice jsou uličky. |
| `widen` | budovy − koridory silnic | Šířka = pruhy × `lane_width_m` + 2 × `sidewalk_width_m`, uličky 1,5 × pruh. Jen silnice ve vrstvě 0 (tunely vedou pod budovami, estakády nad nimi). |
| `buildings` | → `buildings.jsonl` | Výška: `height` → `num_floors` × 3,2 → `default_height_m`. Zjednodušení 1,5 m, sloučení sousedů ve stejném výškovém pásmu (DBSCAN 0,5 m). Památky a části budov (`building_part`) se neslučují; části památky se přeškálují na ruční výšku. |
| `ground` | voda, parky, náměstí, kolejiště → `ground.jsonl` | Sjednocení po druhu, ořez oblastí a mřížkou chunků. |
| `alleys` | uličky + budovy → `alleys.json`, `alley_probes.csv` | FL0 (`specs/flow.md`): ulička užší než `flow.gap_close_m` je `micro_only` (jen mikro vozidla) a dostane na oba konce sloupky (`Chunk.barriers`). |
| `nature` | voda, `land_use`, `land_cover` → `nature_water.jsonl`, `nature_green.jsonl`, `nature_shore.jsonl`, `nature_names.jsonl` | N0 (`specs/nature.md`): třída vody a zeleně, povrch, jméno; nepojmenované kusy řeky a moře převezmou jméno nejbližší pojmenované vodní linie (`nature.pipeline.water_name_search_m`), velké parky bez vnitřních ploch se dělí podle `land_cover`; mělčina podél břehu. `city.yaml` `water_class_by_name` přebije třídu podle jména (NYC: Upper New York Bay = moře). |
| `trees` | inventář stromů, OSM `natural=tree`/`tree_row`, parky → `nature_trees.json` | Stromy podél ulic se přichytí na chodník (`street_tree_snap_m`), v parcích a lesích Poissonův disk; nikdy na vozovce (silnice na terénu, i zapuštěné bez příznaku tunelu), v budově ani ve vodě; nejvýš `nature.trees_per_chunk_max` na chunk. `city.yaml` `tree_inventory` (URL CSV, sloupce, atribuce). |
| `elevation` | DEM → `elevation.json`, `graph_z.pb`, `terrain.bin` | T0 (`specs/terrain.md`): dem → clean → profile → pins → exaggerate → grade_clamp → conform → shade, viz níže. Bez `elevation_sources` zůstane balíček plochý. |
| `zones` | pěší segmenty a náměstí − koridory silnic → `zones_ground.jsonl`, `zones_barriers.jsonl` | Pěší zóny a sloupky (`specs/zones.md`): pásy `zones.street_width_m` kolem segmentů `pedestrian` a pěší náměstí, které protínají, bez koridorů silnic (+ `zones.gap_margin_m`). Hranice zóny bez hranice oblasti = zábrana (`Chunk.barriers`). |
| `trams` | segmenty `rail`/`tram` → `trams.pb` | Koleje jako vlastní obousměrný graf (rozdělení v konektorech, ořez oblastí, největší komponenta, bez slepých vleček kratších než `trams.min_track_m`). Zastávky se generují po úsecích mezi výhybkami (`specs/trams.md`). Město bez tramvají má prázdný graf. |
| `landmarks`, `spots` | YAML → `landmarks.pb`, `spots.pb` | Památka = nejbližší budova do 40 m od bodu (nebo `overture_id`). Spoty se přichytí na nejbližší ponechanou silnici. |
| `models` | `models.yaml` + CityGML v `raw/models/` → `models.pb` | M7 (`specs/models.md`): budovy zdroje ve výběru památky, převod souřadnic polynomem proloženým PROJ, čištění, rozpočet trojúhelníků, části s patou na terénu, střešní plán, náhled `preview/models/<id>.png`. `pack` doplní `replaces` a atribuci, `validate` hlídá rozpočty a patu. Mosty (v3) z IPR „Mosty 3D“ (`raw/models/mosty_shp/`, `models.yaml` `bridges`); `pack` ořízne most o silnice pod ním. Tokio (v5) z PLATEAU, souřadnice JGD2011 zeměpisné bez PROJ, jen LOD2. New York (v6) z NYC OTI 3-D Building Model, EPSG:2263, výšky ze stop na metry, `drop`. Bez `models.yaml` krok nic nedělá. |
| `pack` | → `app/assets/cities/<city>/` | `manifest.pb`, `graph.pb`, `chunks/{x}_{y}.pb`, `landmarks.pb`, `spots.pb`; vše gzip protobuf, souřadnice v decimetrech. Střechy a země předtriangulované (earcut). Deterministický: kanonické prstence, úplné řazení, bez času buildu – stejný vstup dá stejné bajty. |
| `validate` | hotový balíček | Souvislý graf, mosty a tunely napojené na obou koncích, trasa ze startu ke každému spotu (po ponechaných silnicích, s jednosměrkami), žádná budova na ose silnice, žádné sloupky přes osu silnice, limit velikosti chunku, každá hero památka má budovu. S terénem navíc: výšky uzlů a konců hran souhlasí, žádná hrana (mimo `stairs`) nad `terrain.max_grade` (tolerance clampu se počítá na každý úsek profilu), int16 bez saturace, mosty nad vodou a silnicí aspoň `terrain.pipeline.bridge_min_clear_m` (pod plnou světlostí `terrain.bridge.clear_*` jen varování; u nájezdu mostu, blíž než `clear_road_m / bridge.max_grade` od místa, kde most dosedá, jen varování), okraj silnice na terénu do `road_gap_max_m` u aspoň 1 − `road_gap_share` vzorků (vzorek, kde je do úhlopříčky mřížky jiná silnice v jiné výšce, se nepočítá: conform dá bod mřížky nejbližší silnici). S přírodou: stromy mimo vozovku, budovy a vodu, limit stromů na chunk, velká voda má jméno. |
| `lod` | `terrain.bin` + budovy + zeleň → `lod/{x}_{y}.pb` | Vzdálený prstenec: terén po `terrain.lod.grid_m`, budovy sloučené po blocích, les a park jako hmoty, voda jedním povrchem; dlaždice = `terrain.lod.chunks`² chunků. |
| `preview` | → `preview/{city.png,index.html}`, s terénem `<city>_relief.png` a `steepest.json`, s přírodou `<city>_nature.png` | Přehledka a porovnání s OSM. Reliéf: stínování (pole `shade`) přes barvu výšky, ponechané silnice, 10 nejprudších pojmenovaných ulic (skutečný sklon = herní / `exaggeration`, na úseku aspoň 60 m). Příroda: třídy vody a zeleně, mělčina, stromy, popisky. |

## Terén (M5, `specs/terrain.md`)

`city.yaml`: `elevation_sources` (pořadí = priorita): `local` čte první `content/cities/<id>/dem/*.asc`
(ESRI ASCII grid ve WGS84, postup v `dem/README.md`; adresář je mimo git), `terrain_tiles` stáhne
AWS Terrain Tiles (Terrarium PNG, zoom `terrain.pipeline.dem_zoom`) do `run/citypack/<city>/tiles/`,
`gsi_tiles` výškové dlaždice GSI DEM5A (Japonsko: 5 m z laseru, holý terén, zoom nejvýš 15, voda
a moře bez dat se dopočítají z okolí) do `tiles_gsi/`. Hladina vody je dolní kvartil výšek po
břehu; `water_level_m` (jméno → skutečné metry) ji přebije, kde to nesedí (Kōtō drží vnitřní
řeky pod přílivem: Oyoko River 0 m).
`elevation_is_bare_earth: false` = povrchový model: `clean` vyřízne budovy a vyhladí
(`clean_sigma_m`, u hrubého zdroje `clean_sigma_coarse_m`). Kód dlaždic je port z
MountainsSimulator/terrain-fetch (`internal/dem/`).

- **profile**: výška hran zhuštěných po `profile_step_m`, vyhlazená po trase (`profile_window_m`:
  `lidar` pro lokální mřížku, `coarse` pro dlaždice). Zapuštěná silnice bez příznaku tunelu (příčné
  ulice Central Parku) jede po terénu.
- **pins**: mosty mají dolní mez (voda + `bridge.clear_water_m`, silnice + `clear_road_m`,
  ikonické mosty `landmarks.yaml` `deck_height_m`), tunely horní (`tunnel.depth_*`); obě omezené
  tím, kam se z konců stavby dá dojet sklonem `bridge`/`tunnel.max_grade`.
- **grade_clamp**: sklony hran na `terrain.max_grade` podle třídy. Meze, které se navzájem
  vylučují, povolí dřív, než ze silnice udělají schody: nejdřív meze na koncích porušeného úseku,
  pak aktivní meze do `(clear_road_m + depth_land_m) / bridge.max_grade` po síti (portál tunelu
  a nájezd estakády spojené krátkou ulicí, Mrázovka u Radlické).
  Po clampu **fairing** (`profile_fair_passes`): pila rovina–max. sklon–rovina na strmých
  kopcích se vyhladí k průměru sousedů (v mezích) a clamp proběhne znovu.
- **conform**: terén řídí jen pozemní hrany (ne most ani tunel, vrstva 0 na obou koncích; mosty
  Overture ve vrstvě 0 jako Mánesův most se neberou). Bod mřížky do úhlopříčky buňky od vozovky
  nese výšku silnice; o sdílený bod vyhraje ponechaná silnice, pak nejbližší, pak vyšší. Pak
  **fit** (`conform_fit`): vzorky po 2 m po vozovce opraví rohy svých buněk (Kaczmarz), jen kde
  celá buňka patří téže hraně. Dál přechod `blend_m` k terénu; ve vodě dno (hladina −
  `underwater_m`), jen body pásu silnice na břehu drží její výšku. Voda se pozná podle týchž
  trojúhelníků, které kreslí balíček; kde se potkají dvě vodní tělesa, platí nižší hladina.
- **shade**: Horn, sklony násobené `shade_strength` (jen kanál `shade`).
- Podzemní vodní toky (Overture `level` < 0 nebo `tunnel=*`, Rudolfova štola pod Letnou) do
  vody ani do jmen nepatří.
- Mosty, nájezdy a estakády (každá netunelová hrana mimo terén, i most Overture ve vrstvě 0:
  Praha 53, NYC 61): v jejich půdorysu + `nature.pipeline.deck_tree_margin_m` neroste strom;
  validate hlídá 0 stromů v půdorysu a spojitou výšku desky (konec hrany = výška uzlu, skok
  uvnitř hrany ≤ 0,05 m).
- T3b: uzel, kde ponechaná silnice na konstrukci potká jen vedlejší silnice na zemi, zůstává na
  konstrukci; hrany na konstrukci u obou konců mají sklon mostu (Nuselský most: nájezdy 0,20 →
  0,08, deska neklesá na svah). Pozemní hrana, která z uzlu mostu pokračuje ve vzduchu nad
  conformovaným terénem (`elevated_flag`), je most (NYC West 38th Street, 2 hrany); profil a
  conform pak běží znovu. Terén do poloviny šířky silnice + `trench.margin_m` nese výšku silnice
  (validate: nad silnicí ≤ `trench.max_m` až na `trench.share` vzorků).
- Sloupky (zóny i uličky) se v kroku `pack` ořežou o vozovky ponechaných silnic a půdorysy mostů a
  nájezdů (Čechův a Jiráskův most); validate jich tam chce 0. Stromy v půdorysu desky, kterou
  označil až krok `elevation`, `pack` vypustí.
- Hrana nad vodou aspoň `bridge_over_water_m` v kuse, napojená na obou koncích, je most i bez
  příznaku (NYC: 2 hrany); slepá hrana nad vodou (molo) zůstane silnicí.

Zdroje: NYC AWS Terrain Tiles (USGS 3DEP, veřejné dílo; NYC 1 ft DEM má neověřenou licenci).
Praha zatím také AWS Terrain Tiles (EU-DEM/SRTM, ~25 m, povrchový model): ČÚZK DMR 4G i 5G jsou
jen LAZ v S-JTSK (ATOM `atom.cuzk.gov.cz/DMR4G-SJTSK`), převod na mřížku potřebuje PDAL/GDAL
(`content/cities/prague/dem/README.md`). Po převodu stačí `elevation_sources: [local]` a
`elevation_is_bare_earth: true`.

## Terén a příroda v číslech (M5, 2026-11-23)

| | New York | Praha |
|---|---|---|
| zdroj výšek | AWS Terrain Tiles (3DEP) | AWS Terrain Tiles (EU-DEM), DMR čeká na GDAL |
| z0, převýšení | −1 m, 2,0 | 183 m, 2,0 |
| schody, povolené meze | 0, 94 | 0, 446 |
| okraj silnice mimo terén > 0,3 m | 187 z 100 516 (0,2 %) | 240 z 55 429 (0,4 %) |
| vozovka ponechané silnice vs terén > 0,15 m (T3) | 79 z 187 946, max 0,42 m | 191 z 82 919, max 0,87 m (serpentiny) |
| body mřížky ve vodě nad hladinou (T3) | 0 | 0 (dřív 357, max 32 m pod mosty) |
| mosty pod plnou světlostí (varování) | 14 vzorků | 171 vzorků (nábřeží u předmostí) |
| stromy (žádný v půdorysu mostu či nájezdu) | 60 996 (35 392 ze Street Tree Census) | 32 782 (OSM + parky) |
| sloupky na vozovce či mostě (T3b) | 284 → 0 | 64 → 0 |
| terén > 0,3 m nad silnicí vedle ní (T3b) | 121 z 451 224 | 686 z 269 091 (Nerudova 8 z 1 062, max 0,68 m) |
| uzavřené štěrbiny, `micro_only` uličky | 9 080, 57 | 3 655, 99 |
| balíček | 4,5 MB | 3,1 MB |

Nejprudší ulice Prahy podle náhledu: Nad Laurovou, Nad Štolou, Donská, Zámecká, Thunovská (14–16,5 %
skutečného sklonu; strop dává `max_grade.alley` 0,33 / převýšení 2,0).

## Ověřeno proti datům (OVĚŘ z plánu, release 2026-11-18.0)

- **`lanes`** ve schématu segmentu pořád není. Pruhy jsou default podle třídy (`defaultLanes` v `roads.go`);
  upřesnění z OSM `lanes` by vyžadovalo extra OSM extrakt – zatím ne.
- **Jednosměrky**: `access_restrictions` s `access_type: denied` a `when.heading` (`backward` = jednosměrka
  ve směru geometrie). Počítají se jen bezpodmínečná omezení (bez módu, času, účelu).
- **Vrstvy**: `level_rules` (hodnoty −3…5) se zaokrouhlí na −1/0/+1; bez nich `road_flags` `is_bridge` / `is_tunnel`.
- **Čtvrti**: Overture `divisions` pokrývá Midtown jen komunitními obvody a pár mikročtvrtěmi →
  ruční `districts.yaml` na manhattanské mřížce (obdélníky ulice × avenue, první shoda vyhrává).
- **Výšky**: Overture má výšku u ~98 % budov Midtownu, NYC Building Footprints a GHSL proto zatím
  nejsou zapojené (`height_sources: [overture]`). Generování hmot z GHSL tam, kde obrysy chybí, není hotové.
- **DuckDB vs go-duckdb**: zvolena CLI binárka (bez CGO). DuckDB 2.0 vyžaduje `SET geometry_always_xy = true`.

## Midtown v číslech (M0)

~4 000 uzlů, ~4 700 hran (2 873 ponechaných), 9 407 hmot budov, 209 chunků, balíček 0,6 MB.

## Manhattan v číslech (M1)

Manhattan jižně od 110th St s mosty Brooklyn, Manhattan, Williamsburg a Queensboro a krátkými předmostími
(DUMBO, Williamsburg, Long Island City): 17 065 uzlů, 20 037 hran, 32 246 hmot budov, 896 chunků,
90 spotů (30 se minihrou, 8 budek, 12 vstupů do metra, 20 fotomíst, 6 občerstvení, 5 obchodů se suvenýry, 1 bar bez minihry), balíček 2,6 MB. Build s `-refetch` ~5 min.

## Praha v číslech (M3)

Praha 1 a 2 s Letnou, Holešovicemi, Karlínem, Žižkovem, Vinohrady, Smíchovem a Vyšehradem
(`plans/M3_PRAHA.md`): 12 510 uzlů, 14 419 hran (4 524 ponechaných, z toho 435 spojek kvůli
jednosměrkám), 13 942 hmot budov, 507 chunků, 56 spotů (30 se minihrou, 6 budek, 12 vstupů do metra), balíček 1,7 MB. Build s
`-refetch` ~6 min. Organická síť jednosměrek bez spojek po směru jízdy rozpadla ponechané silnice
na ostrovy, kam se nedalo dojet (Národní, Spálená, Dlouhá); proto druhý krok spojek.

Pěší zóny (M3-S4): Praha 274 ploch dlažby a 496 linií sloupků (Karlův most, Staroměstské
náměstí, náplavky), Manhattan 253 a 475 (pěší náměstí jako Times Square). Balíčky 1,6 a 2,6 MB.

Tramvaje (M3-S5): Praha 3 247 hran kolejí, 174 generovaných zastávek, balíček 1,7 MB; New York
prázdný `trams.pb`.

## Tokio v číslech (M4)

Chiyoda, Chūō, sever Minata (Roppongi, Shiba) a laloky přes Kandu, Akihabaru a Ueno do Asakusy,
Ryōgoku a k Skytree (`plans/M4_TOKIO.md` T1, ~50 km²): 31 728 uzlů, 40 625 hran (14 424
ponechaných, z toho 381 spojek kvůli jednosměrkám), 84 927 hmot budov (hustá zástavba, skoro
3× Manhattan), 789 chunků, 43 spotů (7 se minihrou, 2 budky, 11 vstupů do metra, 10 fotomíst,
8 obchodů a barů), balíček 3,7 MB. Levostranný provoz (`drive_side: left`). Build s fetch ~13 min.

Jména silnic: Overture má v Tokiu `names.primary` japonsky. `city.yaml` `name_langs: [ja-Latn,
en]` bere první `names.common` v tomto pořadí a `names.primary` jen v latince, japonská jména bez
přepisu zahodí (klienti nemají písmo CJK). Jména jsou po segmentech nejednotná (`Harumi-dōri`,
`Harumi Street`), HUD je ukáže, jak jsou.

- Spoty mají pole `minigame` (id z katalogu): na tom místě se minihra hraje (9.5).
- `validate` bere při kontrole „silnice v budově“ v úvahu dvory (díry v obrysu): příjezd do dvora
  Dakoty na 72nd St není kolize.


## Moskva v číslech (M6)

Uvnitř Sadového okruhu i s okruhem + Zamoskvorečje, Gorkého park, Komsomolské náměstí a předmostí
u Kutuzovského (`plans/M6_MOSKVA.md` X1; sever oříznutý na 55,777° kvůli dvorním rampám u
Novoslobodské): 28 296 uzlů, 31 834 hran, 15 079 hmot budov, 520 chunků, 48 spotů (13 s minihrou,
2 budky, 12 vstupů do metra, 8 fotomíst, 8 obchodů a barů), 387 hran tramvají a 34 zastávek,
balíček 3,8 MB (`pack-moscow-1cabcee6fcf1`). Build s fetch ~12 min.

Terén z AWS Terrain Tiles (z0 = 122 m, převýšení 2,0, 0 schodů): Moskva je mírná, nejprudší
pojmenovaná ulice je Bolšoj Nikolovorobinskij pereulok 11,5 %, pak Zemljanoj val 9,9 %. Příroda:
14 170 stromů (OSM 46 %, zbytek Poissonův výsev v parcích), řeka Moskva, Jauza, Obtokový kanál,
Patriarší a Golicynské rybníky pojmenované; 62 hran mostů, 43 z nich s koncem ve vrstvě 0.

Jména: Overture má v Moskvě `names.primary` azbukou. `name_langs: [en, ru-Latn]` bere anglické
nebo latinkou přepsané jméno; od M6 platí `name_langs` i pro vodu a zeleň (krok `nature`, dřív
jen silnice), azbuka by se v klientech nevykreslila. Plochy kanálu bez jména berou jméno
z nejbližší pojmenované čáry kanálu jako řeky (Obtokový kanál má jméno jen na ose).

- `validate`: `terrain.pipeline.road_strip.max_m` 1,2 m (dvorní obslužné rampy u Novoslobodské
  a na Taganke 1,04–1,18 m; Praha 0,87, NYC 0,42). Od Tokia 2,1 m (vlásenka ponechané spojky pod
  Tanuki-zaka v Azabu 2,01 m).
- `validate`: přistání mostu je i uzel, kde most navazuje na krátkou rampu z vrstvy 1 do 0 (výjezd
  Shuto na Sendai-dori), nejen na pozemní hranu.
- Borovická věž nemá v Overture budovu, je bod (`kind: plaza`).

## Tokio: přírodní vrstvy a terén (přestavba po M5/N1)

Balíček `5af7637300d7` vznikl před terénem a přírodou, takže neměl `lod/` (mapa v telefonu z nich
kreslí vodu a zeleň) ani mřížku terénu. Terén z AWS Terrain Tiles tu nejde: v Japonsku nesou SRTM,
povrchový model ~12 m nad ulicemi (Shōwa-dōri v Iriya 16 m místo 2 m), řeky pak ležely nad mosty.
Tokio proto bere `gsi_tiles` (DEM5A, holý terén): z0 = −1 m, převýšení 2,0, 2 schody, nejprudší
Ōsaka 16,3 % a Ushi-zaka 16,2 %. Plocha `natural=water` + `water=bay` bez jména u Harumi je moře
(`specs/nature.md`), ne jezero. Obslužná ulička nad vodou se za most nepovažuje (`flagWaterBridges`:
vlásenka pod Shuto u Nihonbashi-gawa nebyla most z břehu na břeh).

## Modely památek (M7, `specs/models.md`, 2026-11-27)

Zdroj Praha: **IPR Praha, 3D model budov** (CityGML 2.0, export CityGRID), licence **CC BY 4.0**,
atribuce „data base © IPR Praha“ (v manifestu „3D model: data base © IPR Praha (CC BY 4.0)“).
Licence: https://www.geoportalpraha.cz/en/data-and-services/open-data , popis dat:
https://geoportalpraha.cz/en/data-and-services/articles-and-projects/3d-model/3d-model-budovy-mosty .
Soubory po mapových listech 1 : 5000 jsou položky ArcGIS Online uživatele `opendatapraha`
(`BD3_Prah_<list>` typu GML); Hrad a pilot pokrývá list **Praha 7-1** (`BD3_Prah_7-1.gml`, 172 MB),
druhá dávka (H4) přidává **6-1** (Obecní dům s Prašnou bránou, 144 MB), **6-2** (Národní muzeum,
Žižkovská věž, 182 MB) a **7-2** (Tančící dům, Vyšehrad, 120 MB); třetí dávka (Hlavní nádraží
a Vítkov v 6-1, Staronová synagoga a Klementinum v 7-1) nový list nepotřebuje:

```
mkdir -p run/citypack/prague/raw/models
d=run/citypack/prague/raw/models; u=https://www.arcgis.com/sharing/rest/content/items
curl -L -o $d/BD3_Prah_7-1.gml $u/88dc83fcd48c4ac9aec3532c19395d72/data
curl -L -o $d/BD3_Prah_6-1.gml $u/78e0a97afa514482b86aa7a53b3fdb4f/data
curl -L -o $d/BD3_Prah_6-2.gml $u/fc9e5b3903d3454fb5c8d02f74179b6e/data
curl -L -o $d/BD3_Prah_7-2.gml $u/94f085ef4a524a129f6bc2bae86f8c22/data
run/bin/citypack -force models prague && run/bin/citypack pack prague && run/bin/citypack validate prague
```

Surová data nejsou v gitu ani v CI (`run/` je ignorovaný); vydaný balíček nese hotový `models.pb`.
Souřadnice zdroje S-JTSK / Křovák East North (EPSG:5514, v souboru `srsName="unknown"`), výšky Bpv.
Převod do místních metrů: kvadratický polynom proložený PROJ (DuckDB `ST_Transform`) na mřížce 5 × 5
přes obálku listu, reziduum 1 mm. Podrobnosti a čísla v `plans/M7_PAMATKY.md`.

### Tokio – MLIT Project PLATEAU (H5, 2026-11-28)

Zdroj: **3D都市モデル（Project PLATEAU）東京都23区**, data FY2025 (spec 5.0), CityGML 2.0 + i-UR,
po městských obvodech a po **3. stupni sítě (1 km)**, jeden soubor budov na mesh
`udx/bldg/<mesh>_bldg_6697_op.gml`. Stahuje se jen potřebný mesh, ne zip celého obvodu
(0,4–2,5 GB): katalog `https://api.plateauview.mlit.go.jp/datacatalog/citygml/m:<mesh>` vrátí URL
souboru pro každý obvod, který mesh zasahuje (Taitō a Sumida mají pro týž mesh různé soubory).

**Licence:** podmínky webu PLATEAU (https://www.mlit.go.jp/plateau/site-policy/, kap. 3): obsah lze
užít podle **公共データ利用規約（第1.0版）(PDL 1.0)**, https://www.digital.go.jp/resources/open_data/public_data_license_v1.0 ;
pravidla jsou výslovně **kompatibilní s CC BY 4.0** (PDL 1.0 §1.7.3). Autorská práva k 3D modelům
měst drží jednotlivé obce (zde obvody Tokia). Povinné: uvést zdroj a u upravených dat uvést, že
jsou upravená, a nevydávat je za dílo MLIT. Mimo licenci jsou loga a symboly (LOD2 žádné nemá,
R10). Web PLATEAU upozorňuje, že užití výsledků veřejného zeměměření může omezovat zákon
o zeměměřictví (測量法, příručka https://www.mlit.go.jp/plateau/libraries/handbooks/); hra modely jen
zobrazuje jako obraz, příručku jsme nečetli (**neověřeno**). Text atribuce:

```
出典：国土交通省 PLATEAUウェブサイト（https://www.mlit.go.jp/plateau/open-data/）
「3D都市モデル（Project PLATEAU）東京都23区」（国土交通省）（https://www.geospatial.jp/ckan/dataset/plateau-tokyo23ku）を加工して作成
```

V manifestu (hra nemá písmo CJK) anglicky: „3D model: Source: MLIT Project PLATEAU
(https://www.mlit.go.jp/plateau/open-data/), processed (PDL 1.0)“.

**Soubory** (`run/citypack/tokyo/raw/models/`, jméno `<kód obvodu>_<mesh>_bldg_6697_op.gml`):

| Soubor | Památka | Velikost | sha256 |
|---|---|---|---|
| `13103_53393599` (Minato) | Tokijská věž | 110 MB | `95059a52aee0e34c…` |
| `13107_53394654` (Sumida) | Tokyo Skytree | 60 MB | `ca0d97fb6178ca0e…` |
| `13106_53394653` (Taitō) | Sensō-ji (Kaminarimon, Hōzōmon, hlavní síň, pagoda) | 143 MB | `57e8a933ccf054d5…` |
| `13101_53394611` (Chiyoda) | nádraží Tokio (Marunouchi) | 166 MB | `3448bec01ea01591…` |
| `13101_53394519` (Chiyoda) | Národní sněmovna – budova **v datech není**, soubor se nepoužívá (není v `files`) | 11 MB | `69d22f506861b245…` |

```
d=run/citypack/tokyo/raw/models; mkdir -p $d; a=https://assets.cms.plateau.reearth.io/assets
curl -L -o $d/13103_53393599_bldg_6697_op.gml $a/ea/d75459-6d62-4a1f-8081-317603bd5f8d/13103_minato-ku_pref_2025_citygml_1_op/udx/bldg/53393599_bldg_6697_op.gml
curl -L -o $d/13107_53394654_bldg_6697_op.gml $a/af/d16ede-837d-458a-af51-16771bbb96d8/13107_sumida-ku_pref_2025_citygml_1_op/udx/bldg/53394654_bldg_6697_op.gml
curl -L -o $d/13106_53394653_bldg_6697_op.gml $a/80/45b2b1-5a88-40ab-9877-70b540b8707e/13106_taito-ku_city_2025_citygml_1_op/udx/bldg/53394653_bldg_6697_op.gml
curl -L -o $d/13101_53394611_bldg_6697_op.gml $a/5d/dc07c5-ace7-465a-9c99-53f6d78f6164/13101_chiyoda-ku_pref_2025_citygml_1_op/udx/bldg/53394611_bldg_6697_op.gml
run/bin/citypack -force models tokyo && run/bin/citypack pack tokyo && run/bin/citypack validate tokyo
```

**Souřadnice:** EPSG:6697 = JGD2011 zeměpisná šířka, délka (v tomto pořadí) a výška T.P. (střední
hladina Tokijského zálivu). JGD2011 se od WGS84 liší o centimetry (obojí ITRF), proto se vrcholy
promítají přímo projekcí balíčku jako Overture (`models.go`, v5 `latLon`), bez PROJ. Výšky T.P.
se používají jen relativně (pata = medián terén − země zdroje), datum nevadí. Kontrola polohy:
střešní plán proti vlastním půdorysům Overture, posun 0–0,7 m (Skytree 3 m, Overture kryje jen
čtvrtinu komplexu), viz `plans/M7_PAMATKY.md`.

**Formát PLATEAU:** budovy mají LOD0 (půdorys), LOD1 (hranol), LOD2 (`bldg:boundedBy` s plochami)
a několik i LOD3/LOD4; čtečka (v5) bere jen LOD2. Instalace (`lod2Geometry`) nemají plochy
`Roof/Wall/Ground` a vypadnou. Podhledy střech a bran (`OuterCeilingSurface`) se čtou jako střecha.

### New York – NYC OTI 3-D Building Model (H5, 2026-11-28)

Zdroj: **NYC Office of Technology and Innovation (OTI, dřív DoITT), „3-D Building Model“**, NYC
Open Data `tnru-abg2` (https://data.cityofnewyork.us/d/tnru-abg2), zveřejněno 2016-04-18,
letecké snímkování 2014, CityGML **1.0** LOD2 (Ground/Wall/RoofSurface pod `lod2MultiSurface`),
jedna budova na BIN (atributy `BIN`, `DOITT_ID`, `SOURCE_ID`), bez `BuildingPart` a bez textur.
Ke stažení tři zipy na `s-media.nyc.gov/agencies/oti/` (CityGML 916 MB, multipatch 257 MB, DGN);
uvnitř 20 dodacích oblastí `DA<n>_3D_Buildings_Merged.gml` a jejich obálky `DeliveryArea.shp`.

**Licence:** NYC Open Data jsou podle NYC Administrative Code **§ 23-502(d)** dostupná „without any
registration requirement, license requirement or restrictions on their use“; město smí od
přeposílatele (i aplikace) žádat uvedení **zdroje, verze a popisu úprav** – proto je má řádek
v manifestu i `NOTICE`. FAQ NYC Open Data: „There are no restrictions on the use of Open Data.“
Odpovědnost za data město odmítá (§ 23-504). Dataset sám licenci neuvádí (`license: null`),
dodatečné podmínky agentury (OTI) jsme nenašli. Loga a jména města (NYC je ochranná známka)
hra nepoužívá (R10). **Lze.**

V manifestu: „3D model: NYC 3-D Building Massing Model, NYC OTI (NYC Open Data tnru-abg2, 2014
survey, published 2016-04-18), simplified and recoloured“.

**Soubory** (`run/citypack/nyc/raw/models/`): stahuje se jen potřebná oblast, ne celý zip. Zip
podporuje HTTP range; centrální adresář je na konci (28 položek), položka se stáhne podle offsetu
a rozbalí (deflate). Všech sedm památek první dávky leží v **DA12** (Manhattan zhruba pod 59. ulicí
a dolní Manhattan; 44 MB komprimovaně, `DA12_3D_Buildings_Merged.gml` 614 061 971 B):

```
d=run/citypack/nyc/raw/models; mkdir -p $d; u=https://s-media.nyc.gov/agencies/oti/DA_WISE_GML.zip
# DA12: lokální hlavička na offsetu 86275704, komprimovaně 43973699 B (z centrálního adresáře)
python3 - "$u" 86275704 43973699 $d/DA12_3D_Buildings_Merged.gml <<'PY'
import sys,struct,zlib,subprocess
u,off,cs,out=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]
h=subprocess.run(['curl','-s','-r',f'{off}-{off+29}',u],capture_output=True).stdout
s=off+30+sum(struct.unpack('<HH',h[26:30]))
p=subprocess.Popen(['curl','-s','-r',f'{s}-{s+cs-1}',u],stdout=subprocess.PIPE); d=zlib.decompressobj(-15)
with open(out,'wb') as f:
    for c in iter(lambda:p.stdout.read(1<<20),b''): f.write(d.decompress(c))
    f.write(d.flush())
PY
run/bin/citypack -force models nyc && run/bin/citypack pack nyc && run/bin/citypack validate nyc
```

**Souřadnice:** NAD83 / New York Long Island **ftUS** (EPSG:2263, `srsName="EPSG:2263"` v souboru),
výšky NAVD88 v **amerických stopách**. x, y převádí PROJ přes EPSG:4326 do projekce balíčku
(polynom na mřížce 5 × 5 přes obálku DA12, 7 × 8 km, reziduum 1 mm); z se násobí 1200/3937
(`nyc_3d` v `models.go`, v6). Bez převodu výšek by věže byly 3,28× vyšší (ESB ~1 450 m). Datum
NAVD88 nevadí, výška se bere jen relativně (pata = medián terén − země zdroje). Pražskou chybu
117 m (PROJ bez datumu) převod přes EPSG:4326 nemá: poloha 0–1,4 m proti Overture (One WTC 3 m).

**Co v datech je a není:** budovy ano (anténa ESB, špice One WTC a Chrysleru, věže sv. Patrika),
mosty ne (Brooklyn Bridge v DA19 chybí, jen dva nízké objekty u brooklynského pilíře), socha
Svobody ano (DA19, BIN 1000002, podstavec s hvězdicí Fort Wood), ale leží mimo oblast balíčku.
Snímkování 2014: novější stavby chybí a staveniště jsou ve stavu 2014 (u One WTC 10m objekt pod
týmž BIN, `drop`).

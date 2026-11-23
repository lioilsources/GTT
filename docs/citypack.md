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
| `zones` | pěší segmenty a náměstí − koridory silnic → `zones_ground.jsonl`, `zones_barriers.jsonl` | Pěší zóny a sloupky (`specs/zones.md`): pásy `zones.street_width_m` kolem segmentů `pedestrian` a pěší náměstí, které protínají, bez koridorů silnic (+ `zones.gap_margin_m`). Hranice zóny bez hranice oblasti = zábrana (`Chunk.barriers`). |
| `trams` | segmenty `rail`/`tram` → `trams.pb` | Koleje jako vlastní obousměrný graf (rozdělení v konektorech, ořez oblastí, největší komponenta, bez slepých vleček kratších než `trams.min_track_m`). Zastávky se generují po úsecích mezi výhybkami (`specs/trams.md`). Město bez tramvají má prázdný graf. |
| `landmarks`, `spots` | YAML → `landmarks.pb`, `spots.pb` | Památka = nejbližší budova do 40 m od bodu (nebo `overture_id`). Spoty se přichytí na nejbližší ponechanou silnici. |
| `pack` | → `app/assets/cities/<city>/` | `manifest.pb`, `graph.pb`, `chunks/{x}_{y}.pb`, `landmarks.pb`, `spots.pb`; vše gzip protobuf, souřadnice v decimetrech. Střechy a země předtriangulované (earcut). Deterministický: kanonické prstence, úplné řazení, bez času buildu – stejný vstup dá stejné bajty. |
| `validate` | hotový balíček | Souvislý graf, mosty a tunely napojené na obou koncích, trasa ze startu ke každému spotu (po ponechaných silnicích, s jednosměrkami), žádná budova na ose silnice, žádné sloupky přes osu silnice, limit velikosti chunku, každá hero památka má budovu. |
| `preview` | → `preview/{city.png,index.html}` | Přehledka a porovnání s OSM. |

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
86 spotů (26 se minihrou, 8 budek, 12 vstupů do metra, 20 fotomíst, 6 občerstvení, 5 obchodů se suvenýry, 1 bar bez minihry), balíček 2,6 MB. Build s `-refetch` ~5 min.

## Praha v číslech (M3)

Praha 1 a 2 s Letnou, Holešovicemi, Karlínem, Žižkovem, Vinohrady, Smíchovem a Vyšehradem
(`plans/M3_PRAHA.md`): 12 510 uzlů, 14 419 hran (4 524 ponechaných, z toho 435 spojek kvůli
jednosměrkám), 13 942 hmot budov, 507 chunků, 54 spotů (28 se minihrou, 6 budek, 12 vstupů do metra), balíček 1,7 MB. Build s
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

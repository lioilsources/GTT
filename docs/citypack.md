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
| `roads` | segmenty + konektory → `graph.pb` | Rozdělí segmenty v konektorech, ořízne hranicí oblasti (konec = uzavírka), zahodí slepé mosty/tunely, nechá největší komponentu, vyznačí ponechané silnice (`road_keep_classes`, `road_keep_names`) a doplní nejkratší spojky. Ostatní silnice jsou uličky. |
| `widen` | budovy − koridory silnic | Šířka = pruhy × `lane_width_m` + 2 × `sidewalk_width_m`, uličky 1,5 × pruh. Jen silnice ve vrstvě 0 (tunely vedou pod budovami, estakády nad nimi). |
| `buildings` | → `buildings.jsonl` | Výška: `height` → `num_floors` × 3,2 → `default_height_m`. Zjednodušení 1,5 m, sloučení sousedů ve stejném výškovém pásmu (DBSCAN 0,5 m). Památky a části budov (`building_part`) se neslučují; části památky se přeškálují na ruční výšku. |
| `ground` | voda, parky, náměstí, kolejiště → `ground.jsonl` | Sjednocení po druhu, ořez oblastí a mřížkou chunků. |
| `landmarks`, `spots` | YAML → `landmarks.pb`, `spots.pb` | Památka = nejbližší budova do 40 m od bodu (nebo `overture_id`). Spoty se přichytí na nejbližší ponechanou silnici. |
| `pack` | → `app/assets/cities/<city>/` | `manifest.pb`, `graph.pb`, `chunks/{x}_{y}.pb`, `landmarks.pb`, `spots.pb`; vše gzip protobuf, souřadnice v decimetrech. Střechy a země předtriangulované (earcut). Deterministický: kanonické prstence, úplné řazení, bez času buildu – stejný vstup dá stejné bajty. |
| `validate` | hotový balíček | Souvislý graf, mosty a tunely napojené na obou koncích, trasa ze startu ke každému spotu (po ponechaných silnicích, s jednosměrkami), žádná budova na ose silnice, limit velikosti chunku, každá hero památka má budovu. |
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

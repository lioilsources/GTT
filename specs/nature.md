# Voda a zeleň

**version: 1** · data P0 (citypack) · povrchy, pád do vody P1 (±5 %, scénáře `scenarios/nature/`)
· vzhled vody a korun P2 · plány `Prompts/03-METROPOLE_NATURE_PLAN.md` a
`Prompts/04-METROPOLE_FLOW_PLAN.md` (les průjezdný) · pod-plán `plans/M5_TEREN_PRIRODA.md` ·
parita F-072 (voda a zeleň), F-073 (les a stromy, viz `specs/flow.md`)

## Účel
Voda a parky jsou hlavní orientační body. Hráč je pozná na první pohled, ve všech městech stejně:
voda je vždy modrá a nic jiného modré není, zelená patří zeleni, park má stromy, les, louky a
jména. Čísla `content/tuning.yaml` → `nature`, barvy `design/tokens.json` → `color.water`,
`color.green`. Všechno je přídavné: balíček bez nových polí se kreslí jako dosud (`ground`).

## Třídy
**Voda** (`Water.class`)

| Třída | Z čeho (Overture `base/water`) | Vzhled |
|---|---|---|
| `sea` | subtype `ocean`, class `bay`, `harbour`, `strait` | `color.water.sea`, dlouhá vlna |
| `river` | subtype `river`; `stream` širší než 6 m | `color.water.river` |
| `canal` | subtype `canal` | `color.water.river`, rovný břeh |
| `lake` | subtype `lake`, `pond`, `reservoir` | `color.water.lake` |
| `small` | plocha pod 400 m² (fontána, bazén) | `color.water.small`, bez animace |

Prvky jen pro popisky (subtype `physical`, linie bez plochy) se do výplní nepočítají, jejich jméno
smí posloužit jako popisek.

**Zeleň a povrchy** (`Green.class`, `Green.surface`)

| Třída | Stromy | Povrch | Průjezdné |
|---|---|---|---|
| `wood` (les) | `nature.trees_per_ha.wood` | `forest` | ano (`specs/flow.md`) |
| `parkland` | `trees_per_ha.parkland` | `grass` | ano |
| `garden` | `trees_per_ha.garden` | `grass` | ano |
| `cemetery` | `trees_per_ha.cemetery` | `grass` | ano |
| `grass` (louka, hřiště) | žádné | `grass` | ano |
| `sand` (pláž) | žádné | `sand` | ano |

Rozdělení parku: voda > les > louka a hřiště > zbytek `parkland`. Park nad 5 ha bez vnitřních
ploch se rozdělí podle `base/land_cover` (subtype `forest` souvisle nad 0,5 ha = `wood`).
Ruční opravy v `content/cities/<id>/nature_overrides.geojson` mají přednost.

## Data v balíčku (návrh polí, `.proto` přibude s N0)
| Zpráva | Pole | Popis |
|---|---|---|
| `Ground` (voda) | `water_class` (enum), `name`, `label_axis` (polyline dm), `shore` (polygon pruhu mělčiny `nature.shore_band_m`) | |
| `Green` (nové v `Chunk`) | polygon, `class`, `surface`, `name`, `label_axis` | ořezané mřížkou chunků |
| `Chunk.trees` | bytes, 3 B na strom: x (uint8, m od kraje chunku), y (uint8), velikost 0–2 = S/M/L v dolních 2 bitech + 6 bitů jitter barvy | nejvýš `nature.trees_per_chunk_max` |
| `Spot.area_name` | string | park nebo voda do 150 m („Washington Square Park“, „u Hudsonu“) |
| `lod/*.pb` | voda jedna plocha, `wood` a `parkland` jako nízké hmoty 14 m a 8 m | šikmý pohled |

Pole `woods` (lesní hmoty) se do chunků nezapisuje (rozhodnutí F1 v plánu FLOW).
Stromy: inventář města (velikost podle průměru kmene: < 20 cm S, < 50 cm M, jinak L), pak body a
stromořadí z OSM, pak Poissonův disk v třídách s hustotou, seed = `hash(city, chunk)` (FNV-1a
32 bit nad `"<city>/<cx>_<cy>"`). Žádný strom blíž než `crown_r` velikosti k silnici, budově
nebo vodě; nad limitem chunku se rovnoměrně proředí (každý k-tý v pořadí x, y).

## Barvy (vyhrazené odstíny)
- `color.water.{sea, river, lake, small, shore, line}` a `color.green.{wood, parkland, grass,
  crown, trunk, sand}` jsou společné všem městům. Paleta města smí měnit jen světlost a sytost
  v rozsahu ±12 % (klíče `color.city.<id>.water`, `park` zůstávají jako odstín pro starší kreslení
  `ground`, nové kreslení vody a zeleně bere `color.water`/`color.green`).
- **Vyhrazené rozsahy** (HSL, jen pro barvy se sytostí ≥ 0,25 a světlostí 0,12–0,92): modrá
  vody = odstín 185–240°, zelená = 75–165°. Žádný povrch, fasáda, střecha, silnice ani prvek UI
  světa nesmí do nich padnout. Výjimka: průhledné stíny (alfa < 0,8) a texty/ikony HUD.
- `metro validate` to hlídá u `color.city.*` a `color.world.*`. Do rozhodnutí Ol1na (konflikty
  níže) kontrola jen varuje, nepadá.

### Konflikty se stávajícími paletami (stav 2026-11-23, rozhoduje Ol1n)
| Paleta | Klíč | Barva | Problém |
|---|---|---|---|
| `world.day` | facades | #8FA9C4 | ocelově modrá fasáda v rozsahu vody |
| `city.nyc` | facades | #5678A3, #2E465D, #193B62 | modré věže stylu A v rozsahu vody |
| `city.nyc` | park | #7FA37A | málo sytá, mimo zelený rozsah |
| `city.prague` | water | #368C76 | voda tyrkysově zelená (odstín 165°), patří do zelené |
| `city.prague` | park | #63A18D | na hranici zelené (161°, sytost 0,25) |
| `city.prague` | sidewalk | #DDE4CD | světle zelený chodník (78°) |
| `city.tokyo` | asphalt | #92CACB | tyrkysový asfalt (181°) těsně pod rozsahem vody |

Návrh: fasády NYC posunout k šedomodré se sytostí pod 0,25, vodu Prahy na `color.water.river` s
risografickým inkoustem, tokijský asfalt nechat (mimo rozsah). Nic se nemění bez Ol1na.

## Vykreslení shora (oba klienti, P2)
- voda: výplň podle třídy, světlejší pruh `shore`, tmavší linka břehu `color.water.line`, stín
  mostu jako tmavý pás na hladině, jméno podél `label_axis` kurzívou (styl jmen ulic)
- vlnění: F posuvná textura (`ImageShader`, alfa 0,15, na nízké kvalitě vypnuto); W rovina
  s dvěma posuvnými vrstvami šumu, neprůhledná
- louka a parková zeleň: plocha `color.green.grass` / `parkland`; les `color.green.wood`
- strom: tmavá tečka kmene `color.green.trunk` na zemi + koruna `color.green.crown` ve výšce
  stromu (promítá se jako střecha, `specs/terrain.md`); koruna do `nature.crown_fade.radius_m`
  (v lese `flow.forest.crown_fade_radius_m`) od hráčova auta má alfu `crown_fade.alpha`
- jméno parku uprostřed plochy; HUD „ulice · čtvrť“ ukáže jméno parku, když je v něm hráč
- pořadí ve F: země a voda → silnice → stíny, rekvizity, chodci, vozidla → koruny od
  nejvzdálenější → budovy → mosty → popisky
- mapa v telefonu: stejné barvy, voda a parky ve všech přiblíženích, jména podle plochy

## Jízda (P1)
- **Povrch pod autem:** `grip × nature.grip[surface]` (`asphalt` mimo zeleň, `grass`, `sand`,
  `dirt` pro uličky bez zpevnění, `forest` podle `specs/flow.md`).
- **Voda:** když střed auta ve vrstvě 0 vjede do polygonu vody (ne `small`), auto ztratí ovládání,
  za `nature.water_fall.sink_s` se potopí (měřítko 1 → 0,6, alfa → 0) a hráč se objeví na
  nejbližším uzlu ponechané silnice ve vrstvě 0, čelem po hraně, rychlost 0; poplatek za
  odtahovku = akce `{op: "tow"}` modulu `economy` (`economy.tow_fee`, `specs/economy.md`). Z mola nebo nábřeží se dá sjet, žádná neviditelná zeď.
  Během Taxi směny a minihry se počítá jako zrušení jízdy podle pravidel dané hry.
- Provoz a chodci: auta AI zůstávají na silnicích, chodci chodí parkem po cestách.
- Lodě (N2, jen kulisa): nejvýš 6 viditelných, po trasách trajektů z dat; kde nejsou, nejsou.

### Scénáře (`scenarios/nature/`, ±5 %, `sedan_regent`)
1. `brake_grass`, `brake_sand` proti `brake_asphalt` – brzdná dráha z 20 m/s.
2. `water_fall` – vjezd do vody: respawn na stejném uzlu (shoda id uzlu), poplatek.

## Hraniční případy
- Balíček bez tříd: `ground` kreslení jako dosud, povrch všude `asphalt`.
- Strom na hranici chunku patří chunku svého kmene.
- Spot v parku i u vody: `area_name` = park (menší plocha vyhrává).
- Voda v tunelu (vrstva −1) ani pod mostem (+1) pád nespustí.

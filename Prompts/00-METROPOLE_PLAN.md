# METROPOLE_PLAN.md

**Pracovní název:** Metropole
**Stav:** master plán + detailní zadání M0 a M1. Pozdější milníky dostanou vlastní pod-plán v `plans/` až po dogfoodingu M1.
**Datum:** 2026-11-21
**Pro:** kódovací model (Opus, střední effort). Rozhodnutí v kapitole 2 jsou uzavřená, neotvírej je. Co je označené **OVĚŘ**, ověř v dokumentaci, než na tom postavíš kód. Co je v kapitole 16, rozhoduje Ol1n — do té doby platí uvedený default.

---

## 1. Vize a pilíře

Volné ježdění autem po skutečných světových metropolích. Úkoly si hráč vybírá ve vertikálním feedu na herním telefonu: každá karta je „motiv" = minihra na konkrétním místě ve městě. Hráč přijme, GPS ho vede městem, cestou se může zdržet čímkoli, na místě si zahraje 5–10 minut a vrací se do feedu.

Pilíře (při každém sporu rozhoduje pořadí):

1. **Jízda je hračka sama o sobě.** Když nebaví 5 minut bezcílného ježdění, nic dalšího se nestaví.
2. **Město je skutečné.** Geografie 1:1, správné mosty, tunely, řeky, výšky. Turista, který hru hrál, se ve městě neztratí.
3. **Minihry jsou klasiky.** Pravidla zná každý, žádné vysvětlování delší než 3 karty. Plus hry, které se hrají jen v tom městě.
4. **Svoboda = svět reaguje.** Ne zbraně, ale fyzika, provoz, policie, lidi s hláškami. Úkol jde kdykoli ignorovat.
5. **Jeden palec, na výšku, offline.** Bez reklam, bez trackingu, bez loot boxů.

## 2. Uzavřená rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| R1 | Mobilní hra na výšku, ovládání jedním palcem („palcovka"). Tablet/desktop/web jsou vedlejší buildy téhož kódu. | Hub je vertikální feed; na výšku je vidět daleko dopředu; krátké seance. Na PC/konzoli by se hra měřila s GTA a prohrála. |
| R2 | Flutter + Flame, jeden codebase. Svět je 2,5D: pohled shora, budovy vytažené perspektivou (styl GTA 1/2). | Ol1nův stack a pipeline (store, lokalizace), minihry a hub jsou z velké části UI, jde převzít existující hry. Skutečné 3D ve Flame (`flame_3d`) je experimentální a stojí na experimentálním Flutter GPU — nestavět na něm. |
| R3 | Brána M0: 2,5D Midtown musí běžet 60 fps na referenčním telefonu. Když ne, platí záložní žebřík v 6.5. | Jediné velké technické riziko, proto se řeší jako první. |
| R4 | Geografie 1:1, auta zvětšená (`car_scale` ≈ 2,5), ponechané silnice rozšířené, vedlejší ulice bez provozu. Žádná komprese mapy. | Zachová proporce, panorama i šířku řek; auto je na telefonu čitelné. |
| R5 | Zdroj map: Overture Maps (obsahuje OSM) + městská open data + GHSL jako záloha výšek. Zpracování Go CLI `citypack`, výstup stahovatelný balíček na město. | Jedno schéma pro celý svět, licence známé (kap. 14). |
| R6 | Minihry = ~11 sdílených enginů + pravidlové moduly + skiny. Každá minihra je samostatný Dart balíček se stejným kontraktem. | 100 her nesmí být 100 codebase. Izolované balíčky = snadný regresní test. |
| R7 | Bez zbraní a bez zabíjení. Chodci vždy uskočí. Policie honí a pokutuje. | Tón (turista + manga), rating, odlišení od klonů GTA. |
| R8 | Bez volné chůze. Vystoupení = kontextová akce na zastávce (obchod, bar, pokec, minihra, přesednutí). Pěší zóny se jezdí „mikrovozidly" (koloběžka, kolo, skútr). | Chůze zdvojnásobí práci a rozbije ovládání jedním palcem. |
| R9 | Dialogy NPC jsou předgenerovaný a ručně prošlý pool, žádné LLM za běhu. | Offline hraní, nulové náklady za běh, předvídatelný obsah pro review ve storech. |
| R10 | Žádné reálné značky: auta fiktivní, feed se nejmenuje TikTok, hra se neodkazuje na GTA. Veřejné instituce a památky pod skutečným jménem, komerční podniky fiktivní. | Ochranné známky; podniky navíc zanikají a mění se. |
| R11 | Hry kasinového typu (oko, hold'em) i všechny kostkové hry se hrají o body, ne o sázky. Herní měna nejde koupit za peníze. | Rating a regionální omezení simulovaného hazardu (kap. 14). |
| R12 | Bez backendu ve v1. Balíčky měst jsou statické soubory. Ukládání lokálně. | Offline-first, žádný tracking. |
| R13 | Nástroje v Go, Python jen pro LLM dávky, žádný bash. | Ol1nova konvence. |

## 3. Co v1 není

Multiplayer, interiéry, volná chůze, zbraně, reálné značky, runtime LLM, účty a cloud save, reklamy, loot boxy, nákup herní měny, licencovaná hudba, vlastní editor map.

## 4. Herní smyčka a meta

```
FEED (10–30 s)  →  JÍZDA (1–3 min)  →  MINIHRA (5–10 min)  →  VÝSLEDEK  →  FEED
                     ↑ cestou: drift zóny, fotomísta, obchody, pokec, zvonící budky
```

- **Výsledek minihry:** 0–3 hvězdy, skóre, hotovost, razítko do Pasu.
- **Pas turisty** (hlavní progres): razítka za objevené památky, čtvrti, minihry na 3★, fotomísta. Procento dokončení města.
- **Hotovost:** auta, tuning, kosmetika, suvenýry (sbírka na polici v garáži), občerstvení (malý dočasný bonus k odměně), taxi.
- **Další města:** dostupnost balíčku města řeší monetizace (Q5). Ve hře se do dostupného města cestuje letenkou nebo jízdenkou za herní hotovost, odjezd z nádraží nebo terminálu.
- **Žádný fail state ve světě:** rozbité auto = odtahovka, malý poplatek, respawn u nejbližší garáže.
- **Rychlý přesun:** stanice metra (odemknou se návštěvou) a taxi. „Zajít na pivo" v baru = krátký skit + minihry v baru; po pivu hráč neřídí, hra mu zavolá taxi (placený rychlý přesun). Žádné řízení pod vlivem.
- **Zvonící budky:** telefonní budka u cesty občas zvoní; zvednutí = náhodný motiv s bonusovou odměnou.
- **Cílová seance:** 8–15 minut.

## 5. Svět: pipeline `citypack` a 10 měst

### 5.1 Měřítko a jednotky

- Světová jednotka = 1 metr skutečné geografie. Lokální rovinná projekce od `origin` města (x = Δlon·cos(lat0)·R, y = Δlat·R).
- Vozidla, chodci a rekvizity se kreslí i simulují `car_scale`× větší. Výchozí hodnoty jsou v `tuning.yaml`, ladí se v M0:

```yaml
car_scale: 2.5
lane_width_m: 8.0
sidewalk_width_m: 5.0
view_width_m: {slow: 50, fast: 85}     # přiblížení podle rychlosti
car_anchor: {x: 0.5, y: 0.72}          # pozice auta na obrazovce
extrusion: {k: 0.004, knee_m: 50, exp: 0.85, max_scale: 2.2}
chunk_m: 256
speed_mps: {cruise: 25, top_default: 40}
```

### 5.2 Zdroje dat

| Vrstva | Primární zdroj | Poznámka |
|---|---|---|
| Silnice, mosty, tunely, koleje | Overture `transportation` (segmenty + konektory, `class`, `road_flags`, `level_rules`, `names`) | Počet pruhů: `lanes` byl koncem 2024 ze schématu Overture vyřazen s plánem na redesign — **OVĚŘ** aktuální stav; do té doby default podle třídy, upřesnění z OSM `lanes`. Jednosměrky **OVĚŘ** ve schématu (`access_restrictions` + heading), jinak OSM `oneway`. |
| Budovy a části budov | Overture `buildings` (`building`, `building_part`) | Výška jen u části budov. `building_part` dává stupňovité siluety ikon. |
| Voda, parky, pobřeží, využití území | Overture `base` | |
| Body zájmu | Overture `places` + OSM tagy | Jen jako poloha a kategorie; jména viz R10. |
| Čtvrti | Overture `divisions` (neighborhood; pokrytí **OVĚŘ**), jinak ruční `districts.geojson` | Pro HUD a feed. |
| Výšky – záloha 1 | městská open data | NYC Building Footprints: výška střechy nad terénem. |
| Výšky – záloha 2 | GHSL GHS-BUILT-H | Rastr 100 m, průměrná výška zástavby, stav 2018. Dává „náladu čtvrti" kdekoli na světě. Zvaž i GHS-OBAT (výšky po budovách) — **OVĚŘ** licenci a pokrytí. |

Řetěz výšky budovy: `height` → `num_floors`×3,2 m → městská data → GHSL v těžišti → default podle využití území. Ikony mají vždy ruční `height_m` v `landmarks.yaml`.

Verzi Overture release připni v `city.yaml` (reprodukovatelnost). Přístup k datům přes DuckDB + spatial (GeoParquet); volání z Go buď `go-duckdb`, nebo spuštěním binárky `duckdb` — vyber v M0 podle toho, co bez potíží běží na Mac Mini M2 i na Sparku (ARM64).

### 5.3 Kroky pipeline

`citypack build <city>` provede postupně (každý krok jde spustit zvlášť a má cache):

1. **fetch** – stáhne vrstvy pro `area.geojson` do lokálního GeoParquet.
2. **roads** – ponechá třídy z `road_keep_classes` + ulice z `road_keep_names` + nejkratší spojky, bez kterých by ponechaná síť nebo některý spot nebyl dosažitelný. Výstup: graf (uzly, hrany, jednosměrnost, pruhy, třída, jméno, vrstva −1/0/+1, most/tunel). Zahozené ulice ve výstupu zůstanou jako `alley`: fyzicky průjezdná dlážděná ulička bez provozu a bez GPS (zkratky pro hráče).
3. **widen** – šířka hrany = pruhy × `lane_width_m` + 2 × `sidewalk_width_m`. Budovy se ořežou o buffer silnice (rozdíl polygonů).
4. **buildings** – zjednodušení obrysů (tolerance 1,5 m), sloučení sousedících budov ve stejném výškovém pásmu (0–12, 12–25, 25–50, 50–100, 100–200, 200+ m) do hmot. Ikony a budovy s `building_part` se neslučují. Kde obrysy chybí, vygeneruj hmoty podle GHSL a využití území.
5. **ground** – voda, parky, pobřeží, kolejiště: zjednodušit, triangulovat (earcut). Šířka řek se nemění.
6. **landmarks** – spojení `landmarks.yaml` s geometrií (přes id z Overture/OSM nebo Wikidata), ruční výšky, příznak `hero`.
7. **pois / spots** – kurátorované body (kap. 5.5) přichycené na nejbližší hranu grafu, každý s parkovacím bodem.
8. **pack** – chunky 256 m: Protobuf + gzip, souřadnice v decimetrech (int32). Soubory: `manifest.pb`, `graph.pb`, `chunks/{x}_{y}.pb`, `landmarks.pb`, `spots.pb`. Schéma v `tools/citypack/proto/citypack.proto`, generuje se pro Go i Dart.
9. **validate** – graf je souvislý; každý most a tunel napojen na obou koncích; ze startu existuje trasa ke každému spotu; žádná budova nezasahuje do silnice; žádný chunk nad limit velikosti. Selhání = nenulový exit code.
10. **preview** – vyrenderuje PNG přehledku města a HTML stránku pro porovnání se skutečnou mapou.

Cíl velikosti balíčku: 10–40 MB na město.

### 5.4 Konfigurace města

```yaml
# content/cities/nyc/city.yaml
id: nyc
name: New York
origin: {lat: 40.7580, lon: -73.9855}
drive_side: right            # london, tokyo, hongkong, mumbai: left
units: imperial
area: area.geojson
overture_release: "<připnout v M0>"
height_sources: [overture, nyc_footprints, ghsl]
road_keep_classes: [motorway, trunk, primary, secondary, tertiary]
road_keep_names: [Broadway, Wall Street, Bleecker Street, Canal Street]
style: style.yaml            # paleta, textury fasád, dlažba, mobiliář, počasí, zvuk
```

Okraj mapy: silnice ven končí komickou uzavírkou („Tudy do New Jersey – příště"), ne neviditelnou zdí.

### 5.5 Kurátorovaný obsah na město (checklist „city pack")

| Položka | Počet | Jak |
|---|---|---|
| Ikonické budovy a stavby (`hero`) | 25–40 | ruční seznam, přesná výška, karta „pohlednice" (ilustrace ve stylu hry + 2 věty vlastního textu) |
| Body zájmu: nádraží, divadla, kina, muzea, tržnice, stadiony, vyhlídky, mosty, tunely | 150–300 | návrh z dat podle kategorií, ruční průchod |
| Restaurace, bary, kavárny, obchody | hustota podle dat | poloha z dat, jména fiktivní, typ kuchyně místní |
| Spoty miniher | 40–70 | každá minihra na místě, kam patří (šachy do parku, šipky do hospody) |
| Čtvrti | 15–40 | polygon + jméno do HUD |
| Místní vozidla | 5–8 | viz kap. 10 |
| Místní minihry | 3 | viz kap. 9.4 |
| Style pack | 1 | paleta, fasády, mobiliář, počasí, ambient, rádio |
| Dialogy s místní příchutí | 20 skitů | viz kap. 11 |

### 5.6 Deset měst

Pořadí vydání je zároveň pořadí rostoucí obtížnosti pro pipeline.

| # | Město | Jízda | Nálada | Místní vozidla | Co město prověří |
|---|---|---|---|---|---|
| 1 | New York | vpravo | kaňony mrakodrapů, mřížka, mosty | žlutý taxík, food truck, limuzína | základ; nejlepší data výšek |
| 2 | Praha | vpravo | dlažba, tramvaje, mosty přes Vltavu, věže | lidová škodovka, tramvaj, koloběžka | organická síť, pěší zóny, mikrovozidla; Ol1n ověří věrnost osobně |
| 3 | Londýn | vlevo | křivolaké ulice, Temže, cihla, mrholení | černý taxík, patrový autobus | levostranný provoz |
| 4 | Paříž | vpravo | bulváry, jednotná výška střech, kruhové objezdy | „kachna", skútr | hvězdicové křižovatky |
| 5 | Tokio | vlevo | neon, estakády mezi věžáky, uličky | kei auto, kei náklaďák, taxi | vícevrstvé silnice (řazení estakád, kap. 6.3) |
| 6 | Řím | vpravo | chaos, ruiny, piazzy, skútry | malý městský vůz, tříkolka, skútr | historické jádro bez aut |
| 7 | Istanbul | vpravo | dva kontinenty, Bospor, trajekty, bazar | dolmuš, starý sedan | velká voda, trajekt jako přesun |
| 8 | Hongkong | vlevo | vertikální hustota, přístav, kopce | červený taxík, patrová tramvaj, minibus | extrémní výšky a hustota |
| 9 | Rio de Janeiro | vpravo | pláže, kopce, favely, socha nad městem | „brouk", kombi, moto-taxi | terén a nepravidelná zástavba |
| 10 | Bombaj | vlevo | hustý provoz, promenáda u moře, koloniální centrum | rikša, černožlutý taxík | slabá data výšek → GHSL |

Lavička náhradníků: Mexico City, Berlín, Los Angeles, Sydney, Soul, Káhira, Bangkok, Havana.

**Herní oblast New York:** M0 = Midtown (30th–60th St, od řeky k řece). M1 = Manhattan jižně od 110th St + mosty Brooklyn, Manhattan, Williamsburg a Queensboro s krátkými předmostími. Později: Uptown, pás Brooklynu, Coney Island jako výletní zóna.

## 6. Renderer 2,5D (`packages/world_engine`)

### 6.1 Kamera

Mapa se otáčí, auto jede vždy „nahoru". Auto je na `car_anchor`. Šířka záběru v metrech se plynule mění mezi `view_width_m.slow` a `.fast` podle rychlosti.

### 6.2 Vytažení budov

Úběžník VP = pozice hráčova auta na obrazovce (okolí auta je tak vždy vidět). Bod půdorysu `p` ve výšce `h`:

```
h_eff = h                         pro h ≤ knee_m
h_eff = knee_m + (h − knee_m)^exp pro h > knee_m
s     = min(1 + k · h_eff, max_scale)
p'    = VP + (p − VP) · s
```

Stěna = čtyřúhelník mezi hranou půdorysu a hranou střechy, barva podle světové strany stěny, textura oken z atlasu (u podél stěny, v podle výšky). Střecha = předtriangulovaný půdorys posunutý na `p'`. Budovy s `building_part` se kreslí jako hranoly na sobě.

### 6.3 Pořadí kreslení

1. země, voda, parky (statické `Vertices` na chunk, v cache)
2. silnice, značení, uličky
3. tunelová vrstva −1 (jen když je v ní hráč; strop se skryje)
4. stíny, rekvizity, chodci, vozidla ve vrstvě 0
5. budovy seřazené od nejvzdálenější k nejbližší vůči VP; u každé stěny, pak střecha; vše v jednom bufferu = jedno `drawVertices`
6. mosty a estakády (vrstva +1) a vozidla na nich. Pro NYC stačí kreslit po budovách. Pro Tokio se segmenty estakád zařadí do stejného řazení jako budovy.
7. střechy a detaily ikon, počasí, částice
8. popisky: jména ulic podél osy při nízké rychlosti, HUD „ulice · čtvrť"

Den/noc: tónování + rozsvícená okna na stěnách v noci.

### 6.4 Streaming

Načtené chunky = kruh 3×5 kolem hráče ve směru jízdy. Načítání v isolate. Kolize budov a rekvizity se generují při načtení chunku (rekvizity procedurálně ze seedu chunku, neukládají se).

### 6.5 Rozpočet a záložní žebřík

Cíl: 60 fps, příprava bufferu budov ≤ 4 ms na referenčním telefonu střední třídy (zvol jeden Android, jeden iPhone; zapiš do README). RAM < 600 MB.

Když cíl nevyjde: (1) vytahovat jen N nejbližších a nejvyšších budov, ostatní ploché se stínem; (2) snížit hustotu rekvizit a provozu; (3) teprve potom navrhnout Ol1novi přesun světa do Godotu (v listopadu 2026 stabilní řada 4.7, 4.8 v betě) — to je jeho rozhodnutí, ne tvoje.

## 7. Jízda, provoz, policie (`packages/drive_core`)

### 7.1 Ovládání

V M0 naimplementuj tři schémata, Ol1n vybere dogfoodingem:

- **A (default):** auto přidává samo; palec tažený do stran řídí; tah dolů brzdí a couvá; druhý prst kdekoli = ruční brzda.
- **B:** levá/pravá polovina obrazovky zatáčí, oba palce brzdí.
- **C:** virtuální volant dole + pedál brzdy.

### 7.2 Fyzika

`flame_forge2d` pro tělesa a kolize, vlastní model pneumatik: v každém kroku spočítej boční rychlost a zruš ji impulsem omezeným na `grip`; nad limitem auto klouže = drift. Ruční brzda sníží `grip` zadní nápravy. Asistent kontry v driftu. Parametry auta: `mass, power, brake, grip_front, grip_rear, drift_bias, steer_speed, top_speed`.

Vrstvy −1/0/+1: kolizní filtr podle vrstvy; vrstva auta se mění na rampě (hrana grafu s `layer_from → layer_to`).

Statické kolize: budovy jako řetězové tvary na chunk. Mobiliář (lampy, koše, stánky, hydranty) se dá porazit, po čase se obnoví.

### 7.3 Provoz a chodci

- Auta jedou po pruzích grafu, drží odstup, stojí na semaforech (dvoufázové na křižovatkách hlavních tříd). Hustota podle třídy silnice a denní doby. Vznikají a mizí v prstenci 250 m mimo záběr. `drive_side` z konfigurace města.
- Dynamických těles najednou nejvýš 30.
- Chodci chodí po chodnících, přecházejí na semaforech, před autem vždy uskočí (bublina „!!"). Nelze je srazit.

### 7.4 Policie

Přestupky viděné hlídkou: náraz do auta, jízda po chodníku, převzetí cizího auta, ujetí. Hledanost 1–3. Únik = 10 s mimo dohled. Dopadení = pokuta a krátká animace, žádné násilí.

### 7.5 Výměna aut

Zastav vedle zaparkovaného auta → „Přesednout". Cizí auto = hledanost 1, pokud to vidí hlídka; majitel zavolá hlášku z poolu. Vlastní auta v garážích (několik na město).

## 8. Feed a telefon (`packages/feed_hub`)

Herní telefon se vytahuje tahem od spodního okraje, jízda se zpomalí. Aplikace: **Feed**, Mapa, Garáž, Pas, Foťák, Kontakty, Peněženka, Nastavení.

**Karta feedu** (celá obrazovka):

- teaser: smyčka do 6 s (`teaser.mp4`, 540×960, ≤ 500 kB), záloha animovaný obrázek; v M1 jen portrét hostitele s jemným pohybem
- hostitel: manga postava, jedna zvací věta z poolu
- štítky: typ hry, místo a čtvrť, vzdálenost a čas jízdy, odměna, obtížnost
- gesta: tah nahoru = další · tah vpravo nebo tlačítko „Jedu" = přijmout · dvojité klepnutí = líbí · tah vlevo = tohohle míň

**Výběr karet** (lokálně, bez sítě): balíček 12 karet. Skóre kandidáta = novinka + obliba typu + pásmo vzdálenosti (nejčastěji 1–3 min jízdy) + bonus za nenavštívenou čtvrť nebo neobjevenou památku poblíž. V balíčku vždy aspoň jedna místní hra a jedna jízdní výzva. Po 12 kartách konec balíčku („Běž si zajezdit"), žádné nekonečné scrollování.

Po přijetí: trasa A* po grafu, čára na silnici, šipka na okraji obrazovky, HUD se jménem cíle.

## 9. Minihry

### 9.1 Kontrakt (`packages/mg_api`)

```dart
class MinigameMeta {
  final String id;              // 'oko'
  final String engine;          // 'cards'
  final Duration targetLength;  // 5–10 min
  final Set<String> cities;     // prázdné = všude
  final bool casinoLike;        // pro rating a regionální vypínač
}

class MinigameContext {
  final String cityId;
  final MinigameSkin skin;      // paleta, stůl, pozadí, figurky
  final int difficulty;         // 1..5
  final int seed;               // determinismus pro testy
  final NpcPersona? opponent;   // portrét + hlášky
  final Locale locale;
}

class MinigameResult {
  final int stars;              // 0..3
  final int score;
  final Duration played;
  final bool aborted;
}

abstract class Minigame {
  MinigameMeta get meta;
  Widget build(MinigameContext ctx, void Function(MinigameResult) onFinish);
}
```

### 9.2 Pravidla pro každou minihru

- na výšku, jedna ruka, offline, pauza kdykoli
- tvrdý strop 10 minut: po něm rozhoduje stav (body, materiál) nebo náhlá smrt
- návod nejvýš 3 karty; 3 úrovně soupeře
- pravidla jako čistá logika bez UI, deterministická ze `seed`, pokrytá unit testy
- vlastní balíček `packages/mg_<id>`, závisí jen na `mg_api` a svém enginu
- spustitelná samostatně z ladicí „Galerie miniher" (bez jízdy)
- v produktu generický název: řada klasik má chráněné jméno (Skee-Ball, Othello, Yahtzee, UNO, Connect 4, Tetris, UFO Catcher) — **OVĚŘ** před vydáním
- před implementací jednostránková specifikace `content/minigames/<id>.md`: pravidla, mapování výsledku na hvězdy, úrovně AI, jak se vynutí strop 10 min, sloty skinu

### 9.3 Enginy

| Engine | Co umí | Her |
|---|---|---|
| `cards` | balíčky, ruce, štychy/odhazování, AI | 8 |
| `board` | mřížka, figurky, tahy, minimax/MCTS | 13 |
| `dice` | hody, bodovací tabulky, riskování | 5 |
| `tiles` | kameny, sady, postupky | 4 |
| `flick` | 2D fyzika, míření a síla tahem prstu | 15 |
| `rhythm` | časová osa, dráhy, okna zásahu | 5 |
| `arcade` | jednoobrazovkové akční a reflexní hry | 18 |
| `puzzle` | mřížkové hlavolamy, kvíz | 6 |
| `drive` | výzvy přímo ve městě, používá `drive_core` | 13 |
| `service` | obsluha objednávek na čas | 4 |
| `sport` | míč + hráči, jednoduchá 2D fyzika | 9 |

### 9.4 Seznam 100 miniher

⚠ = kasinový typ (R11). ♻ = kandidát na převzetí kódu z existujícího Ol1nova projektu; před použitím zkontroluj stav repozitáře.

**Univerzální (70) — ve všech městech, skin a místo podle města**

| # | Minihra | Engine | Poznámka |
|---|---|---|---|
| 1 | Oko bere (jednadvacet) ⚠ | cards | o body, první do 5 vyhraných kol |
| 2 | Prší | cards | mau-mau |
| 3 | Žolíky | cards | rummy |
| 4 | Srdce | cards | hearts |
| 5 | Solitaire | cards | klondike |
| 6 | Rychlík | cards | rychlá karetka pro dva ♻ Fuse |
| 7 | Hold'em o žetony ⚠ | cards | turnaj 3 hráčů, žetony existují jen v partii |
| 8 | Šachy – bleskovka | board | ♻ logika z PrincessChess |
| 9 | Dáma | board | varianta pravidel podle města |
| 10 | Mlýn | board | |
| 11 | Piškvorky | board | |
| 12 | Reversi | board | |
| 13 | Člověče, nezlob se | board | |
| 14 | Vrhcáby | board | v Istanbulu skin „tavla" |
| 15 | Lodě | board | |
| 16 | Čtyři v řadě | board | |
| 17 | Mankala | board | |
| 18 | Go 9×9 | board | |
| 19 | Desetitisíc | dice | české kostky |
| 20 | Kostkový poker | dice | tabulka kombinací |
| 21 | Lhářské kostky | dice | blafování |
| 22 | Prase | dice | riskuj, nebo zapiš |
| 23 | Domino | tiles | |
| 24 | Mahjong solitaire | tiles | párování kamenů |
| 25 | Kulečník 8-ball | flick | |
| 26 | Šipky 301 | flick | |
| 27 | Bowling | flick | |
| 28 | Minigolf | flick | dráhy s místními památkami |
| 29 | Šoupaná (shuffleboard) | flick | |
| 30 | Střelnice | flick | ♻ Kačeny |
| 31 | Plechovky | flick | pouťové shazování |
| 32 | Žabky | flick | házení placáků po místní řece |
| 33 | Pouliční bubeník | rhythm | |
| 34 | Taneční battle | rhythm | |
| 35 | DJ set | rhythm | |
| 36 | Bouchni krtka | arcade | |
| 37 | Had | arcade | |
| 38 | Cihly | arcade | breakout |
| 39 | Holubi útočí | arcade | vertikální střílečka ♻ Kiran |
| 40 | Přes ulici | arcade | přeběhni bulvár |
| 41 | Pinball | arcade | stůl s motivem města |
| 42 | Mrakodrap | arcade | stavění pater na přesnost |
| 43 | Holub | arcade | prolétávání mezi věžáky |
| 44 | Kurýr | arcade | běh po chodníku |
| 45 | Fukar | arcade | ♻ Puff |
| 46 | U-rampa | arcade | ♻ RattleRamp |
| 47 | Posuvné puzzle | puzzle | obrázek památky |
| 48 | Skládačka panoramatu | puzzle | |
| 49 | Skladník | puzzle | sokoban |
| 50 | Sirky | puzzle | duel: 15 sirek, bereš 1–3, kdo vezme poslední, prohrál · hlavolam: přelož sirky do zadaného obrazce na čas |
| 51 | Spoj linky | puzzle | propoj stanice metra |
| 52 | Městský kvíz | puzzle | poznej památku nebo čtvrť |
| 53 | Taxi | drive | cestující chtějí na skutečná místa |
| 54 | Rozvoz jídla | drive | |
| 55 | Drift zóna | drive | body za drift na křižovatce nebo objezdu |
| 56 | Sprint A→B | drive | |
| 57 | Časovka | drive | okruh kolem památky |
| 58 | Parkování | drive | |
| 59 | Únik | drive | setřes hlídku |
| 60 | Foto-tour | drive | 5 památek, zarámuj fotku |
| 61 | Autobusák | drive | linka podle jízdního řádu |
| 62 | Kaskadér | drive | rampy a skoky |
| 63 | Stánek s jídlem | service | místní street food |
| 64 | Barman | service | |
| 65 | Barista | service | latte art |
| 66 | Stolní fotbal | sport | |
| 67 | Stolní tenis | sport | |
| 68 | Penalty | sport | |
| 69 | Streetball trojky | sport | |
| 70 | Vzdušný hokej | sport | |

**Místní (30) — tři na město**

| # | Město | Minihra | Engine | Poznámka |
|---|---|---|---|---|
| 71 | New York | Koulená na boardwalku | flick | koule do kruhů s body |
| 72 | New York | Stickball | sport | pálka z násady v ulici |
| 73 | New York | Double Dutch | rhythm | dvě švihadla |
| 74 | Londýn | Snooker | flick | |
| 75 | Londýn | Kaštany (conkers) | arcade | |
| 76 | Londýn | Taxikářská zkouška | drive | dojeď k cíli bez GPS |
| 77 | Paříž | Pétanque | flick | |
| 78 | Paříž | 421 | dice | barová kostková hra |
| 79 | Paříž | Závod číšníků | service | podnos v běhu |
| 80 | Řím | Scopa | cards | |
| 81 | Řím | Morra | arcade | odhad součtu prstů |
| 82 | Řím | Skútrem přes piazzu | drive | slalom na skútru |
| 83 | Praha | Kuličky | flick | do důlku |
| 84 | Praha | Čára | flick | mince co nejblíž čáře |
| 85 | Praha | Nohejbal | sport | |
| 86 | Istanbul | Okey | tiles | |
| 87 | Istanbul | Rybaření z mostu | arcade | |
| 88 | Istanbul | Chyť zmrzlinu | arcade | zmrzlinář uhýbá kornoutem |
| 89 | Tokio | Jeřáb na plyšáky | arcade | |
| 90 | Tokio | Lovení rybek | arcade | papírová síťka se trhá |
| 91 | Tokio | Mini-šógi 5×5 | board | |
| 92 | Hongkong | Mahjong (zjednodušený) | tiles | |
| 93 | Hongkong | Čínské šachy | board | xiangqi |
| 94 | Hongkong | Dračí lodě | rhythm | pádlování do rytmu |
| 95 | Rio | Futevôlei | sport | nohejbal na pláži |
| 96 | Rio | Knoflíkový fotbal | flick | |
| 97 | Rio | Souboj draků | arcade | přeřízni soupeři šňůru |
| 98 | Bombaj | Carrom | flick | |
| 99 | Bombaj | Gully cricket | sport | kriket v uličce |
| 100 | Bombaj | Rozvoz obědů | drive | krabičky podle kódů |

### 9.5 Minihry pro M1

| Minihra | Pravidla v kostce | Hvězdy |
|---|---|---|
| Sirky (duel) | 15 sirek (v dalších kolech náhodně 12–25), střídavě se bere 1–3, kdo vezme poslední, prohrál; začínající se střídá; první do 5 kol. AI: optimální tah nechá soupeři počet ≡ 1 (mod 4), obtížnost = pravděpodobnost chyby. Režim hlavolam až v M2. | 5:≤2 = 3★, 5:3 = 2★, 5:4 = 1★ |
| Oko bere | 52 karet, líznout/stát, bankéř stojí na 17, bez sázek a bez dělení; první do 5 kol | 5:≤2 = 3★, 5:3 = 2★, 5:4 = 1★ |
| Dáma | 8×8, povinné braní; strop 8 min, pak rozhoduje materiál | výhra do 4 min 3★, výhra 2★, výhra na materiál 1★ |
| Desetitisíc | 6 kostek, 1=100, 5=50, trojice = 100× hodnota (jedničky 1000), postupka 1500; hraje se do 5000, nejvýš 10 kol | podle náskoku |
| Šipky 301 | míření tahem, kolébání zaměřovače podle obtížnosti; jeden leg proti NPC | podle počtu šipek |
| Střelnice | 3 kola po 90 s | prahy skóre |
| Taxi | směna 4 min, cestující jmenují skutečné cíle | prahy tržby |
| Koulená | 3 série po 9 koulích, kruhy 10–100 | prahy skóre |

## 10. Auta

- **Definice:** `content/cars/<id>.json` — třída, rozměry, parametry z 7.2, sedadla, štítky (město), cena, vzácnost, sloty tuningu.
- **Počty:** M1 5 aut · M2 40 · cíl 200+ (≈ 40 karoserií × ročníky, výbavy a polepy).
- **Třídy:** mini, hatchback, sedan, kombi, kupé, muscle, supersport, veterán, terénní, pick-up, dodávka, taxi, limuzína, autobus, mikro (koloběžka, kolo, skútr), speciální (food truck, tříkolka, rikša).
- **Grafika:** pohled kolmo shora. Vektorová maska karoserie určuje měřítko i kolizi → malba do masky přes ComfyUI (flux + ControlNet) → zvlášť maska laku (barva se tónuje za běhu) → kola jako samostatné sprity (natáčení). Nejdřív 5 aut na ověření postupu, potom hromadná výroba.
- **Tuning:** motor, pneumatiky, brzdy, odlehčení, nastavení driftu.
- **Kosmetika:** lak, polepy, kola, podsvícení, barva kouře, klakson, samolepky.
- **Jména:** fiktivní značky a modely, tvary „inspirované dobou a třídou", ne kopie konkrétního vozu.

## 11. NPC a dialogy (`packages/npc_dialogue`)

- **Postavy:** manga portréty, všichni zjevně dospělí (21+), přitažliví, flirt hravý, nic explicitního. M1: 6 postav. Cíl: 24 na město.
- **Archetypy (16):** např. influencerka, barista hipster, surfař, knihomolka, taxikář filozof, fitness nadšenec, gotička, ztracený turista, pouliční muzikant, manažer ve spěchu.
- **Skit:** NPC věta → hráč volí 1 ze 3 odpovědí (flirt / vtip / suchar) → reakce podle tónu → … celkem 5 replik NPC, pak konec. Hra se nemění. Jediný důsledek: ukazatel „vibe" a šance na kontakt do telefonu; kontakty se pak objevují jako hostitelé karet ve feedu.
- **Pool:** skity mají klíč (archetyp, kontext, volitelně město). Kontexty: ulice, bar, obchod, soupeř v minihře (výhra/prohra), po nehodě, majitel převzatého auta. Postava si losuje ze svého poolu; fronta posledních K skitů brání opakování; po vyčerpání se pool točí dokola.
- **Rozsah:** M1 30 skitů. Cíl v1: 16 archetypů × 12 obecných + 10 měst × 20 místních = 392 skitů (≈ 2 000 replik NPC, ≈ 3 500 odpovědí hráče).
- **Výroba:** `tools/dialoggen` (Python) generuje dávky přes lokální LLM bránu do JSON → ruční průchod v revizním UI → lokalizační pipeline.
- **Mantinely generátoru:** jen dospělí; žádní skuteční lidé; žádné vtipy na národnost nebo původ (místní příchuť = místa, jídlo, počasí, doprava); žádný explicitní obsah.
- **Hlas:** ve v1 bez dabingu, textové bubliny + krátké „blip" zvuky podle archetypu.

## 12. Výtvarno a zvuk

- **Svět:** plochý vektorový styl, výrazná paleta na město, textury fasád z atlasu. Před M1 udělej style board (aspoň 4 varianty) k Ol1novu výběru.
- **Postavy, karty památek, teasery feedu:** ComfyUI na Sparku; teasery později přes existující video pipeline.
- **Hudba a zvuk:** vlastní nebo volně licencované; rádio v autě se stanicemi podle města; ambient podle čtvrti. Žádné reálné skladby.

## 13. Architektura repa

```
metropole/
  app/                      Flutter aplikace: shell, navigace, nastavení
  packages/
    world_engine/           načítání citypacku, renderer, kamera, streaming
    drive_core/             fyzika, ovládání, provoz, chodci, policie
    feed_hub/               telefon, feed, výběr karet
    mg_api/                 kontrakt miniher
    mg_engine_<x>/          11 enginů
    mg_<id>/                jednotlivé minihry
    npc_dialogue/           pool, přehrávač skitů
    meta_progress/          save (SQLite), ekonomika, Pas
  tools/
    citypack/               Go CLI: fetch, build, validate, preview
    dialoggen/              Python: dávky dialogů
    artgen/                 workflow pro ComfyUI + ovladač
  content/
    cities/<id>/            city.yaml, area.geojson, landmarks.yaml, spots.yaml, style.yaml
    cars/  dialogues/  minigames/
    tuning.yaml
  plans/                    pod-plány milníků
```

Konvence (state management, lint, i18n) převezmi z ostatních Ol1nových Flutter projektů; pokud v repu žádná není, Riverpod. Ladicí režimy: Galerie miniher, prohlížeč města (volná kamera, vrstvy, graf), overlay FPS a časů.

Distribuce balíčků měst: statické soubory na CDN, stažení při odemčení města. První město je v instalaci.

## 14. Licence, právo, story

Nejsem právník; tohle je seznam věcí k ohlídání, ne právní posudek.

- **Atribuce map:** obrazovka „O mapách" dostupná z menu + řádek v popisu ve storech: © OpenStreetMap contributors (ODbL), Overture Maps Foundation, GHSL (CC BY 4.0), městská open data podle města.
- **ODbL share-alike:** hra jako výsledné dílo může mít vlastní licenci, ale odvozenou databázi je třeba na požádání poskytnout pod ODbL. Nejjednodušší splnění: citypacky a konfigurace pipeline zveřejnit ve veřejném repozitáři pod ODbL.
- **Značky:** R10. Seznam vyhrazených názvů her v 9.2.
- **Památky:** skutečná jména, vlastní stylizované ilustrace, vlastní texty. Žádné převzaté fotografie.
- **Rating:** alkohol (bary), flirt, hry kasinového typu. Cíl Apple 13+. Držet: kasinových her jen pár, bez sázek, měna nejde koupit. `casinoLike` hry jdou regionálně vypnout jedním přepínačem (Austrálie dává za jakýkoli simulovaný hazard R18+; Google Play simulovaný hazard v některých zemích blokuje).
- **Monetizace (default, viz kap. 16):** hra zdarma s prvním městem; další města jednorázový nákup; kosmetika za herní hotovost. Bez reklam, bez trackingu.

## 15. Milníky

### M0 – Hračka

**Cíl:** jezdit po Midtownu a chtít jezdit dál.

Rozsah:
1. `citypack` pro oblast M0: kroky fetch → pack → validate → preview.
2. `world_engine`: načtení, streaming, renderer podle kap. 6, den/noc přepínačem.
3. `drive_core`: jedno auto, fyzika podle 7.2, tři schémata ovládání, kolize s budovami a mobiliářem, mosty a tunely ve vrstvách.
4. HUD: ulice · čtvrť, rychlost, FPS overlay. Ladicí panel pro `tuning.yaml` za běhu.
5. Web build téhož (odkaz na sdílení).

Bez provozu, chodců, policie, feedu, miniher, ukládání.

Akceptace:
- 60 fps na obou referenčních telefonech při průjezdu Times Square a po 42nd St od řeky k řece
- `citypack validate nyc` projde
- Empire State, Chrysler, Grand Central, Times Square a okraj Central Parku jsou na místě a k poznání (slepý test na 3 lidech: „kde to je?")
- Ol1n po týdnu dogfoodingu vybere schéma ovládání a potvrdí hodnoty v `tuning.yaml`
- rozhodnutí R3: pokračovat ve Flutteru, nebo záložní žebřík

### M1 – Vertikální řez

**Cíl:** celá smyčka feed → jízda → minihra → výsledek, hratelná 10× za sebou.

Rozsah (každý bod samostatná feature, v tomto pořadí):
1. Oblast M1, graf, GPS trasa, mosty.
2. Provoz a semafory. 3. Chodci s uskakováním. 4. Policie, hledanost 1–2.
5. `mg_api` + Galerie miniher + enginy `puzzle`, `cards`, `board`, `dice`, `flick`, `drive`.
6. Osm miniher z 9.5, každá se spotem na autentickém místě. Sirky postav jako první: nejjednodušší hra slouží jako referenční implementace kontraktu.
7. Telefon s Feedem (balíček 6 karet) a Mapou.
8. 5 aut, přesedání, 1 garáž.
9. 20 památek s kartou „pohlednice", Pas s razítky.
10. `npc_dialogue`: 6 postav, 30 skitů, pokec na ulici a soupeř v minihře.
11. Výsledková obrazovka, hotovost, ukládání.
12. Obrazovka „O mapách".

Akceptace:
- 10 smyček za sebou bez pádu a bez zaseknutí
- každá minihra projde unit testy pravidel a jde spustit z Galerie
- dogfooding: průměrná seance ≥ 10 min, Ol1n se k hře vrátí bez nucení tři dny po sobě
- interní build v TestFlightu a v Play internal testing

### Dál (pod-plány po M1)

| Milník | Obsah |
|---|---|
| M2 – New York naplno | 30 miniher, 40 aut, tuning a kosmetika, hledanost 3, obchody, bary, taxi, metro, budky, fotomísta, rádio, počasí; soft launch |
| M3 – Praha | zobecnění pipeline, pěší zóny a mikrovozidla, tramvaje, přepínání měst, 3 místní hry |
| M4 – Londýn | levostranný provoz, 60 miniher celkem |
| M5 – Paříž, Tokio | estakády ve více vrstvách, 80 miniher |
| M6+ | zbylá města po jednom, 100 miniher, 200+ aut |

## 16. Otevřené otázky pro Ol1na

| # | Otázka | Default, dokud neřekne jinak |
|---|---|---|
| Q1 | Bez zbraní a bez srážení chodců — platí? | ano (R7) |
| Q2 | Kasinové hry o body místo sázek — platí? Se sázkami hrozí na Applu vyšší věková kategorie (časté simulované sázení = 18+). | o body (R11) |
| Q3 | Skutečná jména podniků (restaurace, kina)? | fiktivní; instituce a památky skutečné |
| Q4 | Brát cizí auta jako v GTA, nebo jen vlastní garáž? | brát lze, za cenu hledanosti |
| Q5 | Monetizace: města jako jednorázové nákupy, zařazení do Ol1n Pass? | první město zdarma, další placená |
| Q6 | Volná chůze? | ne (R8) |
| Q7 | Druhé město Praha, nebo rovnou Londýn? | Praha |
| Q8 | Název hry a název feedu | Metropole / Feed |

## 17. Zdroje

- Overture – budovy (licence, výšky): https://docs.overturemaps.org/guides/buildings
- Overture – schéma segmentu silnic: https://docs.overturemaps.org/schema/reference/transportation/segment/
- Overture – vyřazení `lanes` ze schématu: https://docs.overturemaps.org/blog/2024/12/18/transportation-to-ga/
- OSM – atribuce: https://osmfoundation.org/wiki/Attribution
- OSM – licence a právní FAQ: https://osmfoundation.org/wiki/Licence_and_Legal_FAQ
- GHSL GHS-BUILT-H: https://registry.opendata.aws/ghs-built-h/
- NYC Building Footprints (metadata): https://github.com/CityOfNewYork/nyc-geo-metadata/blob/master/Metadata/Metadata_BuildingFootprints.md
- flame_3d: https://pub.dev/packages/flame_3d
- Godot – vydání: https://godotengine.org/news
- Apple – věková hodnocení: https://developer.apple.com/help/app-store-connect/reference/age-ratings
- Apple – regionální hodnocení Austrálie a Francie: https://developer.apple.com/news/?id=4mfp130q
- Google Play a simulovaný hazard (případ Luck be a Landlord): https://www.techradar.com/gaming/satirical-indie-game-luck-be-a-landlord-banned-in-13-countries-by-google

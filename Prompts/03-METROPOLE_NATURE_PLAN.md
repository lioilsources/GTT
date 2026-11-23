# METROPOLE_NATURE_PLAN.md

**Stav:** inkrement. Starší plány se nemění, tento dokument je doplňuje.
**Datum:** 2026-11-23
**Pro:** kódovací model (Opus, střední effort). **OVĚŘ** = ověř v dokumentaci nebo v datech, než na tom postavíš kód. Kapitola 10 = rozhoduje Ol1n, do té doby platí default.

**Pořadí platnosti** (novější má při rozporu přednost):

1. `METROPOLE_PLAN.md`
2. `METROPOLE_DUALSTACK_PLAN.md`
3. `METROPOLE_TERRAIN_PLAN.md`
4. tento dokument

**Co doplňuje nebo mění:**

| Plán | Místo | Změna |
|---|---|---|
| hlavní | 5.1 | stromy se neškálují `car_scale`, mají vlastní herní rozměry |
| hlavní | 5.3 | nový krok pipeline `nature` za krokem `ground` |
| hlavní | 6.3 | pořadí kreslení: přibývají koruny stromů a lesní hmoty |
| hlavní | 7.2 | povrchy s různou přilnavostí, stromy a lesy jako překážky, pád do vody |
| dual-stack | 5.1 | `design/tokens.json` dostane vyhrazené barvy vody a zeleně |
| terén | 3.3, kap. 4 | nová pole v citypacku, krok `nature` se řadí za `elevation` |
| terén | 7.2, kap. 8 | voda a zeleň v šikmém pohledu a v prstenci `lod` |
| terén | kap. 10 | práce N0–N2 se přidává k fázím T0–T2 |

Plán funguje i bez terénu: kde citypack nemá výšky, je voda i zeleň v rovině.

---

## 1. Cíl

Voda a zalesněné parky jsou hlavní orientační body města. Hráč je musí poznat na první pohled, z dálky i na mapě, a ve všech městech stejně:

- řeka, přístav a moře jsou vždy modré a nic jiného modré není
- park není zelená skvrna, ale stromy: les, parková zeleň, louka
- obojí má jméno, které se ukazuje ve světě, v HUD i na mapě v telefonu

## 2. Rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| N1 | Vyhrazené barvy: modrá jen pro vodu, zelená jen pro zeleň. Platí ve všech městech, v obou klientech i na mapě v telefonu. Paleta města smí měnit jen odstín a světlost v povoleném rozsahu. | Orientace se nesmí učit v každém městě znovu. |
| N2 | Tři podoby zeleně: **les** = souvislá hmota korun, **parková zeleň** = jednotlivé stromy, **louka** = otevřená plocha. | Park má strukturu, podle které se dá orientovat i uvnitř. |
| N3 | Stromy a lesy jsou data v citypacku. | Stejné polohy a stejné kolize v obou klientech. |
| N4 | Nic se nevymýšlí. Stromořadí jen tam, kde je v datech. Uvnitř parků se stromy rozmisťují podle skutečných tříd ploch. | Pilíř „město je skutečné". |
| N5 | Souvislý les je pro auta neprůjezdný, vedou jím jen cesty. Parková zeleň a louky jsou průjezdné. | Čitelnost shora (auto pod korunami není vidět) a počet stromů. |
| N6 | Voda je neprůjezdná. Pád do vody = šplouchnutí a odtahovka. | Řeka je skutečná hranice, most má smysl. |
| N7 | Všechno je přídavné. Citypack bez těchto polí dál funguje. | Hlavní plán běží. |

## 3. Data

### 3.1 Zdroje

| Co | Zdroj | Poznámka |
|---|---|---|
| Voda | Overture `base` / `water` | moře z pobřežní čáry OSM; podtypy oceán, jezero, rybník, nádrž, řeka, potok, kanál; prvky určené jen pro popisky odfiltruj (**OVĚŘ** ve schématu) |
| Parky a využití území | Overture `base` / `land_use` | překlad značky `landuse` z OSM |
| Lesy, tráva, písek | Overture `base` / `land` | přírodní plochy z OSM; názvy tříd **OVĚŘ** |
| Pokryv z družice | Overture `base` / `land_cover` | odvozeno z ESA WorldCover 10 m; jen k rozdělení velkých parků bez vnitřních ploch |
| Jednotlivé stromy | městský inventář, jinak body a stromořadí z OSM | New York: 2015 Street Tree Census (druh a průměr kmene); aktuálnější jsou sady ForMS; Praha **OVĚŘ** |

Téma `base` je pod ODbL, platí pro něj stejný režim jako pro ostatní mapová data (hlavní plán kap. 14).

### 3.2 Třídy

**Voda**

| Třída | Z čeho | Vzhled |
|---|---|---|
| `sea` | oceán, záliv, přístav | nejtmavší modrá, dlouhá vlna |
| `river` | řeka; potok širší než 6 m | střední modrá |
| `canal` | kanál | střední modrá, rovný břeh |
| `lake` | jezero, rybník, nádrž | světlejší modrá |
| `small` | plocha pod 400 m² (fontána, bazén) | světlá, bez animace |

**Zeleň a povrchy**

| Třída | Stromy | Povrch | Průjezdné |
|---|---|---|---|
| `wood` (les) | hmota korun + stromy po obvodu | — | ne, jen po cestách |
| `parkland` (parková zeleň) | 35 na hektar | tráva | ano |
| `garden` | 40 na hektar | tráva | ano |
| `cemetery` | 25 na hektar | tráva | ano |
| `grass` (louka, hřiště) | žádné | tráva | ano |
| `sand` (pláž) | žádné | písek | ano |

Rozdělení parku: voda má přednost před lesem, les před loukou a hřištěm, zbytek parku je `parkland`. Park nad 5 ha bez vnitřních ploch v datech se rozdělí podle `land_cover`: souvislý stromový pokryv nad 0,5 ha je `wood`.

### 3.3 Konfigurace

```yaml
# content/tuning.yaml
nature:
  tree_sizes:                 # herní metry, bez car_scale
    S: {crown_r: 4, height: 9}
    M: {crown_r: 6, height: 14}
    L: {crown_r: 8, height: 20}
  trees_per_ha: {parkland: 35, garden: 40, cemetery: 25}
  trees_per_chunk_max: 600
  wood: {canopy_height_m: 14, inset_m: 4, edge_tree_step_m: 10, path_clear_m: 3}
  shore_band_m: 6
  trunk_radius_m: 0.8
  grip: {asphalt: 1.0, dirt: 0.8, grass: 0.75, sand: 0.6}
  crown_fade: {radius_m: 14, alpha: 0.35}
  water_fall: {sink_s: 1.2}
```

## 4. Pipeline: krok `nature`

Pořadí: … → ground → (elevation) → **nature** → landmarks → pois → pack → …

1. **classify** – převeď vodu a zeleň do tříd z 3.2. Zjednoduš obrysy (tolerance 2 m), šířku řek neměň.
2. **cut** – od zeleně odečti silnice, budovy a vodu. Silnice, která vede přes vodu a není most ani tunel, je chyba dat: vypiš ji.
3. **wood** – polygon lesa zmenši o `inset_m` a odečti pásy cest a uliček (šířka + `path_clear_m` na každou stranu). Výsledek je lesní hmota s kolizí. Po obvodu rozmísti stromy po `edge_tree_step_m` s náhodným posunem.
4. **trees** – v tomto pořadí:
   - stromy z městského inventáře (velikost podle průměru kmene)
   - body stromů a stromořadí z OSM
   - v třídách s hustotou z `trees_per_ha` rozmístění Poissonovým diskem; seed = hash(město, chunk), aby byl výstup opakovatelný
   - žádný strom blíž než `crown_r` k silnici, budově nebo vodě; nad `trees_per_chunk_max` proředit rovnoměrně
5. **shore** – pruh mělčiny `shore_band_m` uvnitř vody podél břehu.
6. **labels** – jméno a osa popisku pro vodu nad 2 ha a zeleň nad 1 ha; jméno v místním jazyce.
7. **spots** – každý spot a bod zájmu dostane `area_name`, pokud leží v parku nebo do 150 m od pojmenované vody („Washington Square Park", „u Hudsonu"). Karta feedu to zobrazí u místa.
8. **lod** – pro vzdálený prstenec: voda jako jedna plocha, `wood` i `parkland` jako nízké zelené hmoty (14 m a 8 m).

**validate** navíc: žádný strom na silnici, v budově ani ve vodě; každá cesta lesem má průjezdný koridor; počet stromů na chunk pod limitem; voda nad 5 ha má jméno.

**preview** navíc: mapa tříd vody a zeleně s hustotou stromů a se jmény.

### Co přibude v citypacku

| Kde | Pole | Popis |
|---|---|---|
| voda | `class`, `name`, osa popisku, pruh mělčiny | |
| zeleň | polygony s `class`, `surface`, `name` | |
| `chunks/*.pb` | `trees`: 3 bajty na strom | poloha po 1 m v chunku, velikost S/M/L |
| `chunks/*.pb` | `woods`: polygon + výška | lesní hmota, kreslí se i koliduje jako nízká budova |
| `spots.pb` | `area_name` | |
| `lod/*.pb` | plocha vody, zelené hmoty | |

Nejvýš 1,8 kB stromů na chunk.

## 5. Vykreslení

### 5.1 Barvy

`design/tokens.json` dostane `color.water.{sea,river,lake,small,shore,line}` a `color.green.{wood,parkland,grass,crown,trunk}`. Žádný jiný povrch, budova ani prvek UI nesmí použít odstín z rozsahu vody nebo zeleně; `metro validate` to hlídá u palet měst.

### 5.2 Voda (oba klienti)

- výplň podle třídy, světlejší pruh mělčiny, tmavší linka břehu
- stín mostu jako tmavý pás na hladině
- jméno podél osy (stejný styl jako jména ulic, kurzívou)
- vlnění: **F** posuvná textura přes `ImageShader` s nízkou průhledností, na nízké kvalitě vypnuto; **W** rovina ve výšce hladiny s jednoduchým shaderem (dvě posuvné vrstvy šumu, v šikmém pohledu odlesk slunce), neprůhledná

### 5.3 Zeleň v pohledu shora (oba klienti)

- louka a parková zeleň: plocha v zelené z tokenů
- strom: tmavá tečka kmene na zemi + koruna ve výšce stromu. Koruna se promítá stejně jako střecha budovy, takže se při jízdě vůči kmeni posouvá.
- les: nízká „budova" se zelenou strukturovanou střechou a tmavšími stěnami, obvod rozbitý stromy
- koruna do `crown_fade.radius_m` od hráčova auta zprůhlední
- jméno parku uprostřed plochy; HUD „ulice · čtvrť" ukáže jméno parku, když je v něm hráč

Pořadí kreslení ve F (doplňuje hlavní plán 6.3): země a voda → silnice → stíny, rekvizity, chodci, vozidla → **koruny stromů od nejvzdálenější** → budovy a **lesní hmoty** ve společném řazení → mosty → popisky.

### 5.4 Navíc ve W

- stromy jako thin instances tří nízkopolygonových modelů (S/M/L), barva s malou náhodnou odchylkou; za 300 m se nekreslí
- lesní hmota jako síť se zvlněným vrškem
- v šikmém pohledu je voda vidět až k horizontu a parky jako zelené hmoty z `lod`

### 5.5 Mapa v telefonu

Stejné barvy. Voda a parky jsou na mapě vždy, ve všech přiblíženích, se jmény seřazenými podle plochy.

## 6. Jízda

- **Povrchy:** přilnavost se násobí hodnotou z `grip` podle povrchu pod autem.
- **Stromy:** kmen je pevný kruh o poloměru `trunk_radius_m`. Fyzická tělesa mají jen stromy do 80 m od hráče, nejvýš 200 najednou.
- **Les:** lesní hmota je pevný polygon. Cesty lesem jsou uličky z hlavního plánu (průjezdné, bez provozu a bez GPS).
- **Voda:** když střed auta ve vrstvě 0 vjede do vody, auto se za `sink_s` potopí a hráč se objeví na nejbližším uzlu silnice s poplatkem za odtahovku (hlavní plán kap. 4). Z mola nebo nábřeží se dá sjet, žádná neviditelná zeď.
- **Provoz a chodci:** auta AI zůstávají na silnicích. Chodci chodí parkem po cestách.
- **Lodě:** jen kulisa, nejvýš 6 viditelných, po trasách trajektů z dat (**OVĚŘ**, kde je v Overture najít); kde trasy nejsou, lodě nejsou.

## 7. Parita a rozpočty

- **Parita:** třídy, stromy, lesní hmoty a jména jsou data, tedy shodné. Přilnavost povrchů, kolize se stromy a pád do vody jsou P1. Vlnění a vzhled korun P2. Barvy z tokenů jsou závazné pro oba klienty.
- **Scénáře P1:** brzdná dráha na trávě a na písku proti asfaltu; průjezd parkovou zelení z nahraných vstupů (stejný počet nárazů do stromů); vjezd do vody (respawn na stejném uzlu).
- **Rozpočet F:** nejvýš 2 500 korun najednou, +1,5 ms; voda jedním voláním na třídu.
- **Rozpočet W:** nejvýš 6 000 instancí stromů, +6 draw calls; voda nejvýš 2 draw calls.
- Při překročení se nejdřív zkrátí vzdálenost kreslení korun, potom se vypne vlnění.

## 8. Fáze

| Fáze | Obsah | Kdy | Akceptace |
|---|---|---|---|
| **N0 – Data** | krok `nature`, pole v citypacku, validate, preview; New York | hned v session SHARED, s T0 nebo samostatně; klienty nemění | na náhledu má Central Park lesy, louky a vodní plochy na správných místech; Hudson, East River a Harlem River mají jména; stromy z inventáře stojí podél ulic; citypack bez nových polí dál funguje |
| **N1 – Pohled shora a jízda** | 5.1–5.3, 5.5 a kap. 6 v obou klientech, scénáře | po bráně M0, společně s T1 | slepý test na 3 lidech: ze snímku bez popisků do 2 s ukážou řeku a park; scénáře v toleranci; 60 fps drží |
| **N2 – Šikmý pohled** | 5.4, `lod`, lodě | společně s T2 | z Brooklynského mostu je v šikmém pohledu čitelná řeka i panorama; Central Park je z 1 km vidět jako zelená hmota; 60 fps drží |

Položky N0–N2 zapiš do `plans/progress.yaml`, pokud se postup měří.

## 9. Rizika

- **Nepřesné třídy uvnitř parků:** hlídá náhled v N0 a ruční oprava v `content/cities/<id>/nature_overrides.geojson`.
- **Příliš mnoho stromů:** limit na chunk, lesní hmoty místo jednotlivých stromů, rozpočty v kap. 7.
- **Auto schované pod korunami:** průhlednost korun kolem hráče, les neprůjezdný.
- **Inventář stromů je snímek v čase:** stačí pro náladu ulice, nevydávat za aktuální stav.

## 10. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| V1 | Souvislý les neprůjezdný, nebo průjezdný mezi stromy? | neprůjezdný, jen cesty |
| V2 | Lodě jako kulisa už v N2, nebo až s Istanbulem? | v N2 |
| V3 | Jména vody a parků jen v místním jazyce, nebo i přeložená? | místní |
| V4 | Roční období (podzimní barvy)? | ne |

## 11. Zdroje

- Overture – téma base: https://docs.overturemaps.org/guides/base
- Overture – typy v tématu base: https://docs.overturemaps.org/schema/concepts/by-theme/base
- Overture – land_cover z ESA WorldCover: https://docs.overturemaps.org/blog/2024/05/16/land-cover/
- NYC 2015 Street Tree Census: https://catalog.data.gov/dataset/2015-street-tree-census-tree-data

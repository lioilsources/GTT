# METROPOLE_TERRAIN_PLAN.md

**Stav:** druhý dodatek k `METROPOLE_PLAN.md`, navazuje na `METROPOLE_DUALSTACK_PLAN.md`. Při rozporu platí tento dokument.
**Datum:** 2026-11-23
**Pro:** kódovací model (Opus, střední effort). **OVĚŘ** = ověř v dokumentaci nebo v datech, než na tom postavíš kód. Kapitola 12 = rozhoduje Ol1n, do té doby platí default.

**Co mění:**

- hlavní plán 5.3 (nový krok pipeline `elevation` a `lod`), 6.2 (jednotná zobrazená výška), 7.2 (svahy a skoky)
- dual-stack plán 6.2 (konstantu `deck_lift_m` nahrazují skutečné profily mostů a tunelů)

---

## 1. Cíl

Města mají skutečný reliéf. Jezdí se do kopce a z kopce, přes mosty nahoru a tunely dolů, a hráč to vidí i cítí:

- **vidí** – terén, sklon ulic a výhledy z kopce (naplno v šikmém pohledu, kap. 7)
- **cítí** – auto do kopce ztrácí, z kopce nabírá, přes hranu skočí

Výšky jsou data v citypacku a jsou stejné pro oba klienty. Fyzika svahů je sdílená specifikace. Liší se jen to, jak moc reliéfu klient ukáže.

## 2. Rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| T1 | Výšky jsou v citypacku: mřížka terénu po chunku + výška každého bodu silniční sítě. | Jeden zdroj pro oba klienty i pro fyziku. |
| T2 | Fyzika zůstává 2D (Forge2D / planck.js). Svah je přídavná síla, skok je samostatný svislý pohyb. | Žádná 3D fyzika, parita mezi klienty zůstává. |
| T3 | Silnice určují terén, ne naopak. Profil ulic se vyhladí a omezí sklonem, terén se k němu přimkne. | Hrubá výšková data jsou ve městě zašuměná; sjízdnost má přednost. |
| T4 | Terén je převýšený (`exaggeration`, default 2,0). | Auta jsou 2,5× větší, bez převýšení by kopce vedle nich zanikly. |
| T5 | Mosty, tunely a estakády mají skutečný podélný profil. | I ploché město (New York) má díky nim „kopce". |
| T6 | Pohled shora zůstává výchozí v obou klientech a dostane reliéf. Šikmý pohled je druhý režim kamery, zatím jen ve W. | Viz kap. 7 a otázka K1. |
| T7 | Všechno je přídavné. Citypack bez výšek dál funguje, klient bez podpory výšek pole ignoruje. | Hlavní plán běží, nesmí se rozbít. |

## 3. Data

### 3.1 Zdroje

| Zdroj | Co to je | Licence | Použití |
|---|---|---|---|
| Místní lidarový model terénu | holý terén v rozlišení metrů | podle města | první volba |
| AWS Terrain Tiles | globální výšky terénu v dlaždicích na S3 | otevřená data, atribuce podle zdrojů | záloha pro všechna města |
| Copernicus GLO-30 | globální model **povrchu** 30 m (včetně budov a stromů) | zdarma, s povinnou poznámkou o původu | druhá záloha |
| FABDEM | GLO-30 s odstraněnými budovami | CC BY-NC-SA, jen nekomerčně | **nepoužívat** |

Pro první dvě města:

| Město | Zdroj | Poznámka |
|---|---|---|
| New York | městský 1ft DEM (holý terén z lidaru 2010; existuje i novější z 2017) | podmínky užití **OVĚŘ**; město je ploché, reliéf dělají mosty, tunely a Uptown |
| Praha | ČÚZK DMR 5G | otevřená data, CC BY 4.0, uvádět původ (ČÚZK); první opravdu kopcovité město |

Londýn, Paříž, Tokio a Hongkong mají národní lidarová data; dostupnost a licenci **OVĚŘ** při přípravě města. Kde nic není, platí AWS Terrain Tiles.

Stahování dlaždic: převezmi kód z Ol1nova Go nástroje `terrain-fetch` (projekt DoggioWars), který s AWS Terrain Tiles už pracuje.

Místní data se připravují ručně do `content/cities/<id>/dem/` (mimo git), postup stažení zapiš do `content/cities/<id>/dem/README.md`. Atribuci každého použitého zdroje doplň na obrazovku „O mapách".

### 3.2 Konfigurace

```yaml
# content/cities/<id>/city.yaml
elevation_sources: [local, terrain_tiles]
elevation_is_bare_earth: true      # false = krok clean odstraní budovy

# content/tuning.yaml
terrain:
  exaggeration: 2.0
  grid_m: 8
  blend_m: 24
  max_grade: {motorway: 0.08, trunk: 0.10, primary: 0.20, secondary: 0.20, tertiary: 0.28, alley: 0.33}
  bridge: {clear_water_m: 15, clear_road_m: 6, max_grade: 0.07}
  tunnel: {depth_water_m: 10, depth_land_m: 8, max_grade: 0.07}
slope_physics:
  gravity: 20.0            # m/s² v herních jednotkách
  slope_force_scale: 0.6
  suspension_travel: 0.5   # m; o kolik se kola dotáhnou za zemí, než auto letí
  hard_landing: 10.0       # m/s
camera:
  topdown: {height_m: 250}
  chase: {distance_m: 55, height_m: 40, look_ahead_m: 25, fov_deg: 40}
```

Všechna čísla jsou výchozí a ladí se ve fázi T3.

### 3.3 Co přibude v citypacku

Všechny výšky jsou **herní** (po převýšení a omezení sklonu), v decimetrech, relativně k `z0` města.

| Kde | Pole | Popis |
|---|---|---|
| `manifest.pb` | `terrain_version`, `z0_m`, `exaggeration` | bez `terrain_version` klient jede naplocho |
| `chunks/*.pb` | `terrain` 33×33 × int16 | mřížka po 8 m, okraje sdílené se sousedy |
| `chunks/*.pb` | `shade` 33×33 × uint8 | předpočítané stínování svahu |
| `graph.pb` | `z_dm` u uzlu a u každého vrcholu hrany | hrany s převýšením zhuštěné na úseky ≤ 16 m |
| silnice | `z_dm` u vrcholů pásu | pásy zhuštěné po 8 m |
| budovy | `base_z_dm` | nejnižší bod terénu pod půdorysem |
| voda | `z_dm` | hladina |
| `lod/*.pb` | hrubý terén 32 m + hmoty bloků | jen pro šikmý pohled |

Navíc asi 3,3 kB na chunk, pro oblast M1 necelé 2 MB před kompresí.

## 4. Pipeline: krok `elevation`

Pořadí: fetch → roads → widen → buildings → ground → **elevation** → landmarks → pois → pack → **lod** → validate → preview.

1. **dem** – načti výšky pro oblast s okrajem 500 m, převzorkuj na pracovní mřížku 4 m v lokálních souřadnicích.
2. **clean** (jen když `elevation_is_bare_earth: false`) – buňky pod půdorysy budov označ jako prázdné a doplň je interpolací z okolí; pak vyhlaď (σ = 30 m).
3. **profile** – odečti výšku v uzlech a po 16 m podél hran; vyhlaď podél trasy (okno 40 m u lidaru, 120 m u hrubých dat). Hrany sbíhající se v uzlu sdílejí jeho výšku.
4. **pins** – pevné body:
   - most přes vodu: mostovka `clear_water_m` nad hladinou, nebo `deck_height_m` z `landmarks.yaml` u ikonických mostů
   - most přes silnici nebo trať: `clear_road_m` nad křižovanou hranou
   - estakáda nad zemí: terén + 8 m
   - tunel: `depth_water_m` pod hladinou, jinak `depth_land_m` pod terénem
5. **exaggerate** – `z' = z0 + (z − z0) · exaggeration`. Světlé výšky a hloubky z bodu 4 se nepřevyšují.
6. **grade_clamp** – opakuj: pro každou hranu delší než dovolí `max_grade` její třídy posuň volné koncové uzly k sobě o polovinu přebytku (pevný bod se nehýbe, volný vezme celý přebytek). Konec při přebytku pod 0,05 m nebo po 500 průchodech. Tím vzniknou i nájezdy k mostům a tunelům. Hrana, která se nevejde, se stane uličkou se schody (`stairs: true`, pro auta neprůjezdná) a vypíše se ve zprávě.
7. **conform** – postav mřížku 8 m z vyčištěných výšek × převýšení. Uvnitř silnic vezmi výšku silnice, do vzdálenosti `blend_m` plynule přejdi k terénu. Pod vodou hladina − 3 m.
8. **shade** – stínování svahu, slunce azimut 315°, výška 45°.

**lod** – terén zředěný na 32 m a budovy sloučené do hmot po blocích, po skupinách 4×4 chunků.

**validate** navíc: žádná hrana nad `max_grade`; výška uzlu souhlasí se všemi jeho hranami; mostovka má světlost nad vším, co kříží; mezera mezi silnicí a terénem na okraji pásu pod 0,3 m; rozsah se vejde do int16.

**preview** navíc: stínovaná mapa reliéfu a seznam deseti nejprudších ulic se jmény (poslouží i jako obsah: „nejprudší ulice města").

Testy pipeline: syntetický terén (rovina, kužel, hřeben, údolí s mostem) se zlatými výstupy.

## 5. Sdílená specifikace (`specs/terrain.md`)

### 5.1 Výška pod bodem

```
groundZ(x, y, surface):
  surface = terén   → bilineární interpolace v mřížce chunku
  surface = hrana E → průmět bodu na osu hrany E, lineární interpolace mezi jejími vrcholy
```

Auto si drží `surface`. Na most, do tunelu a na estakádu přechází na nájezdu (hrana s přechodem vrstvy) a jede po povrchu hrany, jinak po terénu. Kolizní vrstvy z hlavního plánu 7.2 platí dál.

### 5.2 Svah

Na zemi působí na auto síla proti spádu:

```
grad   = spád povrchu (rozdíl groundZ o 1 m v ose x a y)
a_svah = −gravity · slope_force_scale · grad / sqrt(1 + |grad|²)
grip   = grip · 1 / sqrt(1 + |grad|²)
```

Stojící auto bez plynu na svahu drží (pod 0,5 m/s se síla svahu neuplatní). Provoz řízený AI sílu svahu nepočítá, jen sleduje výšku a do kopce jede pomaleji.

### 5.3 Skok

Stav navíc: `z`, `vz`, `airborne`. Každý krok po vodorovném pohybu:

```
g  = groundZ(poloha)
vg = (g − g_prev) / dt

vz = vz − gravity·dt;  z = z + vz·dt      # karoserie padá volně
když z ≤ g:                               # dosedla na zem
    když byla airborne: dopad = vg − vz
    z = g;  vz = vg

mezera   = z − g
airborne = mezera > suspension_travel
```

Karoserie se tedy od země oddělí, kdykoli povrch uhne rychleji, než auto padá, ale za skok se počítá až mezera větší než chod pérování. Drobné hrany a šum mřížky tak skok nespustí.

Když je `airborne`, nepůsobí pneumatiky, plyn, řízení ani síla svahu, jen odpor vzduchu. Dopad nad `hard_landing` ubere rychlost a zatřese kamerou. `mezera` řídí i oddělení stínu od auta. Vozidla AI neskáčou.

Kontrolní hodnoty (ověřeno simulací s krokem 1/60 s):

| Situace | Výsledek |
|---|---|
| 30 m/s, hrana ze stoupání 15 % do klesání 15 % | 0,77 s a 23 m ve vzduchu, dopad 8,7 m/s |
| 40 m/s, hrana 20 % / 20 % | 1,53 s a 61 m, dopad 15,7 m/s (tvrdý) |
| 15 m/s, hrana 5 % / 5 % | žádný skok (mezera 0,04 m) |
| 30 m/s, schod dolů 5 cm | žádný skok |
| 30 m/s, zvlněná silnice ±0,3 m s periodou 19 m | žádný skok |

### 5.4 Scénáře parity (P1, tolerance ±5 %)

- sjezd 200 m při 10 % bez plynu: rychlost na konci
- rozjezd do kopce 15 %: čas na 20 m/s
- skoky z kontrolní tabulky v 5.3: doba a délka letu, rychlost dopadu
- stání na svahu 20 % bez plynu: posun 0
- přejezd mostu s nájezdy 7 %: průběh rychlosti

Auto: `sedan_01`. Hodnoty nahraje vedoucí klient podle dual-stack plánu 5.5.

## 6. Jednotná zobrazená výška

Každý bod světa má zobrazenou výšku `z`: terén svou herní výšku, střecha `base_z` + zobrazenou výšku budovy (dual-stack plán 6.2). Kamera v pohledu shora je kolmo nad autem ve výšce `z_ref + H`, kde `z_ref` je vyhlazená výška země pod autem a `H = camera.topdown.height_m`.

- **W** staví sítě ve skutečné zobrazené výšce, víc nepotřebuje.
- **F** promítá každý bod: `s = H / (H − (z − z_ref))`, `p' = VP + (p − VP) · s`. Rozdíl `z − z_ref` ořízni na rozsah −2H až 0,8H.

Pro budovu na rovině dává vzorec totéž co dosud. Příklad reliéfu: kopec o 30 m výš ve vzdálenosti 100 m se posune o 13,6 m od středu.

## 7. Kamera: aby kopce byly vidět

### 7.1 Pohled shora (oba klienti)

Kolmý pohled reliéf ukazuje slabě, proto se sčítá víc nápověd:

- perspektiva podle kap. 6 (svah před autem „roste")
- stínování svahu z pole `shade` v barvě terénu i silnic
- šipky na vozovce u úseků nad 8 %, mířící do kopce
- stín auta se při skoku oddělí a zmenší
- HUD: sklon v % a přibližná nadmořská výška (`z0 + z / exaggeration`)
- krátké oddálení kamery na hraně a při dopadu

### 7.2 Šikmý pohled (W)

Kamera za autem a nad ním, dívá se dopředu dolů: `distance_m` za autem, `height_m` nad ním, míří `look_ahead_m` před auto, tedy asi 27° pod vodorovnou. Je vidět horizont, stoupání před autem i město pod kopcem.

- plynulé dotáčení za autem; budovy mezi kamerou a autem zprůhlední
- vzdálený prstenec do 1,5 km z `lod/` (hrubý terén a hmoty bloků), mlha, obloha, slunce shodné se stínováním
- ovládání a HUD stejné jako shora
- přepínač v nastavení a gestem; který režim je výchozí, určuje K1
- rozpočet navíc: nejvýš 40 draw calls a 60 tisíc trojúhelníků

Hory, které se nejezdí (Rio, Hongkong), jsou v šikmém pohledu vidět jako kulisa. V pohledu shora je ořízne limit z kap. 6.

### 7.3 Šikmý pohled ve F

Flame nemá hloubkový buffer. Šikmý pohled by znamenal promítat všechny vrcholy na CPU a řadit po chuncích od nejvzdálenějšího (terén, silnice, pak objekty chunku). Je to proveditelné, ale je to vlastní softwarový 3D renderer s artefakty u mostů. Dělá se až jako fáze T4 a jen když to Ol1n po bráně G1 výslovně zadá.

## 8. Vykreslení terénu

**W:** síť terénu po chunku z mřížky (2 048 trojúhelníků), barva vrcholů = materiál × `shade`. Silnice jako vlastní pásy s `zOffset` proti prolínání (**OVĚŘ** API). Budovy od `base_z` nahoru, stěna na straně svahu sahá pod terén. Mosty jako pásy s profilem a zábradlím, tunely s portály; uvnitř tunelu se v pohledu shora skryje strop.

**F:** vrcholy země a silnic se promítají každý snímek podle kap. 6. Chunk s rozdílem výšek pod 1 m se kreslí postaru z cache. Rozpočet navíc: 2 ms na referenčním telefonu; když se nevejde, zvětši krok mřížky pro vykreslení na 16 m.

## 9. Obsah, který z reliéfu těží

- minihry `drive`: Časovka jako závod do vrchu, Sprint jako sjezd, Kaskadér na skutečných hranách, Drift zóna v serpentinách
- vyhlídky jako body zájmu a fotomísta
- „nejprudší ulice" z výstupu pipeline jako razítko do Pasu

## 10. Fáze

| Fáze | Obsah | Kdy | Akceptace |
|---|---|---|---|
| **T0 – Výšky v datech** | krok `elevation`, pole v citypacku, validate, preview, testy na syntetickém terénu; New York | hned, session SHARED; klienty nemění | `citypack validate nyc` projde; na náhledu jsou vidět nájezdy mostů a Uptown; citypack bez výšek dál funguje |
| **T1 – Svahy a skoky** | `specs/terrain.md`, fyzika 5.2 a 5.3 v obou klientech, scénáře, nápovědy pohledu shora (7.1), promítání ve F (kap. 6) | po bráně M0/D1 | scénáře v toleranci; přejezd Brooklynského mostu je znát na rychlosti i na obraze; 60 fps drží |
| **T2 – Terén a šikmý pohled ve W** | síť terénu, mosty a tunely s profilem, `lod`, šikmá kamera | po D1 | 60 fps v šikmém pohledu na obou referenčních telefonech; přepnutí kamery za jízdy bez záseku |
| **T3 – Kopcovité město** | Praha s DMR 5G, ladění `exaggeration`, `gravity` a sklonů, minihry z kap. 9 | s druhým městem (M3) | Ol1n potvrdí, že kopce odpovídají skutečnosti (Petřín, Letná, Hradčany); žádná průjezdná ulice nad limitem |
| **T4 – Šikmý pohled ve F** | podle 7.3 | jen na zadání po G1 | — |

Položky T0–T4 zapiš do `plans/progress.yaml`, pokud se postup měří.

## 11. Parita a rizika

- **Parita:** výšky a pravidla = stejná data; fyzika svahů a skoků P1; pohled shora s reliéfem v obou klientech; šikmý pohled P2 (jen W).
- **Šikmý pohled rozevírá rozdíl mezi klienty.** Pokud se ukáže jako hlavní zážitek, je to argument pro W jako hlavní stack u brány G1. Proto K1.
- **Hrubá data ve městě:** krok `clean` a vyhlazení profilu; u ikonických mostů ruční `deck_height_m`.
- **Převýšení zkresluje známá místa:** ladí se v T3 na městě, které Ol1n zná.
- **Výkon F:** promítání země každý snímek; hlídá rozpočet v kap. 8.
- **Falešné skoky z šumu mřížky:** `suspension_travel` a vyhlazený profil silnic.

## 12. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| K1 | Výchozí kamera: (A) shora v obou klientech, šikmo jako přepínač ve W; (B) šikmo výchozí ve W, F zůstane shora; (C) šikmo všude, tedy T4 nebo jediný stack W | A |
| K2 | Převýšení terénu | 2,0, doladit v T3 |
| K3 | První kopcovité město: Praha, nebo přidat San Francisco jako ukázkové město kopců? | Praha |
| K4 | Mají skoky poškozovat auto? | ne, jen ztráta rychlosti |

## 13. Zdroje

- AWS Terrain Tiles: https://registry.opendata.aws/terrain-tiles
- Terrain Tiles – atribuce zdrojů: https://github.com/tilezen/joerd/blob/master/docs/attribution.md
- Copernicus DEM: https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM
- FABDEM – licence: https://gee-community-catalog.org/projects/fabdem/
- ČÚZK – podmínky poskytování dat: https://cuzk.gov.cz/Predpisy/Podminky-poskytovani-prostor-dat-a-sitovych-sluzeb/Podminky-poskytovani-prostorovych-dat-CUZK.aspx
- ČÚZK – DMR 5G, stahovací služba: https://geoportal.gov.cz/php/micka/record/basic/CZ-CUZK-ATOM-DMR5G-ETRS89?dlang=eng
- NYC 1 foot DEM: https://catalog.data.gov/dataset/1-foot-digital-elevation-model-dem

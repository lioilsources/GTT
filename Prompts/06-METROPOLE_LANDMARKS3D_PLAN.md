# METROPOLE_LANDMARKS3D_PLAN.md

**Stav:** inkrement. Starší plány se nemění, tento dokument je doplňuje.
**Datum:** 2026-11-25
**Pro:** kódovací model (Opus, střední effort). **OVĚŘ** = ověř v dokumentaci nebo v datech, než na tom postavíš kód. Kapitola 11 = rozhoduje Ol1n, do té doby platí default.

---

## 1. Cíl

Hlavní památky města mají skutečný tvar. Pražský hrad s katedrálou, Karlův most s oblouky a věžemi, Týnský chrám se dvěma věžemi. Dnes je každá památka jen vytažený půdorys v barvě `landmark`.

- **v šikmém pohledu (W)** hráč vidí model památky: věže, střechy, oblouky
- **v pohledu shora (W i F)** vidí střešní plán: hřebeny, věže a nádvoří místo jedné plochy

Tvar je data v citypacku, stejná pro oba klienty. Kolize, fyzika a pravidla se nemění.

## 2. Co do hry nejde

Zadání zmiňovalo Google Earth 3D a Street View. Ty použít nejdou. Jde to přes otevřené modely měst.

| Zdroj | Do hry? | Důvod |
|---|---|---|
| Google Photorealistic 3D Tiles (Google Earth 3D) | **ne** | Podmínky Map Tiles API dovolují jen zobrazení mapy online. Zakazují použití offline, ukládání do mezipaměti mimo HTTP hlavičky a vytěžování geometrie. Vyžadují logo Google a platí se za požadavky. Hra má město v balíčku a běží bez sítě. |
| Google Street View | **ne** | Stejné podmínky. Fotky navíc nesedí k plochému stylu, jejich roli plní pohlednice v Pasu. |
| Fotogrammetrická síť s texturami (jakákoli) | **ne** | Desítky MB na jednu památku, textury v paměti, vzhled mimo styl A–E. |
| Úřední otevřený model města (LOD2: stěny a tvarované střechy) | **ano** | Otevřená licence s atribucí, málo trojúhelníků, bez textur. Hlavní cesta, kap. 4. |
| Části budov z OpenStreetMap / Overture (`building_part`, tvar střechy) | **ano, záloha** | Licence a atribuce už ve hře jsou. Kvalita kolísá. |
| Ruční parametrický popis památky | **ano, poslední záchrana** | Pro věci, které LOD2 neumí (příhradová rozhledna) nebo kde data chybí. |
| Hotové modely z knihoven (Sketchfab apod.) | ne | Nejednotná kvalita, měřítko i licence. |

## 3. Rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| H1 | Modely dostanou jen památky s `hero: true`, ne celé město. | Rozpočet a práce na jednu památku. Zbytek města zůstává vytažené půdorysy. |
| H2 | Zdroj je úřední otevřený model města. Záloha části budov z Overture, pak ruční popis. | Kap. 2 a 4. |
| H3 | Žádné textury. Každá plocha má roli (stěna, střecha, měď, kámen, sklo, zlato) a barvu z `design/tokens.json`. | Styl měst je plochý, textury jsou hlavní riziko paměti. |
| H4 | Model je v citypacku v novém souboru `models.pb`. Všechno je přídavné: balíček bez něj funguje, klient bez podpory ho ignoruje. | Stejně jako terén (plán 02, T7). |
| H5 | Kolize dál počítají půdorysy vrstvy 0. Model je jen obraz. | Invariant z `CLAUDE.md`, parita P0/P1 se nedotkne. |
| H6 | Model se skládá z částí. Každá část stojí na terénu jako samostatná budova. | Areál Hradu leží ve svahu a terén je převýšený (T4). Jeden tuhý model by visel ve vzduchu nebo se zabořil. |
| H7 | W kreslí model v šikmém pohledu a střešní plán v pohledu shora. F kreslí jen střešní plán, plný model až s T4. | F nemá šikmý pohled (plán 02, 7.3; plán 05). |
| H8 | Rozpočty z kap. 8 jsou tvrdé. Hlídá je `citypack validate` a `bench`. | Odpověď na riziko výkonu a paměti. |
| H9 | Zdroj každého modelu je v atribuci manifestu a v titulcích hry. | Podmínka licencí. |

## 4. Data

### 4.1 Zdroje podle města

| Město | Zdroj | Licence a atribuce | Formát | Stav ověření |
|---|---|---|---|---|
| Praha | IPR Praha, 3D model budov a mostů. Střechy modelované podrobně včetně komínů, vikýřů a věží, přesnost aspoň 0,5 m, stěny odvozené poloautomaticky. | CC BY, text „data base © IPR Praha“ | CityGML, multipatch, polygonZ. Balík za celou Prahu nebo po mapových listech. | Licence a formáty ověřené na geoportalpraha.cz. **OVĚŘ:** souřadnicový systém stažených dat, velikost listu, jak je v modelu Hrad, katedrála a Karlův most. |
| New York | NYC 3-D Building Model (město, letecké snímky 2014). Existuje i převod do CityGML LoD2 od TU München. | **OVĚŘ** podmínky NYC Open Data pro šíření v komerční aplikaci. U převodu TUM zůstávají práva u původních poskytovatelů. | CityGML, multipatch, DGN | Neověřeno, stránka datasetu nešla strojově přečíst. |
| Tokio | Project PLATEAU (MLIT). | PDL 1.0, kompatibilní s CC BY 4.0. Atribuce „出典：国土交通省 PLATEAUウェブサイト (URL)“, upravená data označit jako upravená. Práva drží jednotlivé městské části. | CityGML z geospatial.jp | **OVĚŘ:** LOD2 pro Chiyoda, Chūō, Minato, Shinjuku, Shibuya, Taitō; omezení podle zákona o zeměměřictví. |
| Moskva | Úřední otevřený model nejspíš není (**OVĚŘ**). | — | — | Jde rovnou zálohou: části budov z Overture, pak ruční popis. |

### 4.2 Pravidla pro data

- Surová data nejsou v gitu ani v CI. Stahují se do `run/citypack/<city>/raw/models/` a tam se cachují.
- Stahuj jen mapové listy, které pokrývají hero památky. Balík za celé město ne.
- Licenci každého zdroje dolož odkazem v `docs/citypack.md` a v `LICENSES.md` dřív, než se balíček vydá.

### 4.3 Konfigurace

```yaml
# content/cities/<id>/models.yaml
source: ipr_praha_3d            # nebo nyc_3d, plateau, overture_parts, manual
models:
  prague_castle:
    select: {buffer_m: 2}       # default: budovy balíčku s landmark == id, rozšířené o buffer
    include: []                 # id objektů zdroje navíc
    exclude: []
    max_tris: 12000             # jen když nestačí default
    roles: {}                   # přepis role podle id části, např. měděná střecha
  petrin_tower:
    manual: models/petrin_tower.yaml   # ruční parametrický popis
```

```yaml
# content/tuning.yaml
models:
  enabled: true
  max_tris: 4000                # na památku
  city_max_tris: 120000
  city_max_bytes: 1500000       # models.pb po gzipu
  min_detail_m: 1.5             # menší části se zahodí
  near_m: 600.0                 # do této vzdálenosti W kreslí model, dál půdorys
  roof_plan_max_polys: 400
```

## 5. Formát v citypacku

Nový soubor `models.pb` (gzip protobuf), `format_version` zůstává 1.

```
Models { repeated Model models }
Model {
  landmark_id: string
  source: enum                  // pro atribuci
  parts: repeated Part
  replaces: repeated uint32     // budovy balíčku, které model v šikmém pohledu nahrazuje
  roof_plan: repeated PlanPoly  // 2D pro pohled shora
}
Part {
  anchor: x, y (dm)             // bod, pod kterým se bere výška terénu, jako u budovy
  positions: sint32[]           // x, y, z v dm od anchor, z od paty části
  triangles: uint32[]
  roles: bytes                  // jedna role na trojúhelník
}
PlanPoly { points: sint32[], height_m, shade: 0..3 }
```

- Výšky jsou skutečné metry. Klient na ně použije stejný převod na zobrazenou výšku jako na budovy (plán 02 kap. 6, dual-stack plán 6.2). **OVĚŘ** přesné pravidlo v `specs/terrain.md` a `specs/style.md`.
- Role a barvy: `design/tokens.json` → `color.model.<role>` pro den a noc, s možností přepisu v `color.city.<city>`. Stěna památky zůstává dnešní `landmark`.

## 6. Pipeline: krok `models`

Běží po kroku `landmarks`, před `pack`. Celý v Go, deterministický, bez knihovny na obecnou decimaci.

1. **Výběr.** Objekty zdroje, jejichž půdorys protíná výběr památky z `models.yaml`.
2. **Čtení.** Čtečka CityGML: budova, část budovy, plochy střech a stěn v LOD2, most. Převod do místních metrů stejnou projekcí jako zbytek balíčku. **OVĚŘ** souřadnicový systém zdroje; když jde stáhnout WGS84, ber WGS84.
3. **Čištění.** Zahoď podlahy a plochy pod terénem. Svař vrcholy na 0,1 m. Slouč plochy v jedné rovině. Zahoď části menší než `min_detail_m`. Přiřaď role: střecha, stěna, přepisy z `models.yaml`.
4. **Rozpočet.** Když je model nad `max_tris`, zvedej `min_detail_m` po krocích až na 4 m. Když ani to nestačí, krok selže a vypíše, kolik chybí. Řeší se ručně v `models.yaml`.
5. **Části.** Rozděl model podle budov zdroje, každé části urči `anchor` a patu podle terénu (H6).
6. **Střešní plán.** Promítni střechy do 2D, slouč podle stínu (4 úrovně podle sklonu a orientace k pevnému světlu), zjednoduš na 0,3 m, drž `roof_plan_max_polys`.
7. **Náhrada.** Do `replaces` dej budovy balíčku, které model zakrývá aspoň ze 60 %.
8. **Výstup.** `models.pb`, náhled `preview/models/<id>.png` (shora a šikmo) a řádek do souhrnu: trojúhelníky, bajty, zdroj.

**Mosty.** Model mostu dodá pilíře, oblouky a věže. Mostovka zůstává ze silniční sítě s profilem (T5). Výšku modelu srovnej s výškou mostovky ze sítě. **OVĚŘ**, jak je Karlův most v balíčku (pěší zóna, `specs/zones.md`).

**Validate.** Rozpočty z kap. 8. Pata každé části do 2 m od terénu. Model do 150 m od bodu památky. Každý model má zdroj s atribucí v manifestu.

## 7. Klienti

Nová sdílená specifikace `specs/models.md` v1 (P2, bez vektorů; scénář jen pro přepnutí model ↔ půdorys).

**W, šikmý pohled**
- Jedna síť na památku, barvy ve vrcholech, stejný materiál a styl města jako budovy.
- Model se kreslí do vzdálenosti `near_m` od auta, dál zůstává vytažený půdorys. Přepnutí má hysterezi, bez probliknutí.
- Když se kreslí model, budovy z `replaces` se skryjí. Jejich kolize zůstávají.
- Stíny: **OVĚŘ**, jak dnes vznikají vržené stíny budov, a použij stejný postup nad střešním plánem s výškami.
- `models.pb` se načte jednou se startem města, sítě se staví až s chunkem památky a s chunkem se uvolní.

**W shora a F**
- Střešní plán se kreslí místo jednobarevné střechy památky, v pořadí podle `height_m`, odstín podle `shade`.
- Promítání výšek stejné jako u střech budov (ve F plán 02 kap. 6).

**Mimo rozsah:** okna a noční svícení modelů, interiéry, animace, pohlednice.

## 8. Rozpočty a rizika

| Co | Limit | Poznámka |
|---|---|---|
| Trojúhelníky na památku | 4 000 | Výjimka do 12 000 jen zápisem v `models.yaml` (areál Hradu). |
| Trojúhelníky na město | 120 000 | 25 památek po 4 000 je 100 000. |
| `models.pb` na město | 1,5 MB po gzipu | Odhad 0,5–0,9 MB. Balíčky dnes mají 4,4–9,3 MB, limit je 40 MB. |
| W: modely v plném detailu naráz | 3 | Ostatní jako půdorys. |
| W: čas snímku p99 ve scéně `bench` u památek | nejvýš +10 % proti stavu bez modelů | Nová scéna `prague-landmarks` (Hradčany, Staroměstské náměstí). |
| W: paměť | nejvýš +25 MB haldy | Bez textur, sítě se uvolňují s chunkem. |
| F: střešní plán | 400 polygonů na památku, fps beze změny | Kreslí se ve stávající vrstvě budov. |

**Odpověď na rizika ze zadání**

- **Úložiště:** malé. Do 1,5 MB na město, protože jde jen o geometrii pár desítek staveb bez textur.
- **Paměť:** malé. Sítě jen pro památky v dosahu.
- **Výkon:** střední, jen v šikmém pohledu na místech s více památkami vedle sebe. Řeší limit tří modelů, `near_m` a scéna v `bench`.
- **Největší riziko je práce s daty.** Zarovnání na půdorysy z Overture, převýšený terén, mosty, stavby mimo LOD2 (Petřínská rozhledna, Žižkovský vysílač). Proto pilot na pěti památkách a brána po H2.
- **Vzhled:** LOD2 bez textur může působit holě. Proto role a barvy podle stylu města a rozhodnutí až nad snímky.

## 9. Fáze

| Fáze | Obsah | Kdy | Akceptace |
|---|---|---|---|
| **H0 – Ověření dat** | Všechna OVĚŘ z kap. 4. Stáhni pražské listy pro pilot. Změř trojúhelníky a velikost u pěti pilotních památek. Zpráva v `plans/M7_PAMATKY.md`. | hned, session SHARED, klienty nemění | Tabulka pilotu s čísly. Licence čtyř měst doložené odkazem, u každého „lze / nelze / nejasné“. Žádná surová data v gitu. |
| **H1 – Pilot v datech** | Krok `models`, `models.pb`, validate, náhledy. Pilot: `prague_castle` (areál s katedrálou), Karlův most se `bridge_tower`, `tyn_church`, `st_nicholas`, `national_theatre`. | po H0 | `citypack validate prague` projde s rozpočty. Náhledy pěti památek. Balíček bez `models.pb` dál funguje. |
| **H2 – Šikmý pohled ve W** | Vykreslení, přepínání model ↔ půdorys, `replaces`, stíny, scéna v `bench`. | po H1 | 60 fps na obou referenčních telefonech u Hradu a na Staroměstském náměstí. Snímky pro Ol1na. **Brána K1.** |
| **H3 – Střešní plán shora** | `specs/models.md`, W a F. | W po H2, F po bráně L (plán 05) | Oba klienti kreslí plán, fps beze změny, parita zapsaná. |
| **H4 – Zbytek Prahy** | Ostatní hero památky. Petřínská rozhledna a Žižkovský vysílač ručním popisem. | po K1 | Všech 20 hero památek má model nebo zapsaný důvod, proč ne. |
| **H5 – New York a Tokio** | Jen kde H0 potvrdilo licenci. | po H4 | Jako H4. |
| **H6 – Moskva** | Části budov z Overture, ruční popis pro Kreml a chrám Vasila Blaženého. | po H5 | Jako H4. |

Založ milník **M7** v `plans/progress.yaml` s položkami H0–H6 a záznamy v `plans/verify.yaml` pro H2 a H3. Nová id parity ber od prvního volného (**OVĚŘ** v `parity.yaml`, dnes končí F-082).

## 10. Parita

- Data a `specs/models.md` jsou sdílené. Střešní plán je P2 v obou klientech. Plný model je P2 jen ve W, dokud F nemá šikmý pohled.
- Kolize, trasy, pravidla miniher a uložení se nemění. Žádné nové vektory P0.
- Další věc, kterou má jen W. Počítá se k argumentům u brány G1 stejně jako šikmý pohled (plán 02 kap. 11).

## 11. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| K1 | Pokračovat po pilotu na celé město? | Rozhodne se nad snímky z H2. |
| K2 | Textury na modelech? | Ne. |
| K3 | F jen střešní plán, dokud nemá šikmý pohled? | Ano. |
| K4 | Pilotní pětice | Hrad s katedrálou, Karlův most s věží, Týnský chrám, sv. Mikuláš, Národní divadlo. |
| K5 | Sochy na Karlově mostě a drobné detaily pod 1,5 m | Vynechat. |
| K6 | Kdy začít | H0–H2 hned ve W, H3 ve F a další města až po bráně L. |
| K7 | Moskva bez úředních dat | Overture a ruční popis, nejvýš 6 památek ručně. |

## 12. Zdroje

- Map Tiles API, podmínky použití: https://developers.google.com/maps/documentation/tile/policies
- IPR Praha, 3D model budov a mostů: https://geoportalpraha.cz/en/data-and-services/articles-and-projects/3d-model/3d-model-budovy-mosty
- IPR Praha, otevřená data a licence: https://www.geoportalpraha.cz/en/data-and-services/open-data
- Project PLATEAU, otevřená data: https://www.mlit.go.jp/plateau/open-data/
- Project PLATEAU, podmínky: https://www.mlit.go.jp/plateau/site-policy/
- NYC 3-D Building Model: https://data.cityofnewyork.us/City-Government/3-D-Building-Model/tnru-abg2
- TU München, New York v CityGML: https://www.asg.ed.tum.de/gis/projekte/new-york-city-3d/

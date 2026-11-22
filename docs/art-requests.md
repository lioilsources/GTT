# Artwork – objednávka do zásoby

Hra dnes kreslí všechno procedurálně (auta podle třídy a rozměrů, portréty = iniciály na kruhu,
pohlednice jen text). Tady je seznam grafiky, kterou budou M1–M3 a M2 potřebovat, aby se dala
vyrábět dopředu (METROPOLE_PLAN kap. 10–12, ComfyUI). Klienti ji napojí, až bude hotová;
do té doby zůstává procedurální záloha.

## Společná pravidla

- **R10:** žádné reálné značky, loga, nápisy firem, SPZ, ani podoba skutečných aut. Památky a
  instituce skutečné jsou v pořádku. Žádní skuteční lidé.
- **Postavy:** zjevně dospělí (21+, věk je u postavy), manga styl, přitažliví, nic explicitního.
- **Styl (vybraný Ol1nem):** New York = **A, plochý vektor**, Praha = **C, sítotisk / risograf**.
  Paleta měst je v `design/tokens.json` → `color.city.<city>` (`specs/style.md`), grafiku ladit s ní.
- **Formát:** PNG s alfou (sRGB), finální velikost níže, k tomu zdrojový soubor / workflow ComfyUI
  a seed (kvůli dalším variantám). Pojmenování přesně podle cest níže.
- **Kam:** `assets/<oblast>/…` v repu (sdílená cesta, větev `shared/art-…`). `metro sync` je
  zkopíruje do obou klientů. Nad ~200 MB se přejde na manifest, takže držet velikosti.
- **Licence:** jen vlastní generování nebo volné licence; do `assets/LICENSES.md` zapsat model
  a licenci výstupu.

## Pořadí (priorita)

### 0. Style board – nejdřív, rozhoduje Ol1n
4 varianty stylu světa a postav (kap. 12: „před M1 style board aspoň 4 varianty“). Každá varianta:
jeden pohled shora na křižovatku Midtownu s autem, jeden portrét postavy, jedna pohlednice.
`assets/styleboard/v1..v4.png`, 1080×1920. Další položky až po Ol1nově výběru, nebo paralelně
v nejpravděpodobnější variantě s vědomím, že se můžou předělat.

### 1. Portréty NPC (hostitelé feedu, dialogy) – 6 postav
`assets/npc/<id>.png`, 1024×1024, ořez hlava a ramena, průhledné pozadí, k tomu
`assets/npc/<id>_bust.png` 768×1280 (karta feedu). Varianty výrazu: `_happy`, `_neutral`, `_annoyed`
(vibe v dialogu), stejné rozměry.

| id | jméno | věk | archetyp | vodítko (bio v `content/npc/characters.yaml`) |
|---|---|---|---|---|
| maya | Maya | 24 | influencerka | natáčí obsah na High Line, brunch |
| theo | Theo | 27 | barista hipster | |
| ray | Ray | 58 | taxikář filozof | |
| iris | Iris | 29 | knihomolka | |
| jules | Jules | 31 | pouliční muzikant | |
| dana | Dana | 38 | manažerka ve spěchu | |

Cíl plánu je 24 postav na město z 16 archetypů (kap. 11); dalších 10 pro Prahu a NYC M2 přijde
s obsahem, kostra archetypů: surfař, fitness nadšenec, gotička, ztracený turista + další.

### 2. Pohlednice památek – 54 karet
`assets/postcards/<city>/<id>.png`, 1080×1350 (4:5), ilustrace památky ve stylu pohlednice,
bez textu (název dodá hra z `i18n/`). Seznam = `hero: true` v `content/cities/<city>/landmarks.yaml`.

- **NYC (34):** empire_state, chrysler, grand_central, times_square, central_park, one_vanderbilt,
  rockefeller, one_bryant_park, park_432, central_park_tower, one57, park_200, eighth_620,
  hudson_yards_30, msg, farley, un_hq, st_patricks, nypl, carnegie_hall, one_wtc, wtc_memorial,
  woolworth, city_hall, federal_hall, trinity_church, flatiron, washington_arch, high_line,
  met_museum, amnh, guggenheim, lincoln_center, brooklyn_bridge
- **Praha (20):** prague_castle, old_town_square, old_town_hall, tyn_church, bridge_tower,
  st_nicholas, wenceslas_square, national_museum, national_theatre, dancing_house, powder_tower,
  municipal_house, rudolfinum, petrin_tower, zizkov_tower, vysehrad, main_station,
  old_new_synagogue, klementinum, vitkov

(Pozor: na budovách nesmí být loga nájemců, např. reklamy na Times Square vymyslet fiktivní.)

### 3. Auta shora – 9 dnes, 40 v M2
Na auto tři vrstvy, pohled **kolmo shora**, předek nahoru, 32 px na metr
(4,5 m auto = 144 px na délku), plátno o 10 % větší než rozměry:
- `assets/cars/<id>/body.png` – karoserie (stíny, okna, světla) bez kol
- `assets/cars/<id>/paint_mask.png` – maska laku v šedi (bílá = lak, tónuje se za běhu)
- `assets/cars/<id>/wheel.png` – jedno kolo shora (natáčí se v kódu)

Obrys karoserie musí sedět do obdélníku délka × šířka (kolize a měřítko).

| id | jméno (fiktivní) | třída | délka × šířka m | lak |
|---|---|---|---|---|
| hatch_pip | Lumo Pip | hatchback | 3,9 × 1,75 | pip_teal |
| m0_coupe | Varga Comet | kupé | 4,5 × 1,9 | comet_red |
| muscle_brute | Corvan Brute 70 | muscle (70. léta) | 4,9 × 1,95 | brute_orange |
| pickup_hauler | Torvik Hauler | pick-up | 5,4 × 2,0 | hauler_green |
| taxi_metro | Halden Metro Cab | taxi (NYC žluté) | 5,0 × 1,9 | cab_yellow |
| vega_roadster | Vega Roadster | supersport | 4,0 × 1,85 | vega_cherry |
| lidovka | Lidka 105 | malý sedan 80. let (fiktivní lidovka) | 4,2 × 1,6 | lidka_cream |
| kolobezka | Šlapka E | elektrokoloběžka + jezdec shora | 1,2 × 0,55 | slapka_lime |
| kolo | Velo Brk | kolo + jezdec shora | 1,8 × 0,6 | brk_blue |

M2 přidá ~31 aut napříč třídami z kap. 10 (mini, kombi, veterán, terénní, dodávka, limuzína,
autobus, skútr, food truck, tříkolka, rikša…). Přesný seznam s rozměry dodám do tohoto souboru,
jakmile bude v `content/cars/`; do té doby stačí prvních 9 jako ověření postupu (kap. 10:
„nejdřív 5 aut na ověření postupu, potom hromadná výroba“).

Navíc provoz (bez jména, náhodný lak): 6 generických aut `assets/cars/traffic_<n>/…`
(sedan, hatchback, SUV, dodávka, NYC autobus, pražská tramvaj 2 články 32 × 2,5 m).

### 4. Chodci a hlídka
- `assets/peds/ped_<n>.png` – 8 chodců shora (dospělí), 32 px/m, 2 snímky chůze + 1 „uskočení“.
- `assets/police/patrol.png` – policejní auto bez reálných znaků (fiktivní „CITY PATROL“),
  4,9 × 1,95 m, + maják zvlášť `patrol_light.png`.

### 5. M2 – budou potřeba později (stačí v pořadí)
- **Ikony HUD a telefonu** `assets/ui/<id>.png` 256×256: aplikace Feed, Mapa, Garáž, Pas, Foťák,
  Kontakty, Peněženka, Nastavení, Cesty, Rádio; počasí jasno/déšť/mlha; hledanost hvězda.
- **Obchody a bary** (fiktivní podniky, R10): 6 výloh / vývěsních štítů shora 256×256
  (`assets/shops/`): kavárna, bar, pizzerie, suvenýry, stánek s hot dogy, bodega.
- **Telefonní budka** shora + zvonící stav (`assets/props/booth.png`, `booth_ring.png`).
- **Stanice metra**: vstup shora + ikona linky bez oficiálního loga MTA (fiktivní kolečka).
- **Fotomísta**: 20 pohledových ilustrací (výhledy, ne památky) 1080×1350, seznam dodám s
  `specs/photo.md`.
- **Počasí**: textura kapek a kaluží (tileable 512×512), mlha (gradient), odlesk mokré silnice.
- **Kosmetika**: 8 polepů (vektorové motivy, tónovatelné), 6 typů kol, barvy kouře řeší kód.
- **Minihry M2 (22):** skiny stolů a herních ploch 1080×1920 (dřevo, plsť, asfalt NYC):
  karty (1 sada 52 + žolík, fiktivní rub „Metropole“), kostky, šachovnice/dáma, kulečník,
  bowling, minigolf (dráhy s motivem NYC), vzdušný hokej, stickball ulice, švihadla Double Dutch.

### 6. Textury povrchů (objednané, dávka gtt-tex1)
`assets/cities/<city>/<id>.png`, tileable 512×512, shora, neutrální světlo: nyc/asphalt,
nyc/sidewalk_concrete, nyc/roof_tar, prague/cobblestone, prague/mosaic_sidewalk, prague/roof_tiles.

## Hotovo

(sem připisovat dodané položky: cesta, datum, poznámka)

- **Style board v1**, 22. 11. 2026: Ol1n vybral NYC = A (plochý vektor), Praha = C (risograf).
  Sprity, postavy a UI sdílené ve stylu A. Paleta a parametry risografu předány zvlášť (tokens, tuning).
- `assets/npc/<id>.png` (= `_neutral`), `<id>_happy|_neutral|_annoyed.png` 1024², `<id>_bust.png`
  768×1280 (výraz happy), 22. 11. 2026, všech 6 postav, průhledné pozadí (BiRefNet-general, `tools/art/run_rmbg.py`).
- `assets/postcards/nyc/*.png`, 22. 11. 2026, 31 z 34. Chybí (přegenerovávají se kvůli textu na
  budovách): amnh, guggenheim, msg.
- `assets/postcards/prague/*.png`, 22. 11. 2026, 19 z 20. Chybí old_new_synagogue (přegenerovává se).
- Postup: `tools/art/make_batch1.py` (prompty, seedy) + `tools/art/run_board.py` (workflow ComfyUI).

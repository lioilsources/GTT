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

### 3. Auta shora – 43 aut + provoz a hlídka (jak je hra kreslí: `specs/art.md` v2 „Auta“)
**Formát (závazný, jinak sprite nesedí na kolizi):**
- Pohled **kolmo shora**, předek **nahoru**, bez perspektivy a bez vrženého stínu (stín kreslí kód).
- Měřítko **32 px na metr skutečného auta** (rozměry z tabulky = `length_m × width_m` v
  `content/cars/<id>.json`, *před* `car_scale`; hra si zvětší sama). Plátno = rozměry × 1,1
  (5 % okraj kolem dokola), zaokrouhleno nahoru – sloupec „plátno px“; ±1 px nevadí.
- Střed plátna = střed auta. Obrys karoserie (bez zrcátek) vyplní obdélník délka × šířka, tedy
  vnitřních 91 % plátna, a nesmí z něj vyčnívat (kolize a měřítko jsou z JSON).
- Silueta podle třídy jako procedurální kresba (`specs/cars.md` → „Kreslení“: poloha kabiny, korba
  pick-upu, rezerva terénního, spoiler supersportu, blatníky veteránu, nákladový prostor dodávky…),
  aby auto bylo stejně čitelné v obou podobách. Detaily (pruhy, cedule) v laku nebo neutrálně.
- **R10:** žádné reálné značky, loga, nápisy, SPZ ani podoba konkrétního skutečného modelu.

**Vrstvy na auto** (`assets/cars/<id>/…`, PNG s alfou, všechny stejně velké jako plátno):
- `body.png` – karoserie bez kol: okna, světla zhasnutá, stínování tvaru. **Lakované plochy
  světle šedé až bílé se stínováním** (hra je násobí barvou laku), nelakované části (sklo,
  nárazníky, chrom, cedule taxi) ve vlastních barvách.
- `paint_mask.png` – maska laku ve stupních šedi (bílá = lak, černá = ne, mezitóny na hranách),
  alfa jako `body.png` nebo plná.
- `wheel.png` – **jedno** kolo shora (pneu + disk), plátno těsně kolem kola, **na střed**; hra ho
  umístí, natáčí a zrcadlí sama. Velikost kola: délka `min(0,36 · L/2, W/2)` × šířka `0,32 · W/2`
  (v metrech × 32 px). Kola stojí na ose `±0,62 · L/2` od středu a `±0,92 · W/2` do stran
  (`content/tuning.yaml` → `drive.axle_offset`), autobus na +0,60 / −0,70 · L/2, tříkolka a rikša mají jedno přední
  kolo uprostřed na +0,75 · L/2 – body.png na těch místech nesmí mít nic, co by kolo zakrylo
  zvenku (podběh smí být tmavý). Třída `micro` (koloběžka, kolo, skútr) má kola i jezdce v `body.png`
  a `wheel.png` nemá.
- `lights.png` *(volitelné)* – jen rozsvícená světla na průhledném pozadí: přední teple bílá,
  zadní červená, na správných místech `body.png`. Hra je kreslí v noci; brzdová = zadní polovina
  plátna. Bez souboru kreslí světla kód.

**Taxi a hlídka:** taxi má střešní ceduli bez nápisu (žlutá/bílá, ve vlastní barvě, ne v laku)
a šachovnicový pruh v `body.png`. Hlídka (`assets/cars/police_patrol/…`, 4,9 × 1,95 m) je
fiktivní „City Patrol“ bez znaků a bez nápisu: `body.png` v barvách hlídky (bez masky laku),
`wheel.png`, na střeše prázdné pouzdro majáku napříč (±0,6 · W/2, hloubka 0,12 · L/2, střed
střechy) – blikající světla do něj kreslí kód. Hlídka v Praze a v Tokiu používá stejný sprite.

**Provoz:** auta provozu nemají model, jen jeden generický tvar 4,6 × 1,9 m s náhodným lakem
(`color.traffic.bodies`) – sprite `assets/cars/traffic_sedan/…` (body, paint_mask, wheel; plátno
67 × 162). Další generické tvary (`traffic_hatch`, `traffic_suv`, `traffic_van`) až v další dávce.

**První dávka** (nejvíc vidět: startovní auto, taxi, nejčastější zaparkovaná, provoz, hlídka) =
řádky s **1** + `traffic_sedan` (67 × 162) + `police_patrol` (69 × 173). `lidovka/body.png` už je
hotové (56 × 148), chybí k ní maska a kolo.

| dávka | id | jméno (fiktivní) | třída | délka × šířka m | plátno px (š × v) | lak | města |
|---|---|---|---|---|---|---|---|
| **1** | m0_coupe | Varga Comet | kupé | 4,5 × 1,9 | 67 × 159 | comet_red | nyc |
| **1** | taxi_metro | Halden Metro Cab | taxi | 5 × 1,9 | 67 × 176 | cab_yellow | nyc, tokyo |
| **1** | hatch_pip | Lumo Pip | hatchback | 3,9 × 1,75 | 62 × 138 | pip_teal | nyc, prague, tokyo |
| **1** | sedan_harbor | Halden Harbor | sedan | 4,8 × 1,85 | 66 × 169 | harbor_slate | nyc, tokyo |
| **1** | sedan_crown | Amberline Crown 300 | sedan | 5,2 × 1,9 | 67 × 184 | crown_wine | nyc, tokyo |
| **1** | van_courier | Halden Courier | dodávka | 5,4 × 2 | 71 × 191 | courier_white | nyc, tokyo |
| **1** | mini_pebble | Ostra Pebble | mini | 3 × 1,6 | 57 × 106 | pebble_sky | nyc, tokyo |
| **1** | pickup_hauler | Torvik Hauler | pick-up | 5,4 × 2 | 71 × 191 | hauler_green | nyc |
| **1** | muscle_brute | Corvan Brute 70 | muscle | 4,9 × 1,95 | 69 × 173 | brute_orange | nyc |
|  | bus_city | Halden Citybus 40 | autobus | 12 × 2,55 | 90 × 423 | citybus_blue | nyc |
|  | coupe_nova | Varga Nova | kupé | 4,4 × 1,82 | 65 × 155 | nova_jade | nyc |
|  | coupe_strada | Bellmar Strada GT | kupé | 4,6 × 1,85 | 66 × 162 | strada_pearl | nyc |
|  | hatch_city | Bellmar Civetta | hatchback | 4,1 × 1,75 | 62 × 145 | civetta_silver | nyc |
|  | hatch_rally | Talvik Rallye S | hatchback | 4 × 1,8 | 64 × 141 | rally_blue | nyc |
|  | kolo | Velo Brk | mikro | 1,8 × 0,6 | 22 × 64 | brk_blue | prague |
|  | kolobezka | Šlapka E | mikro | 1,2 × 0,55 | 20 × 43 | slapka_lime | prague |
|  | kombi_fjord | Talvik Fjord Estate | kombi | 4,9 × 1,85 | 66 × 173 | fjord_sage | nyc |
|  | kombi_woody | Corvan Country Woody | kombi | 5,3 × 1,95 | 69 × 187 | woody_tan | nyc |
|  | lidovka | Lidka 105 | sedan | 4,2 × 1,6 | 57 × 148 | lidka_cream | prague |
|  | limo_grand | Amberline Grand Stretch | limuzína | 8,2 × 2,05 | 73 × 289 | grand_white | nyc |
|  | limo_stretch | Nordquist Regent Stretch | limuzína | 7,6 × 2 | 71 × 268 | stretch_black | nyc |
|  | micro_cruiser | Hudsonia Cruiser | mikro | 1,8 × 0,6 | 22 × 64 | cruiser_cobalt | nyc |
|  | micro_scoot | Zip E-Scoot | mikro | 1,15 × 0,55 | 20 × 41 | scoot_aqua | nyc, tokyo |
|  | mini_bolt | Quillon Bolt E | mini | 3,4 × 1,7 | 60 × 120 | bolt_lime | nyc, tokyo |
|  | mini_dot | Lumo Dot | mini | 2,7 × 1,55 | 55 × 96 | dot_pink | nyc, tokyo |
|  | muscle_bulldog | Rennet Bulldog 8 | muscle | 5,1 × 1,98 | 70 × 180 | bulldog_plum | nyc |
|  | muscle_thunder | Corvan Thunder 69 | muscle | 5 × 1,95 | 69 × 176 | thunder_black | nyc |
|  | off_bloc | Nordquist Bloc G | terénní | 4,8 × 1,98 | 70 × 169 | bloc_olive | nyc |
|  | off_ridge | Torvik Ridge 4x4 | terénní | 4,7 × 1,95 | 69 × 166 | ridge_khaki | nyc |
|  | pickup_mesa | Rennet Mesa | pick-up | 5,6 × 2,05 | 73 × 198 | mesa_red | nyc |
|  | sedan_regent | Nordquist Regent | sedan | 5 × 1,88 | 67 × 176 | regent_navy | nyc |
|  | spec_grill | Rennet Grill Wagon | speciální | 7 × 2,3 | 81 × 247 | grill_tomato | nyc |
|  | spec_rickshaw | Pedalo Rickshaw | speciální | 2,6 × 1,2 | 43 × 92 | rickshaw_rose | nyc |
|  | spec_trike | Ostra Trike 3 | speciální | 3,2 × 1,5 | 53 × 113 | trike_violet | nyc |
|  | super_arrow | Kestrel Arrow R | supersport | 4,5 × 1,95 | 69 × 159 | arrow_gold | nyc, tokyo |
|  | super_lumen | Quillon Lumen EV | supersport | 4,7 × 1,98 | 70 × 166 | lumen_frost | nyc |
|  | super_vento | Ostra Vento | supersport | 4,4 × 1,92 | 68 × 155 | vento_green | nyc |
|  | taxi_classic | Corvan Metro Classic | taxi | 5,4 × 2 | 71 × 191 | classic_yellow | nyc |
|  | van_box | Torvik Boxline | dodávka | 6,6 × 2,2 | 78 × 233 | box_bone | nyc, tokyo |
|  | van_wander | Bellmar Wanderbus | dodávka | 4,6 × 1,8 | 64 × 162 | wander_amber | nyc |
|  | vega_roadster | Vega Roadster | supersport | 4 × 1,85 | 66 × 141 | vega_cherry | nyc, prague, tokyo |
|  | vet_skyliner | Amberline Skyliner 59 | veterán | 5,6 × 2 | 71 × 198 | skyliner_mint | nyc |
|  | vet_tourer | Halden Tourer 1931 | veterán | 4,6 × 1,75 | 62 × 162 | tourer_black | nyc |

Lak = klíč barvy v `design/tokens.json` → `color.carPaint` (hra ho dosadí; sprite ho nemaluje).

### 4. Chodci a hlídka
- `assets/peds/ped_<n>.png` – 8 chodců shora (dospělí), 32 px/m, 2 snímky chůze + 1 „uskočení“.
- Hlídka je v kapitole 3 (`assets/cars/police_patrol/…`).

### 5. M2 – budou potřeba později (stačí v pořadí)
- **Ikony HUD a telefonu** `assets/ui/<id>.png` 256×256, bílý glyf na alfě (tónovatelný,
  `specs/art.md` v3): `feed`, `map`, `taxi`, `garage`, `passport`, `camera`, `contacts`, `wallet`,
  `travel`, `settings`, `radio`, `weather_clear`, `weather_rain`, `weather_fog`, `wanted_star`.
- **Obchody a bary** (fiktivní podniky, R10): 6 výloh / vývěsních štítů shora 256×256
  (`assets/shops/`): kavárna, bar, pizzerie, suvenýry, stánek s hot dogy, bodega.
- **Telefonní budka** shora + zvonící stav (`assets/props/booth.png`, `booth_ring.png`).
- **Stanice metra**: vstup shora + ikona linky bez oficiálního loga MTA (fiktivní kolečka).
- **Fotomísta**: 20 pohledových ilustrací (výhledy, ne památky) 1080×1350,
  `assets/photos/nyc/<id>.png`, seznam = spoty `kind: photo` v `content/cities/nyc/spots.yaml`
  (jméno = co je na obrázku). Zatím hra obrázek nepotřebuje, jen do zásoby.
- **Počasí**: textura kapek a kaluží (tileable 512×512), mlha (gradient), odlesk mokré silnice.
- **Kosmetika** (`specs/garage.md` v2, `specs/art.md` v3, barvy kouře řeší kód):
  - 8 polepů `assets/garage/decals/<id>.png`, 512×1024, předek nahoru, bílý motiv na alfě
    (tónuje se `color.garage.decal`, klient ho roztáhne na plátno karoserie a ořízne maskou laku,
    takže žádné kruhy, které se v dlouhém autě zdeformují): `stripes`, `flames`, `checker`,
    `stars`, `lightning`, `waves`, `camo`, `halftone`.
  - 6 kol `assets/garage/wheels/<id>.png`, 128×128, kolmo shora jako `wheel.png`, světlý disk
    (tónuje se `color.garage.wheels`): `sport`, `whitewall`, `five_spoke`, `mesh`, `turbine`,
    `offroad`.
- **Minihry M2 (22):** skiny stolů a herních ploch 1080×1920 (dřevo, plsť, asfalt NYC):
  karty (1 sada 52 + žolík, fiktivní rub „Metropole“), kostky, šachovnice/dáma, kulečník,
  bowling, minigolf (dráhy s motivem NYC), vzdušný hokej, stickball ulice, švihadla Double Dutch.

### 6. Textury povrchů (objednané, dávka gtt-tex1)
`assets/cities/<city>/<id>.png`, tileable 512×512, shora, neutrální světlo: nyc/asphalt,
nyc/sidewalk_concrete, nyc/roof_tar, prague/cobblestone, prague/mosaic_sidewalk, prague/roof_tiles.

### 7. Suvenýry na poličku (M2-S5, `specs/shops.md`)
`assets/souvenirs/<id>.png`, 512×512, průhledné pozadí, jeden předmět zepředu ve stylu A, bez
textu a log (R10). Id = spot obchodu: `souvenir_times_sq` (sněžítko s mrakodrapy),
`souvenir_canal` (porcelánová kočka mávající tlapkou), `souvenir_battery` (soška ženy s pochodní,
bez nápisu), `souvenir_dumbo` (malý model visutého mostu), `souvenir_soho` (taška s abstraktním
vzorem). Do té doby klient kreslí ikonu a jméno.

## Hotovo

(sem připisovat dodané položky: cesta, datum, poznámka)

- **Style board v1**, 22. 11. 2026: Ol1n vybral NYC = A (plochý vektor), Praha = C (risograf).
  Sprity, postavy a UI sdílené ve stylu A. Paleta a parametry risografu předány zvlášť (tokens, tuning).
- `assets/npc/<id>.png` (= `_neutral`), `<id>_happy|_neutral|_annoyed.png` 1024², `<id>_bust.png`
  768×1280 (výraz happy), 22. 11. 2026, všech 6 postav, průhledné pozadí (BiRefNet-general, `tools/art/run_rmbg.py`).
- `assets/cars/lidovka/body.png`, 22. 11. 2026, karoserie Lidky kolmo shora 56×148 (32 px/m, plátno +10 %),
  alfa. `paint_mask.png` a `wheel.png` zatím chybí, ostatní auta taky (zatím jen test postupu).
- `assets/postcards/nyc/*.png`, 22. 11. 2026, všech 34 (amnh z ostrého úhlu se štítem bez nápisu).
- `assets/postcards/prague/*.png`, 22. 11. 2026, všech 20.
- `assets/souvenirs/<id>.png`, 23. 11. 2026, všech 5 (times_sq, canal, battery, dumbo, soho), 512², průhledné
  pozadí, styl A, bez textu.
- Postup: `tools/art/make_batch1.py` (prompty, seedy) + `tools/art/run_board.py` (workflow ComfyUI).
- `assets/cities/prague/{cobblestone,mosaic_sidewalk,roof_tiles}.png` a `assets/cities/nyc/asphalt.png`,
  22. 11. 2026, tileable 512×512, 256 barev.
- `assets/cities/nyc/{sidewalk_concrete,roof_tar}.png`, 22. 11. 2026, procedurálně (`tools/art/proc_tex.py`):
  chodník 4×4 desky se spárami, střecha štěrk se švy. Tím je sada textur kompletní.
- **Tokio** (styl D, anime cel), 23. 11. 2026: `assets/postcards/tokyo/*.png` všech 25 podle
  `content/cities/tokyo/landmarks.yaml`, bez nápisů (zbylé falešné znaky na štítech a lampionech přebarveny plochou
  barvou), `assets/cities/tokyo/` asphalt, sidewalk_tile, roof (procedurálně), `assets/styleboard/tokyo/`
  (2× křižovatka v pohledu 3/4 a 1× pohlednice, jen reference palety).
- **Auta, dávka 1**, 23. 11. 2026: `assets/cars/<id>/{body,paint_mask,wheel,lights}.png` pro m0_coupe,
  taxi_metro, hatch_pip, sedan_harbor, sedan_crown, van_courier, mini_pebble, pickup_hauler, muscle_brute,
  traffic_sedan a police_patrol (bez masky), procedurálně (`tools/art/cars_proc.py`), plátna podle tabulky.
  Lidovka: k hotovému body.png lak převeden na šedou, výřezy pro kola, doplněny maska, kolo a světla
  (`tools/art/post_lidovka.py`).
- **Auta, dávka 2**, 23. 11. 2026: zbylých 33 aut z tabulky (všechna kromě dávky 1 a lidovky), procedurálně
  (`tools/art/cars_proc.py`). Třída micro (kolo, micro_cruiser, kolobezka, micro_scoot) má kola a jezdce v body.png,
  bez wheel.png a lights.png; rikša bez lights.png. Rozdíly proti procedurální kresbě kvůli pravidlu „kolo zvenku
  nezakryté“: markýza food trucku −0,42…0,40 hl (místo −0,60…0,30), blatníky veteránů jen uvnitř a před a za koly,
  rezerva terénních aut uvnitř obrysu.
- **Lidovka, oprava**, 23. 11. 2026: `assets/cars/lidovka/*` nově procedurálně (`tools/art/cars_proc.py`), 57×148,
  souměrná, karoserie 51 px na šířku, výřezy pro kola, čistě kolmo shora (nahrazuje body.png z ComfyUI).
- **Ikony HUD a telefonu (dávka ui1):** `assets/ui/<id>.png` 256×256, id podle `phoneAppIds` (feed, map, taxi, garage, passport, camera, contacts, wallet, travel, settings) + radio, weather_clear, weather_rain, weather_fog, wanted_star. Bílý glyf na průhledném pozadí, klient ho tónuje (`color.phone.app`/`appOff`, `color.weather.icon`); `tools/art/ui_icons.py`.
- **Kosmetika garáže (dávka garage1):** polepy `assets/garage/decals/<id>.png` 512×1024 (stripes, flames, checker, stars, lightning, waves, camo, halftone = volby 1–8), předek nahoru, bílý motiv na alfě, tvary navržené pro poměr auta ~2,6 a s roztažením 2,2–3,5 snesitelné; kola `assets/garage/wheels/<id>.png` 128² (sport, whitewall, five_spoke, mesh, turbine, offroad = volby 1–6), tmavá pneumatika a světlý disk. `tools/art/garage_cosmetics.py`. Rastr (halftone) je z kosočtverců, ne z kroužků.

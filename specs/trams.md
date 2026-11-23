# Tramvaje

**version: 2** · P1 (jízda po kolejích, testy deterministických částí v obou klientech) / P2
(kreslení) · plán: METROPOLE_PLAN 5.6 (Praha: tramvaje), `plans/M3_PRAHA.md` bod 5 · parita F-030

## Účel

Praha bez tramvají není Praha. Tramvaje jezdí po skutečných kolejích, staví na zastávkách, mají
přednost a nedají se odtlačit. Hráč do nich může narazit, auta provozu za nimi čekají. Čísla jsou
v `content/tuning.yaml` (`trams`), barvy v `design/tokens.json` (`color.trams`). Vypínač
`trams.enabled`; město bez kolejí tramvaje nemá.

## Data (citypack, `specs/citypack.md` v3)

- Soubor `trams.pb` (`TramGraph`, `tools/citypack/proto/citypack.proto`): uzly a hrany kolejí ze segmentů Overture `subtype: rail`,
  `class: tram`, rozdělené v konektorech a oříznuté oblastí stejně jako silnice (hraniční uzel =
  konec tratě). Hrana nese body lomené čáry (dm), vrstvu na začátku a konci (most/tunel jako u
  silnic) a příznak `border` u uzlů. Nechá se jen největší souvislá komponenta; kolej kratší než
  `trams.min_track_m` od zbytku (vlečky, smyčky v depu) se zahodí.
- Kolej je vždy obousměrná (dvojkolejka je v datech jako dvě rovnoběžné hrany; jednokolejka
  se jezdí oběma směry, tramvaje se na ní nepotkají, viz krok 1).
- **Zastávky** generuje balíček (Overture tramvajové zastávky nemá): koleje se rozdělí na úseky
  mezi výhybkami (řetězy hran spojených v uzlech s právě dvěma hranami, hraniční uzel řetěz
  ukončí). Na úseku delším než `trams.stop_min_chain_m` stojí zastávky ve vzdálenostech
  `stop_spacing_m / 2`, `+ stop_spacing_m`, … od začátku úseku; pozice na mostě, v tunelu nebo
  mimo vrstvu 0 se vynechá. Zastávka = (hrana, `s_m` od `from` konce hrany). Dvojkolejka má
  zastávky na obou kolejích. Stejný vstup = stejné zastávky.
- Soubor `trams.pb` má od `specs/citypack.md` v3 každé město; bez kolejí je graf prázdný.

## Stav

Tramvaj: hrana, směr (+1 / −1), `s` (m), rychlost, vrstva, časovač stání na zastávce, časovač po
nárazu, počet článků (`trams.cars_per_tram`), poloha a natočení každého článku, **historie hran**
(v2): posledních nejvýš `trams.trail_points` hran celé projetých za čelem (hrana, směr), nejnovější
první.

Délka tramvaje `D = cars_per_tram · car_length_m + (cars_per_tram − 1) · joint_gap_m`.

## Deterministické funkce (oba klienti, stejné výsledky v testech)

- **Sjízdnost přechodu (v2):** v uzlu `n` se z hrany `a` na hranu `b` smí jen přes úhel nejvýš
  `trams.max_switch_deg`. Směr příjezdu = z bodu na `a` ve vzdálenosti `trams.turn_probe_m` od `n`
  (u kratší hrany její druhý konec) do `n`; směr odjezdu = z `n` do bodu na `b` ve vzdálenosti
  `turn_probe_m`. Sjízdné, když kosinus úhlu mezi nimi ≥ `cos(max_switch_deg)`; nulový směr =
  sjízdné. Overture spojuje koleje v konektorech bez ohledu na výhybky: v rozvětvení (Y) by bez
  tohoto pravidla tramvaj z jedné větve vjela do druhé vlásenkou (≈ 160°), na křížení (X) by zahnula
  o 90° na místě. V Praze to byla polovina přechodů ve výhybkách.
- **Volba další hrany** jako u provozu (`specs/traffic.md`), jen nad grafem kolejí, bez
  jednosměrek a uliček: kandidáti vzestupně podle indexu bez `e`, bez smyček a jen **sjízdní**
  (v2), volba `prng.nextInt(počet)`; bez kandidátů konečná (změna čela, níže), hraniční uzel =
  tramvaj zmizí.
- **Nejpřímější předchůdce (v2):** hrana `p ≠ b` v uzlu `n` (ne smyčka), ze které je přechod na `b`
  sjízdný, s největším kosinem úhlu; při shodě nižší index. Hraniční uzel nebo žádná = −1.
- **Odstup článků:** článek `k` stojí na dráze `s − k · (článek + mezera)` zpět po projeté trase
  (tramvaj si drží posledních `trams.trail_points` bodů své cesty); natočení článku = směr mezi
  jeho předním a zadním kloubem. Funkce `articulate(trail, k)` je čistá.
- **Zastávka vpředu:** nejbližší zastávka na hraně ve směru jízdy dál než `trams.stop_commit_m`.
- **Konečná vpředu (v2):** koncový uzel aktuální hrany ve směru jízdy, který není hraniční a nemá
  žádného sjízdného kandidáta.

## Plynulost (v2, akceptace L-S10)

Natočení článku sleduje kolej plynule: na celé síti města je změna **osy** článku (natočení
modulo π) na metr dráhy čela tramvaje nejvýš `trams.max_turn_deg_per_m`. Test (oba klienti, balíček
Prahy, když je k dispozici): (1) pro každý uzel, každou příjezdovou hranu a každou sjízdnou
odjezdovou hranu projede tramvaj (`articulate` po stopě) celou příjezdovou i odjezdovou hranu po
krocích 0,1 m; (2) každá hrana celá v obou směrech; (3) živé tramvaje (vznik, výhybky, zastávky,
konečné) kolem dvanácti zastávek po 120 s. Stojící tramvaj ani změna čela osu nemění.
Před v2 bylo v Praze maximum 1 800 °/m (otočka na místě, vlásenky ve výhybkách), po v2 9,7 °/m.

## Krok tramvaje (P1, pevný krok `drive.step_hz`)

1. **Překážka vpředu:** nejbližší z (a) hráče, (b) auta provozu, (c) jiné tramvaje, (d) zastávky
   (jen když tramvaj na ní ještě nestála), (e) konečné vpředu (v2; čelo zastaví v koncovém uzlu,
   jako u zastávky se přičte `min_gap_m`). Hráč, auto a tramvaj se počítají ve stejné vrstvě před
   čelem do `trams.look_ahead_m` a bočně do `trams.corridor_m` od osy koleje. Jiná tramvaj
   v protisměru na téže hraně (jednokolejka) se počítá jako překážka jen té, která do hrany
   vjela později. Jiná tramvaj se počítá jen se směrem do ±60° od vlastního (jinak by se
   blokovaly tramvaje na sousední koleji dvojkolejky).
2. **Cílová rychlost:** jako u provozu (`specs/traffic.md` krok 2) s `trams.speed_mps`,
   `trams.accel_mps2`, `trams.brake_mps2`, `trams.min_gap_m`. U zastávky zastaví čelem na
   zastávce a stojí `trams.dwell_s`; pak zvoní (P2 zvuk) a jede.
3. **Posun:** `s += v · dt`, na konci hrany volba další hrany; opouštěná hrana jde do historie.
   Na konečné čelo zůstane v koncovém uzlu (`s` = délka hrany) a tramvaj **změní čelo** (v2):
   - Ocas = bod `D` za čelem po aktuální hraně a dál po historii. Neleží-li na známé cestě
     (historie nestačí), tramvaj zmizí.
   - Nové čelo = ocas: hrana ocasu se jede opačným směrem, `s` = zbytek `D` na té hraně (měřeno od
     konce, ke kterému dřív jela). Nová historie = hrany mezi ocasem a starým čelem v opačném směru,
     nejbližší k novému čelu první. Nová stopa = body cesty od ocasu ke starému čelu.
   - Články stojí na místě: pořadí se obrátí (poslední je první), natočení každého `+ π` (osa se
     nehne), tělesa se přesunou přímo (bez úhlové rychlosti). Rychlost 0, stání `trams.dwell_s`,
     zastávky se zapomenou, vjezd do hrany = tento krok.
4. **Tělo:** každý článek je kinematické těleso `trams.car_length_m × trams.car_width_m`
   (bez `car_scale`, rozměry jsou už ve světových metrech), kategorie `CAT_TRAM = 64`, maska
   `CAT_CAR | CAT_TRAFFIC | CAT_PARKED`, ve stejné vrstvě. Hráč do něj narazí a odrazí se jako od
   zdi, tramvaj se nepohne (žádné odstrčení jako v `specs/traffic.md` kroku 7).
5. **Náraz hráče:** překryv obdélníků hráče a článku (SAT, rezerva `traffic.hit_margin_m`, obdélník
   hráče zvětšený o `drive.body_round_m` jako u provozu) s rychlostí ≥ `trams.hit_min_mps` = událost „tramvaj trefená
   hráčem“ (pro policii a dialogy); tramvaj stojí `trams.hit_stop_s`.

Provoz (`specs/traffic.md` v3) bere tramvaj jako překážku vpředu (krok 1, bod b) se stejným
koridorem jako auta. Semafory tramvaje nerespektují (přednost, vědomé zjednodušení M3).

## Hustota a vznik

Jako provoz: cíl `trams.max_trams`, vznik v mezikruží `trams.spawn_min_m … spawn_max_m` kolem
hráče na náhodné hraně kolejí ve vrstvě 0, volno `trams.spawn_clear_m`; zmizí dál než
`trams.despawn_m`. Sdílený PRNG se seedem `trams.seed`.

Cesta za novou tramvají (v2): od začátku její hrany zpět po nejpřímějších předchůdcích, dokud
pokrytá délka (`s` + délky předchůdců) nedosáhne `D`, hraničního uzlu, uzlu bez předchůdce nebo
plné historie; body předchůdců jdou do stopy, hrany do historie (PRNG se nečerpá). Za koncem
stopy pokračuje přímka jako ve v1.

## Kreslení (P2)

- Koleje: dvě kolejnice po každé hraně (`trams.rail_gauge_m` od sebe), barva
  `color.trams.rail`, kreslí se nad silnicí a pod auty.
- Zastávky: ostrůvek podél koleje `color.trams.stop`, cedulka.
- Článek: obdélník se zaoblenými rohy, barva `color.trams.body`, pruh `color.trams.stripe`,
  okna `color.trams.window`, v noci `color.trams.windowLit`; články od sebe `trams.joint_gap_m`.

## API

`trams.items` (články: poloha, natočení, vrstva), `trams.onHit(fn)`, `trams.stops`.

## Vědomá zjednodušení (v2)

- Zastávka vpředu se hledá jen na aktuální hraně; zastávku těsně za začátkem další hrany
  tramvaj nestihne ubrzdit a vynechá ji.
- Na konečné tramvaj změní čelo (obousměrný vůz) místo otočení ve smyčce; krátké smyčky
  balíček zahazuje (`min_track_m`). Stín článku se kreslí v jeho souřadnicích, po změně čela
  tedy přeskočí na druhou stranu (≈ 0,8 m).
- Konečná se brzdí jen na hraně, která do ní vede; je-li kratší než brzdná dráha, tramvaj
  zastaví prudčeji.
- Po změně čela na jednokolejné koncovce může stát proti tramvaji, která za ní přijíždí; ta
  vjela do hrany dřív, takže ji projede (jako ve v1 na jednokolejce).
- Natočení článku je tětiva mezi klouby po lomené čáře koleje; v ostrém lomu dat (≤
  `max_switch_deg`) se článek otočí na délce článku, ne po oblouku.
- Na jednokolejce tramvaj, která do hrany vjela dřív, protijedoucí projede (tramvaje spolu
  nekolidují). V Praze jsou koleje dvojkolejné, takže se to skoro nestane.
- Proporce kolejnic, ostrůvku a oken jsou poměry v kódu klienta (jako vodorovné značení).

## Hraniční případy

- Hráč stojí na koleji: tramvaj před ním zastaví a čeká (neodtlačí ho ani ho neobjede).
- Koleje bez zastávek (krátké hrany): tramvaj jen projíždí.
- Město bez `trams.pb` nebo s prázdným grafem: žádné tramvaje, nic dalšího se nemění.

# Tramvaje

**version: 1** · P1 (jízda po kolejích, testy deterministických částí v obou klientech) / P2
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
nárazu, počet článků (`trams.cars_per_tram`), poloha a natočení každého článku.

## Deterministické funkce (oba klienti, stejné výsledky v testech)

- **Volba další hrany** jako u provozu (`specs/traffic.md`), jen nad grafem kolejí, bez
  jednosměrek a uliček: kandidáti vzestupně podle indexu bez `e`, volba `prng.nextInt(počet)`;
  bez kandidátů otočka (konečná), hraniční uzel = tramvaj zmizí.
- **Odstup článků:** článek `k` stojí na dráze `s − k · (článek + mezera)` zpět po projeté trase
  (tramvaj si drží posledních `trams.trail_points` bodů své cesty); natočení článku = směr mezi
  jeho předním a zadním kloubem. Funkce `articulate(trail, k)` je čistá.
- **Zastávka vpředu:** nejbližší zastávka na hraně ve směru jízdy dál než `trams.stop_commit_m`.

## Krok tramvaje (P1, pevný krok `drive.step_hz`)

1. **Překážka vpředu:** nejbližší z (a) hráče, (b) auta provozu, (c) jiné tramvaje, (d) zastávky
   (jen když tramvaj na ní ještě nestála). Hráč, auto a tramvaj se počítají ve stejné vrstvě před
   čelem do `trams.look_ahead_m` a bočně do `trams.corridor_m` od osy koleje. Jiná tramvaj
   v protisměru na téže hraně (jednokolejka) se počítá jako překážka jen té, která do hrany
   vjela později.
2. **Cílová rychlost:** jako u provozu (`specs/traffic.md` krok 2) s `trams.speed_mps`,
   `trams.accel_mps2`, `trams.brake_mps2`, `trams.min_gap_m`. U zastávky zastaví čelem na
   zastávce a stojí `trams.dwell_s`; pak zvoní (P2 zvuk) a jede.
3. **Posun:** `s += v · dt`, na konci hrany volba další hrany.
4. **Tělo:** každý článek je kinematické těleso `trams.car_length_m × trams.car_width_m`
   (bez `car_scale`, rozměry jsou už ve světových metrech), kategorie `CAT_TRAM = 64`, maska
   `CAT_CAR | CAT_TRAFFIC | CAT_PARKED`, ve stejné vrstvě. Hráč do něj narazí a odrazí se jako od
   zdi, tramvaj se nepohne (žádné odstrčení jako v `specs/traffic.md` kroku 7).
5. **Náraz hráče:** překryv s rychlostí ≥ `trams.hit_min_mps` = událost „tramvaj trefená
   hráčem“ (pro policii a dialogy); tramvaj stojí `trams.hit_stop_s`.

Provoz (`specs/traffic.md` v3) bere tramvaj jako překážku vpředu (krok 1, bod b) se stejným
koridorem jako auta. Semafory tramvaje nerespektují (přednost, vědomé zjednodušení M3).

## Hustota a vznik

Jako provoz: cíl `trams.max_trams`, vznik v mezikruží `trams.spawn_min_m … spawn_max_m` kolem
hráče na náhodné hraně kolejí ve vrstvě 0, volno `trams.spawn_clear_m`; zmizí dál než
`trams.despawn_m`. Sdílený PRNG se seedem `trams.seed`.

## Kreslení (P2)

- Koleje: dvě kolejnice po každé hraně (`trams.rail_gauge_m` od sebe), barva
  `color.trams.rail`, kreslí se nad silnicí a pod auty.
- Zastávky: ostrůvek podél koleje `color.trams.stop`, cedulka.
- Článek: obdélník se zaoblenými rohy, barva `color.trams.body`, pruh `color.trams.stripe`,
  okna `color.trams.window`, v noci `color.trams.windowLit`; články od sebe `trams.joint_gap_m`.

## API

`trams.items` (články: poloha, natočení, vrstva), `trams.onHit(fn)`, `trams.stops`.

## Hraniční případy

- Hráč stojí na koleji: tramvaj před ním zastaví a čeká (neodtlačí ho ani ho neobjede).
- Koleje bez zastávek (krátké hrany): tramvaj jen projíždí.
- Město bez `trams.pb` nebo s prázdným grafem: žádné tramvaje, nic dalšího se nemění.

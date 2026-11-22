# Provoz a semafory

**version: 3** · P1 (jízda aut v reálném čase) · deterministické části testované v obou klientech
· plán: METROPOLE_PLAN 7.3, M1 bod 2 · parita F-016

## Účel

Město nemá být prázdné: AI auta jezdí po pruzích ponechaných silnic, drží odstup, stojí na
semaforech. Hráč do nich může narazit. Pozdější funkce (policie, chodci) čtou seznam aut a událost
„auto trefené hráčem“. Všechna čísla jsou v `content/tuning.yaml` (`traffic`), barvy v
`design/tokens.json` (`color.traffic`). Vypíná se `traffic.enabled`.

## Stav

- **Semafor** (jen při načtení města): uzel, poloha, posun fáze `offset` (ms), přístupy.
- **Přístup** k semaforu = hrana, po které se do uzlu smí přijet: skupina 0/1, vzdálenost stop čáry
  od uzlu, poloha návěstidla.
- **Auto:** hrana, směr (+1 from → to, −1 to → from), dráha `s` od začátku hrany ve směru jízdy (m),
  pruh, rychlost (m/s), vrstva, vlastní PRNG, časovač zastavení po nárazu, barva (index do
  `color.traffic.bodies`), poloha a natočení.

## Deterministické funkce (oba klienti, stejné výsledky v testech)

### Semafory

- Uzel je semafor, když se v něm potkají aspoň `signal_min_edges` různých ponechaných hran
  (`kept`, bez smyček), aspoň `signal_min_main` z nich má třídu z `signal_classes`
  (index `RoadClass`) a všechny jsou v uzlu ve vrstvě 0 (`layer_from` u `from`, `layer_to` u `to`).
- **Skupina přístupu:** směr hrany z uzlu = vektor od uzlu k prvnímu odlišnému bodu polylinie,
  v celých decimetrech (`round(m · 10)`). Referenční směr má hrana s nejnižším indexem v uzlu.
  Skupina 0, když `|cross(ref, v)| < |dot(ref, v)|` (osy svírají méně než 45°), jinak 1.
  Počítá se v celých číslech, takže oba klienti rozdělí přístupy stejně.
- **Cyklus:** `cycle = 2 · (green_ms + amber_ms + all_red_ms)`.
- **Posun:** `offset = Prng((imul(node, 2654435761) + signal_seed) mod 2^32).nextInt(cycle)`
  (`specs/prng.md`; součin bere jen dolních 32 bitů).
- **Fáze** v čase `t` (ms, celé): `p = (t + offset) mod cycle`; pro skupinu 0 zelená při
  `p < green`, oranžová při `p < green + amber`, jinak červená; skupina 1 totéž s `p − cycle/2`
  (mod `cycle`). Výsledek: 0 zelená, 1 oranžová, 2 červená.
- **Hodiny:** `t = floor(krok · 1000 / drive.step_hz)`, kde krok je počet pevných kroků od spuštění.
- **Stop čára:** `max(width / 2)` ostatních ponechaných hran v uzlu + `stop_margin_m`.
- **Řetězy:** balíček dělí silnice v každém uzlu, takže přístupová hrana bývá kratší než stop čára.
  Proti směru jízdy se přístup přenáší na předchozí hrany přes uzly s právě dvěma ponechanými
  hranami (bez semaforu a zátarasu, jen když se po předchozí hraně do uzlu smí jet), dokud
  `vzdálenost konce hrany od semaforu − stop čára < look_ahead_m`. Hrana pak nese index přístupu
  a tuto vzdálenost (`extra`); vzdálenost auta ke stop čáře = `délka − s + extra − stop čára −
  poloviční délka auta`.
- **Návěstidlo:** na přístupové hraně ve vzdálenosti stop čáry od uzlu, napravo od směru jízdy do
  uzlu (při `drive_side = left` nalevo) na okraji vozovky + `light_side_m`.

### Pruhy

- Vozovka: `c = max(width − 2 · sidewalk_width_m, lane_width_m) / 2`, pruhů
  `L = max(1, round(2c / lane_width_m))` (stejně jako vodorovné značení).
- Obousměrná hrana: na každý směr `n = max(1, floor(L / 2))` pruhů, pruh `i` (0 = nejblíž středu)
  má odsazení `(i + 0.5) · c / n` napravo od směru jízdy.
- Jednosměrná hrana: `n = L`, odsazení `c − (i + 0.5) · 2c / L` napravo (0 = krajní pravý pruh).
- `drive_side = left`: odsazení se zrcadlí (nalevo). Při přechodu na další hranu se pruh omezí na
  `min(i, n − 1)`.

### Volba další hrany

Auto dojede do uzlu `n` po hraně `e`. Kandidáti = hrany `nodeEdges[n]` vzestupně podle indexu, bez
duplicit a smyček, `kept = true`, různé od `e`, a z uzlu `n` po nich lze vyjet (`oneway = 0`;
`1` jen když `from = n`; `−1` jen když `to = n`). Volba `kandidáti[prng.nextInt(počet)]`.
Bez kandidátů: otočka zpět po `e`, když z `n` po ní lze vyjet, jinak −1 (auto zmizí). Hraniční uzel
(`border`, zátaras) = auto zmizí. Uličky (`kept = false`) auto nikdy nepoužije.

## Krok auta (P1, pevný krok `drive.step_hz`)

1. **Překážka vpředu:** nejbližší z (a) hráče ve stejné vrstvě, (b) AI auta ve stejné vrstvě se
   směrem do ±60° od vlastního nebo článku tramvaje ve stejné vrstvě v jakémkoli směru (v3,
   `specs/trams.md`), (c) stop čáry na konci hrany, když je semafor červený nebo oranžový
   a auto je od čáry dál než `amber_commit_m` (při oranžové). Auto/hráč se počítá, když leží před
   autem do `look_ahead_m` a bočně do `corridor · (pološířka + pološířka)`; mezera = podélná
   vzdálenost minus poloviční délky.
2. **Cílová rychlost:** `min(class_speed_mps[třída], max(0, g − min_gap_m) / headway_s,
   sqrt(2 · brake_mps2 · max(0, g − min_gap_m)))`, kde `g` je mezera k překážce; rychlost se k cíli
   blíží nejvýš `accel_mps2` nahoru a `brake_mps2` dolů.
3. **Posun:** `s += v · dt`; na konci hrany volba další hrany (výše).
4. **Poloha:** bod pruhu v `s`; skutečná poloha a natočení se k němu blíží exponenciálně
   (`follow_rate`, 1/s), což zaoblí zatáčky a přeskoky mezi pruhy.
5. **Tělo:** kinematické těleso (planck ve W, forge2d ve F) o rozměrech `car_length_m × car_width_m
   × car_scale`, hustota `mass_kg / plocha`; rychlost těla = (nová poloha − stará) / dt, takže hráč
   do auta narazí a odrazí se. Kategorie `CAT_TRAFFIC`; koliduje s hráčem ve stejné vrstvě a ve
   vrstvě 0 se zaparkovanými auty (`CAT_PARKED`, kinematické auto je odsune). AI auta se navzájem
   nesrážejí (na křižovatkách bez semaforu se mohou krátce překrýt – vědomé zjednodušení M1).
6. **Náraz:** po kroku fyziky test překryvu obdélníků hráče a auta (SAT, rezerva `hit_margin_m`).
   Začátek překryvu při relativní rychlosti ≥ `hit_min_mps` = událost „auto trefené hráčem“
   (auto, rychlost nárazu); auto stojí `hit_stop_s`, pak pokračuje.
7. **Odstrčení (v2):** každý krok s překryvem (při jakékoli rychlosti) nastaví `push_hold_s`.
   Auto je **volné**, dokud běží `hit_stop_s` nebo `push_hold_s`: těleso je dynamické (útlum
   `push_linear_damping`, `push_angular_damping`), hráč ho odtlačí, ve vrstvě 0 navíc koliduje
   s budovami (`CAT_BUILDINGS`); poloha a natočení se čtou z tělesa, rychlost v pruhu je 0.
   Po skončení je těleso zase kinematické, `s` = průmět polohy na vlastní hranu (nejbližší úsek)
   a auto se do pruhu vrátí přes `follow_rate`. Hráč obklíčený auty se tak vždy vytlačí ven.
8. **Objíždění zaparkovaných aut (v2):** v kroku 4 se cílový bod pruhu posune bočně o `shift`.
   Pro každé zaparkované auto ve vrstvě 0: `lx` = vzdálenost před skutečnou polohou auta (ta se za
   bodem pruhu opožďuje), `ly` = vzdálenost doprava od bodu pruhu, obojí ve směru jízdy; boční přesah `ext = phl · |sin Δ| + phw · |cos Δ|` (Δ = rozdíl natočení), potřeba
   `need = pološířka + ext + swerve_margin_m`. Počítá se, když `−(hl + phl) ≤ lx ≤ swerve_ahead_m
   + hl + phl` a `|ly| < need`: vpravo (`ly ≥ 0`) posun `ly − need` (doleva), vlevo `ly + need`.
   `shift` = posun s největší absolutní hodnotou; je-li větší než `swerve_max_m`, `shift = 0`
   (auto se neobjíždí a odsune ho těleso). Funkce `swerveShift` je čistá a testovaná v obou klientech.

## Hustota a vznik

- Cílový počet `round(max_cars · (noc ? night_factor : 1))`, nikdy víc než `max_cars`
  (strop dynamických těles provozu, METROPOLE_PLAN 7.3).
- Každých `spawn_interval_s` nejvýš `spawn_tries` pokusů: náhodný bod v mezikruží
  `spawn_min_m … spawn_max_m` kolem hráče, nejbližší ponechaná hrana do `search_m`, přijetí
  s pravděpodobností `class_weight[třída]`, ve volném místě (`spawn_clear_m` od jiného auta),
  náhodný povolený směr a pruh. Po startu a po přesunu hráče se mezikruží začíná už na
  `initial_min_m` a plní se najednou.
- Auto dál než `despawn_m` od hráče zmizí. Náhoda pro vznik i pro volbu hran je ze sdíleného PRNG
  (`seed`); fyzika a čas rámců dělají z celku P1, ne P0.

## Kreslení (P2)

Auta shora jako auto hráče, barva karoserie z `color.traffic.bodies`, brzdová světla při brzdění.
U každého přístupu k semaforu v dohledu malé návěstidlo (`lightHousing` + `lightRed/Amber/Green`),
nejvýš `light_draw_max`. Auta v tunelu jsou vidět jen v tunelu. Bez alokací v kroku a v rámci.

## API pro další funkce

`traffic.cars` (poloha, natočení, rychlost, vrstva), `traffic.onHit(fn)` (auto, rychlost nárazu),
`traffic.hits` (počet), `traffic.night`, `traffic.addCar(hrana, směr, s, pruh)` (např. policie).
`traffic.solid = false` udělá z hráče ducha (žádné srážky, nárazy ani čekání za ním); nastavuje ho
autopilot měření D1 (`specs/bench.md`), který auta neobjíždí.

## Hraniční případy

- Hrana s nulovou délkou: auto ji projede v jednom kroku.
- Semafor s jedinou skupinou (všechny přístupy v ose): skupina 1 nemá přístupy, auta čekají jen svou
  červenou.
- Hráč stojí v pruhu: auto za ním zastaví a čeká (hráče neobjíždí); hráč ho může odtlačit (krok 7).

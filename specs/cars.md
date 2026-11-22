# Auta, přesedání a garáž (M1-S8)

**version: 2** · P0 vlastnictví a garáž (`vectors/cars.json`) · P2 zaparkovaná auta a kreslení ·
METROPOLE_PLAN 7.5, 10, M1 bod 8 · parita F-018

## Účel
Hráč má vlastní auta a smí přesednout do kteréhokoli zaparkovaného auta ve městě. V garáži si
vybere jedno ze svých aut. Převzetí cizího auta nastaví příznak `stolen`, který čte policie
(pozdější feature) a na který reaguje majitel hláškou (feature dialogů). Nákup aut přijde
s hotovostí (M1-S11); pravidla na něj jsou připravená už teď.

## Obsah
- Auta: `content/cars/<id>.json` podle `schema/car.schema.json`. M1 má 5 aut (plán 10), každé jiné
  třídy: `m0_coupe` (kupé), `hatch_pip` (hatchback), `muscle_brute` (muscle), `taxi_metro`
  (taxi, žlutý sedan), `pickup_hauler` (pick-up). Jména jsou smyšlená (R10).
- `paint` v autě je klíč do `design/tokens.json` → `color.carPaint` (mapa klíč → barva). Barva
  karoserie tak žije jen v tokenech; klient ji najde přes `Tokens.colorCarPaint[paint]`
  (TS `tokens.colorCarPaint[paint]`).
- Čísla: `content/tuning.yaml` → `cars` (start, prahy přesedání a garáže, zaparkovaná auta).
- Garáž je spot `kind: garage` v `content/cities/<město>/spots.yaml` (balíček města ho nese
  v `spots.pb`; po změně YAML se balíček přestaví a publikuje). Jedna garáž na město v M1.

## Stav (P0, modul `cars`)
```
config: {prices: {<carId>: int}, cash: int, owned: [carId], driving: carId}
state:  {cash: int, owned: [carId], driving: carId, stolen: bool, thefts: int}
```
- `prices` – ceny všech aut katalogu (z `price` v autech); klíč = známé auto.
- `owned` – vlastní auta v pořadí, jak přibyla. `driving` – auto, které hráč právě řídí.
- `stolen` – hráč řídí cizí auto. `thefts` – kolikrát za hru převzal cizí auto.
- Start: `cash = cars.start_cash`, `owned = cars.start_owned`, `driving = cars.start_car`.

## Akce
Každá akce má `by: "player"` a `op`:
- `{op: "board", car, owner}` – přesednutí do zaparkovaného auta; `owner` je `"player"`
  (vlastní auto, které hráč dřív odstavil) nebo `"npc"` (cizí auto).
- `{op: "select", car}` – v garáži: vyjet s vlastním autem.
- `{op: "buy", car}` – v garáži: koupit auto (UI ho nabídne až s hotovostí, M1-S11).

Kde smí hráč akci udělat (u zaparkovaného auta, v garáži), hlídá UI; pravidla řeší jen stav.

## Pravidla
- `init(config, seed)` – stav ze startu výše; `seed` se nepoužívá (žádná náhoda).
- `board`: `car` musí být v `prices` (je to model; stejný model jako `driving` je povolený – ve
  městě parkuje víc aut stejného modelu); `owner = "player"` vyžaduje `car ∈ owned`. Výsledek: `driving = car`, `stolen = (owner == "npc")`,
  `thefts += 1`, pokud `owner == "npc"`.
- `select`: `car ∈ owned` a zároveň (`car ≠ driving` nebo `stolen`). Výsledek: `driving = car`,
  `stolen = false`.
- `buy`: `car ∈ prices`, `car ∉ owned`, `cash ≥ prices[car]`. Výsledek: `owned` + `car` na konec,
  `cash −= prices[car]`; `driving` se nemění.
- Cokoli jiného je nepovolená akce (`IllegalAction`).
- `legalActions(state)`: nejdřív `select` pro každé auto z `owned` (v pořadí `owned`), které
  splňuje podmínku, potom `buy` pro každé dostupné auto v abecedním pořadí id. `board` se
  nevyjmenovává (záleží na světě).
- `result(state)` je vždy `null` (modul nekončí), `aiAction` neexistuje (žádný soupeř).

## Události (háčky pro další feature)
Klient po každé úspěšné akci porovná stav před a po a ohlásí:
- `stolen {car, x, y}` – `board` s `owner = "npc"`; čte ho policie (7.4: hledanost 1, když to
  vidí hlídka) a ukládá se jako příznak `stolen` ve stavu.
- `ownerQuip {car, x, y}` – totéž přesednutí; feature dialogů na něj pustí hlášku majitele z poolu.
- `carChanged {car}` – po každém `board` a `select` (HUD, uložení).

## Přesedání (P2, svět)
- Hráč stojí: rychlost auta ≤ `cars.board_speed_mps`, vrstva 0.
- Kandidát je zaparkované auto, jehož střed je od středu hráčova auta nejvýš `cars.board_distance_m`;
  z více kandidátů nejbližší. Pak HUD ukáže kontextové tlačítko „Přesednout“ (`boardCar`).
- Auto samo přidává plyn (controls A), takže hráč zastaví jen na chvíli (brzda, ruční brzda).
  Tlačítko proto zůstane `cars.action_hold_s` od posledního splnění podmínek, dokud je vybrané
  auto pořád do `board_distance_m` (rychlost se v té době nehlídá). Stejně tlačítko Garáž
  (do `garage_radius_m`).
- Stisk: hráčovo auto zůstane zaparkované na místě (zaparkované těleso, vlastník podle toho, jestli je
  v `owned` a hráč ho neukradl), vybrané zaparkované auto zmizí a na jeho místě vznikne nové
  dynamické těleso s parametry nového auta (rozměry × `car_scale`, hmotnost, grip, …). Rychlost 0.
- Zaparkovaná auta (v2) jsou dynamická tělesa v kategorii `CAT_PARKED` (hmotnost auta ×
  `cars.parked.mass_factor`, útlum `cars.parked.linear_damping`, `angular_damping`). Kolidují s hráčem
  jen ve vrstvě 0, s budovami, mezi sebou a s provozem, takže je hráč i provoz odtlačí. Po kroku fyziky
  se poloha a natočení probuzeného tělesa zapíšou zpět do zaparkovaného auta (kreslení, přesedání).

## Zaparkovaná auta (P2, generují se po chunku)
- Generují se při načtení chunku a zahodí s ním (jako mobiliář, plán 6.4). Generátor je sdílený
  PRNG: `Prng((cx · 73856093 XOR cy · 19349663 XOR cars.parked.salt) mod 2³²)`.
- Způsobilé úseky (v pořadí hran a bodů grafu): hrana `kept`, na zemi, ne most, `roadClass` v
  `cars.parked.classes`, střed úseku v chunku, délka úseku > 2·`cars.parked.segment_margin_m`.
- Až `cars.parked.attempts` pokusů, nejvýš `cars.parked.per_chunk` aut. Každý pokus vždy vytáhne
  čtyři čísla v tomto pořadí: úsek `nextInt(počet)`, místo `nextInt(1000)`, strana `nextInt(2)`
  (0 = vpravo po směru úseku, normála `(dy, −dx)/l`), model `nextInt(počet cars.parked.models)`. Bez způsobilého úseku
  se nic negeneruje.
- Místo podél úseku: `margin + (l − 2·margin) · místo / 1000`, `margin = segment_margin_m`.
  Střed auta je `width/2 − sidewalk_width_m − půlšířka − curb_gap_m` od osy hrany (když vnitřní bok
  auta, tj. offset − půlšířka, je blíž ose než `cars.parked.min_inner_m`, pokus se zahodí). Natočení: vpravo směr úseku, vlevo +π.
- Pokus se zahodí, když je střed blíž než `cars.parked.min_spacing_m` k jinému autu téhož chunku
  nebo k autu, které hráč odstavil, nebo blíž než `cars.parked.clear_player_m` k hráčovu autu.
- Auto, které hráč odstavil, se nezahazuje s chunkem; zmizí, až je dál než `cars.parked.forget_m`
  (vlastní auto zůstává ve vlastnictví a jde vybrat v garáži).
- Klienty F a W počítají stejně, ale shodu umístění nehlídají vektory (P2).

## Garáž
- Hráč je v garáži, když stojí (≤ `cars.garage_speed_mps`) nejvýš `cars.garage_radius_m` od
  parkovacího bodu spotu `garage`. HUD ukáže tlačítko „Garáž“ (`garage`).
- Seznam ukazuje vlastní auta (jméno, třída, vyznačené řízené). Výběr = akce `select`: nové auto
  vznikne na parkovacím bodě garáže natočené podle `park_heading`, řízené auto zajede do garáže
  (vlastní) nebo ho odveze odtahovka (cizí; nezůstane stát). Odstavené vlastní auto jinde ve městě
  zmizí (je teď v garáži / venku).
- Dokud je seznam garáže otevřený, svět stojí (jízda se nekrokuje).
- Nákup: pod vlastními auty seznam aut na prodej s cenou; koupit jde auta z `buyable` (`specs/economy.md` „Nákup auta“).

## Kreslení (P2)
Pohled shora, vektorové obdélníky v souřadnicích auta (x dopředu, y doleva, `hl`, `hw` = půldélka
a půlšířka po `car_scale`). Všechny třídy: stín, kola (přední se natáčí), karoserie (`paint`),
kabina, sklo (lak + 12 % bílé), světla vpředu i vzadu. Podle třídy:
- `coupe` – kabina −0,42…0,30 hl, pruhy přes kapotu a víko (stripe).
- `hatchback` – kabina −0,70…0,25 hl (krátká záď).
- `muscle` – kabina −0,50…0,10 hl, dva pruhy ±0,22 hw přes celé auto (`carDetail.muscleStripe`).
- `taxi` – kabina −0,45…0,30 hl, střešní cedule −0,15…0,05 hl × ±0,35 hw (`carDetail.taxiSign`),
  šachovnicový pruh na boku (`carDetail.taxiChecker`).
- `pickup` – kabina 0,05…0,45 hl, korba −0,95…−0,05 hl (`carDetail.bed`, lem `carDetail.bedRim`).
- Ostatní třídy jako `coupe` bez pruhů.
Zaparkovaná auta stejně, bez světlometů a kuželu. Sprity z ComfyUI (plán 10: maska, lak, kola)
přijdou později a nahradí jen kreslení; rozměry a kolize zůstávají z JSON.

## Hraniční případy
- Přesednout zpátky do vlastního odstaveného auta: `board` s `owner = "player"`, `stolen = false`.
- Ukradené auto se dá znovu opustit a vzít jiné cizí: každé převzetí zvedne `thefts`.
- Garáž, když hráč řídí vlastní auto a vybere to samé: nepovoleno (nic se neděje).
- Balíček bez spotu `garage`: tlačítko Garáž se neukáže, zbytek funguje.
- Respawn (tlačítko) nechává řízené auto a stav beze změny, jen přesune těleso.

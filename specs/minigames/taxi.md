# Taxi

**version: 1** · engine `drive` · pravidla P0 (vektory `vectors/taxi.json`), jízda P2 (skutečný svět) ·
kontrakt `specs/minigames/README.md` · plán: METROPOLE_PLAN 9.5 („směna 4 min, cestující jmenují
skutečné cíle; hvězdy podle prahů tržby“) · parita F-027 · navazuje na `specs/loop.md`,
`specs/phone.md` (navigace), `specs/route.md`, `specs/cars.md`, `specs/traffic.md`

## Účel

Světová minihra: na stanovišti taxi (`penn_taxi_stand`) hráč přesedne do žlutého taxíku
(`taxi_metro`) a jezdí 4minutovou směnu po skutečném městě. Cestující čekají u chodníku, jmenují
skutečný cíl (hero landmark balíčku města jeho skutečným jménem), navigace je tam dovede a za
každou jízdu je jízdné. Tržba za směnu = skóre, hvězdy podle prahů tržby.

Na rozdíl od ostatních miniher **neběží přes celou obrazovku** a svět se nepozastaví: jízda,
provoz, policie i chodci běží dál. Čistá pravidla počítají jen účetnictví směny (výběr cíle,
jízdné, spropitné, konec); kde je auto, rozhoduje svět a pravidlům posílá celá čísla v akcích.

## Config

`content/tuning.yaml` → `minigames.taxi`. Pravidla dostanou
`{dests, lines, fareBase, farePerKm, expectBaseS, expectDmPerS, bonusPerS, bonusMaxPct, latePerS,
lateMaxPct, tipPct, hitTipPct, starFares}`; `dests` = id cílů v pořadí balíčku (viz Svět), `lines` =
počet hlášek cestujících v `i18n/` (`taxiLine1..N`).

| klíč | význam | default |
|---|---|---|
| `shift_s` | délka směny (jen UI, pak `timeout`) | 240 |
| `fare_base` | nástupní sazba | 6 |
| `fare_per_km` | za km trasy | 20 |
| `expect_base_s`, `expect_dm_per_s` | očekávaný čas jízdy = základ + délka ÷ rychlost | 15, 70 |
| `bonus_per_s`, `bonus_max_pct` | bonus za každou ušetřenou sekundu, strop v % taxametru | 1, 30 |
| `late_per_s`, `late_max_pct` | srážka za každou sekundu navíc, strop v % taxametru | 1, 50 |
| `tip_pct`, `hit_tip_pct` | spropitné v % taxametru, srážka za každý náraz do auta | 20, 5 |
| `star_fares` | tržba pro 3★, 2★, 1★ | [180, 110, 45] |
| `lines` | počet hlášek `taxiLine1..N` | 6 |
| `pickup_min_m`, `pickup_max_m` | kde se objeví další cestující (vzdušně od auta) | 50.0, 180.0 |
| `pickup_radius_m` | zastavit u cestujícího do této vzdálenosti | 10.0 |
| `drop_radius_m` | zastavit v cíli do této vzdálenosti od bodu zastavení | 20.0 |
| `stop_speed_mps` | „stojí“ | 1.5 |
| `dest_min_m`, `dest_max_m` | povolené cíle (vzdušně od místa nástupu) | 400.0, 1800.0 |
| `dest_search_m` | cíl bez silnice do této vzdálenosti se nepoužije | 120.0 |
| `renav_s` | zrušenou navigaci obnoví po | 3.0 |
| `line_s` | jak dlouho visí hláška cestujícího | 4.0 |
| `low_s` | časovač směny zčervená pod (jen UI) | 30.0 |
| `passenger_m`, `passenger_px` | poloměr značky cestujícího (m, nejméně px) | 2.0, 6.0 |
| `curb_m` | cestující stojí tolik za okrajem koridoru silnice | 1.0 |

## Stav

```
{
  rng: int,            // uint32 PRNG (specs/prng.md)
  phase: "wait" | "ride" | "over",
  clockMs: int,        // čas směny poslední akce s časem
  fare: int,           // tržba směny
  rides: int,          // dokončené jízdy
  dest: string,        // cíl cestujícího ve voze ("" bez cestujícího)
  line: int,           // index hlášky cestujícího (0 … lines−1, −1 bez cestujícího)
  pickMs: int,         // čas nástupu
  hits: int,           // nárazy během aktuální jízdy
  lastDest: string,    // cíl předchozí jízdy ("" na začátku)
  last: {dest, distDm, rideS, expectS, meter, time, tip, fare}   // rozpis poslední jízdy
}
```

`last` po `init` má řetězec `""` a všude jinde 0.

## Akce

- `{"by": "player", "op": "pickup", "atMs": int, "allow": [string]}` – hráč zastavil u čekajícího
  cestujícího. `allow` = cíle, které svět povoluje (podmnožina `dests` v libovolném pořadí,
  prázdné = všechny).
- `{"by": "player", "op": "hit"}` – náraz do auta provozu s cestujícím ve voze (`onHit` provozu).
- `{"by": "player", "op": "dropoff", "atMs": int, "distDm": int}` – hráč zastavil v cíli;
  `distDm` = délka trasy z místa nástupu do cíle v dm (`specs/route.md`, součet délek hran trasy),
  spočítaná při nástupu.
- `{"by": "timeout"}` – konec směny (UI po `shift_s` času jízdy).

## Pravidla

`÷` je celočíselné dělení nezáporných čísel (dolů).

### init(config, seed)

`rng = Prng(seed).state`, `phase = "wait"`, `clockMs = 0`, `fare = rides = pickMs = hits = 0`,
`dest = lastDest = ""`, `line = −1`, `last` prázdné.

### apply – pickup

Legální jen ve `wait`, `atMs` celé číslo ≥ `clockMs`, `allow` pole řetězců, každý z `dests`.

1. `pool` = `dests` v pořadí configu, jen ty z `allow` (prázdné `allow` = všechny).
2. Má-li `pool` víc než jeden prvek, vyřadí se z něj `lastDest`.
3. `dest = pool[rng.nextInt(len(pool))]`, potom `line = rng.nextInt(lines)` (v tomto pořadí).
4. `phase = "ride"`, `pickMs = clockMs = atMs`, `hits = 0`.

### apply – hit

Legální jen v `ride`: `hits += 1`.

### apply – dropoff

Legální jen v `ride`, `atMs` celé číslo ≥ `pickMs`, `distDm` celé číslo ≥ 0.

```
rideS   = (atMs − pickMs) ÷ 1000
expectS = expectBaseS + distDm ÷ expectDmPerS
meter   = fareBase + distDm × farePerKm ÷ 10000
diff    = expectS − rideS
time    = diff ≥ 0 ?  min(diff × bonusPerS, meter × bonusMaxPct ÷ 100)
                   : −min((−diff) × latePerS, meter × lateMaxPct ÷ 100)
tip     = meter × max(0, tipPct − hits × hitTipPct) ÷ 100
fare    = meter + time + tip
```

`fare += fare jízdy`, `rides += 1`, `lastDest = dest`, `dest = ""`, `line = −1`, `hits = 0`,
`clockMs = atMs`, `phase = "wait"`, `last = {dest, distDm, rideS, expectS, meter, time, tip, fare}`.

### apply – timeout

Legální ve `wait` i `ride`: `phase = "over"`. Cestující ve voze (jízda nedokončená) nic nezaplatí.

### Ostatní

- `legalActions`: `wait` → `[{pickup, atMs: clockMs, allow: []}, {timeout}]`, `ride` → `[{hit},
  {timeout}]`, `over` → `[]` (dropoff závisí na světě, nevyjmenovává se).
- `aiAction`: hra nemá soupeře (volání je chyba).
- Jiné `by`, neznámé `op`, akce ve `over` → `IllegalAction`.

## Hvězdy a výsledek

`result` je `null` mimo `over`. Pak `{winner, stars, score, rides}`: `score = fare`,
`stars` = 3 při `fare ≥ starFares[0]`, 2 při `≥ starFares[1]`, 1 při `≥ starFares[2]`, jinak 0;
`winner = "player"` při `stars ≥ 1`, jinak `"draw"`. Hotovost pak spočítá smyčka (`specs/loop.md`,
`specs/economy.md`, engine `drive`).

## Svět (P2, oba klienti stejně)

- **Cíle** = landmarky balíčku s `hero`, v pořadí `landmarks.pb`, které mají udržovanou silnici
  (`kept`) do `dest_search_m`; bod zastavení = průmět landmarku na tu hranu. Jméno cíle = `name`
  landmarku (skutečné jméno, žádné značky – R10 hlídá balíček).
- **Start:** smyčka (`specs/loop.md`) u spotu s minihrou engine `drive` místo toastu spustí směnu.
  Svět se nepozastaví, telefon se zavře, rozpracovaná navigace se zruší. Hráčovo auto se odloží a
  hráč řídí `taxi_metro` na stejném místě (dočasně: vlastnictví aut se nemění, uloží se původní
  auto). Po konci směny dostane hráč původní auto zpět na místě, kde taxík stojí. Když hráč
  během směny sám přesedne nebo vyjede z garáže, směna skončí (timeout) a auto se nevrací.
- **Čas směny** běží s časem jízdy (`dt` světa, tedy zpomalený při otevřeném telefonu); po
  `shift_s` pošle UI `timeout`. Čas v akcích = celé ms od začátku směny (`floor`).
- **Cestující:** ve `wait` se objeví na nejbližší udržované přízemní hraně (vrstva 0) v bodě
  `pickup_min_m … pickup_max_m` od auta (svět zkouší směry od směru jízdy po 45°, první vyhovující),
  na chodníku vpravo od směru hrany (odsazení polovina šířky koridoru + `curb_m`, 1.0); navigace (tichá, bez
  `arrived` smyčky) vede na bod silnice. Hráč zastaví (`stop_speed_mps`, vrstva 0) do
  `pickup_radius_m` + poloviny šířky koridoru od cestujícího → `pickup` s `allow` = cíle `dest_min_m … dest_max_m` vzdušně od auta.
- **Hláška:** po nástupu cestující řekne `taxiLine<line+1>` se jménem cíle (`{place}`) na
  `line_s` s; volitelně jako bublina NPC.
- **Jízda:** navigace do bodu zastavení cíle (stejná trasa a pilulka jako `specs/phone.md`),
  `distDm` = délka trasy z místa nástupu (`feedDistDm` bez vzdušné náhrady; bez trasy vzdušná
  vzdálenost × `feed.straight_pct` ÷ 100). Každý `onHit` provozu s cestujícím ve voze → `hit`.
  Zastavení do `drop_radius_m` od bodu zastavení cíle → `dropoff`, toast s jízdným
  (`taxiPaid`). Pak hned další cestující.
- Zrušená navigace (✕ na pilulce) se po `renav_s` obnoví, když je auto dál než `drop_radius_m` od cíle navigace.
- **HUD:** zbývající čas směny (`taxiTime`), tržba (`taxiFare`), pilulka navigace s cílem
  (`taxiPickup` k cestujícímu, `routeTo` do cíle), tlačítko ukončit směnu (= vzdát).
  Barvy `color.taxi.*`.
- **Konec:** `timeout` → výsledek → normální výsledek smyčky (`specs/loop.md`): `MinigameResult`
  s `stars`, `score = fare`, `playedMs` = čas směny. Vzdaná směna = `aborted`, 0★.
- „Hrát“ u spotů, `arrived` u spotů a nákupní tlačítka smyčky během směny nespouští jiné minihry.

## Galerie a ladění

Taxi potřebuje svět: Galerie ukáže řádek Taxi jako dostupný s poznámkou „začíná ve městě“
(`taxiGallery`) a tlačítkem, které otevře svět u stanoviště a hned spustí směnu
(W: `?mg=taxi` otevře svět na spotu s minihrou `taxi` a hned spustí směnu, jako
`?spot=…&play=…`; F: karta v Galerii zavře Galerii, přenese auto na stanoviště a spustí směnu).

## Hraniční případy

- `allow` prázdné (žádný cíl v rozmezí) → vybírá se ze všech cílů.
- Jediný cíl v `pool` → může se opakovat i `lastDest`.
- Konec směny s cestujícím ve voze → jízda se nezaplatí.
- Výrazně pomalá jízda → srážka nejvýš `late_max_pct` taxametru, jízdné nikdy záporné.
- Město bez cílů → směna jde, ale cestující se neobjeví (0★).

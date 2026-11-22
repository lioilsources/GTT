# Zvonící budky (M2-S2)

**version: 1** · P0 pravidla zvonění (`vectors/booths.json`) · P1 budky ve světě, zvednutí,
nabídka · METROPOLE_PLAN 4 („Zvonící budky“), M2 bod 2 · parita F-037

## Účel
Telefonní budka u cesty občas zvoní. Kdo u ní zastaví a zvedne, dostane náhodný motiv (minihru na
spotu ve městě) s bonusovou hotovostí za dohrání. Svět tak hráče sám zve, i když nemá otevřený
Feed. Čísla jsou v `content/tuning.yaml` → `booths`, texty v `i18n/` (`booth*`), barvy v
`design/tokens.json` → `color.booth`. Vypíná se `booths.enabled`.

## Budky v balíčku
Budka = spot `kind: booth` v `content/cities/<city>/spots.yaml` (bez `minigame`), přichycený na
silnici jako každý spot (parkovací bod, `specs/citypack.md`). Pořadí budek = pořadí ve `spots.pb`;
index budky `b` je pořadí mezi spoty `kind = booth`. Město bez budek = modul se nespouští.

## Stav (P0, modul `booths`)
Pravidla běží v celých sekundách hry (tik = 1 s; klient tikne jednou za sekundu pevného kroku,
pauza hodiny zastaví, `specs/pause.md`).
```
config: {booths, gapMin, gapMax, retry, ringS, bonus, games: [spotId]}
state:  {ringing, left, next, answered, missed, offer: {spot, bonus}, paid, last, rng}
```
- `booths` – počet budek. `games` – id spotů s minihrou v katalogu (pořadí spotů, jako kandidáti
  feedu, `specs/feed.md`), z nich se losuje motiv. Prázdné `games` = budky nezvoní.
- `ringing` – index zvonící budky, −1 = ticho. `left` – zbývající sekundy zvonění.
- `next` – sekundy do dalšího pokusu o zvonění. `answered`, `missed` – počty zvednutých a
  nezvednutých zvonění.
- `offer` – motiv posledního zvednutí: `spot` (`""` = žádný) a `bonus` (hotovost).
- `paid` – součet vyplacených bonusů, `last` – bonus poslední akce `finish` (0 jinak).
- `rng` – stav PRNG (`specs/prng.md`).
- `init(config, seed)`: `rng = Prng(seed)`, `ringing = −1`, `left = 0`, `answered = missed = 0`,
  `offer = {spot: "", bonus: 0}`, `paid = last = 0`, `next = gap()`, kde
  `gap() = gapMin + rng.nextInt(gapMax − gapMin + 1)`.

## Akce
Všechny `by: "player"`:
- `{op: "tick", near: [b]}` – jedna sekunda; `near` = indexy budek, na které teď smí zazvonit
  (vzestupně, bez duplicit, každý `0 ≤ b < booths`; viz Dosah).
- `{op: "answer", booth}` – hráč zvedl budku `booth`.
- `{op: "finish", spot, stars, aborted}` – skončila smyčka na spotu `spot` (`specs/loop.md`).
- `{op: "clear"}` – motiv se zahodil (`offer = {spot: "", bonus: 0}`).

## Pravidla
`tick(near)`:
1. Když `ringing ≥ 0`: `left −= 1`; při `left = 0`: `ringing = −1`, `missed += 1`, `next = gap()`.
   Konec tiku.
2. `next −= 1`. Když `next > 0`: konec tiku.
3. Když `near` je prázdné nebo `games` je prázdné: `next = retry`. Konec tiku.
4. Jinak `ringing = near[rng.nextInt(len(near))]`, `left = ringS`.

`answer(booth)`: nelegální, když `booth ≠ ringing` nebo `ringing = −1`. Jinak
`offer = {spot: games[rng.nextInt(len(games))], bonus}`, `ringing = −1`, `left = 0`,
`answered += 1`, `next = gap()`.

`finish(spot, stars, aborted)`: `last = 0`. Když `offer.spot ≠ ""` a `spot = offer.spot`: je-li
`stars ≥ 1` a ne `aborted`, pak `last = offer.bonus`, `paid += last`; v každém případě
`offer = {spot: "", bonus: 0}`. Jiný spot motiv nemění. Nelegální: `stars` mimo 0–3,
`aborted` ne bool, `spot` ne řetězec.

Každá jiná akce než `finish` nastaví `last = 0`.

`clear`: `offer = {spot: "", bonus: 0}` (vždy legální).

Nelegální: neznámé `op`, `by ≠ "player"`, `near` s indexem mimo rozsah, neseřazené nebo
s duplicitou. `legalActions(state)`: `clear`, `tick` s `near = []`, a když `ringing ≥ 0`, ještě
`answer` se zvonící budkou. `result` je vždy `null`, `aiAction` neexistuje.

## Hotovost
Bonus spočítá `finish` (`last`). Klient ho připíše k hotovosti stejně jako odměnu ekonomiky
(`specs/economy.md`: `cash` ze stavu aut, `cash += last`, zpět do stavu aut) hned po akci
`reward` téže smyčky; ekonomika se nemění.

## Ve světě (P1)
- **Dosah:** budka `b` je v `near`, když je hráčův střed od jejího parkovacího bodu ve vzdálenosti
  `ring_min_m ≤ d ≤ ring_max_m` (blízko, ale ne hned vedle). Během navigace (přijatá karta),
  minihry, Taxi a s hledaností > 0 je `near` prázdné (budka nezvoní, zvonící dozvoní).
- **Zvednutí:** u zvonící budky stejné podmínky jako „Hrát“ u spotu (`specs/loop.md`): rychlost
  ≤ `loop.stop_speed_mps`, vrstva 0, parkovací bod do `loop.spot_radius_m`. HUD ukáže kontextové
  tlačítko „Zvednout“ (`boothAnswer`), přednost má před „Hrát“ i „Přesednout“.
- **Nabídka:** po `answer` karta přes svět (hra stojí, `specs/pause.md`): hostitel =
  `characters[fnv1a(boothId) mod počet postav]` (jako soupeř, `specs/loop.md`), text
  `boothCall` se jménem minihry, místem spotu a bonusem. Tlačítka „Jedu“ (`boothGo`) a „Nechat
  být“ (`boothSkip`). „Jedu“ = jako přijatá karta feedu: trasa na spot (`specs/phone.md`),
  `driveDm` = délka trasy, obtížnost = `feed.difficulty_base`. „Nechat být“ = `clear`.
- **Bonus:** po každém výsledku smyčky (`specs/loop.md`, krok 2) klient pošle `finish` se spotem,
  hvězdami a `aborted`; nenulové `last` přičte k hotovosti a výsledková obrazovka ukáže řádek
  `loopBooth` (zahrnutý v `loopCash`). Přijetí jiné karty feedu nebo přepnutí města → `clear`.
- **Neukládá se:** stav budek žije jen v relaci (po startu `init` s náhodným seedem).
- **Kreslení:** budka shora jako obdélník `booth_w_m × booth_l_m` u parkovacího bodu, tělo
  `booth.body`, střecha `booth.roof`; zvonící budka pulzuje kruhem `booth.ring` (perioda
  `ring_pulse_s`) a na okraji obrazovky ukazuje šipka `booth.ring` (jako navigace). HUD při
  začátku zvonění toast `boothRinging`, na Mapě zvonící budka jako bod `booth.ring`.

## Hraniční případy
- Hráč stojí u budky, když začne zvonit: tlačítko se ukáže hned (Dosah je jen pro zvonění).
- Zvonění dozvoní během otevřené nabídky jiné budky: nemůže, nabídka hru zastaví.
- Motiv vede na spot, kde hráč právě stojí: „Jedu“ rovnou vyhlásí `arrived` (jako navigace).
- `booths.enabled = false` nebo město bez budek: žádné budky, žádný modul.

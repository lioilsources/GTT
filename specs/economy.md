# Ekonomika: odměna, odtah, pokuta

**version: 1** · P0 · vektory `vectors/economy.json` · plán: METROPOLE_PLAN 4 („Výsledek minihry“,
„Hotovost“, „Žádný fail state“), 7.4 (pokuta), M1 bod 11 · parita F-025

## Účel

Hotovost za výsledek smyčky (minihra po jízdě), poplatek za odtah rozbitého auta a pokuta od
policie. Oba klienti musí ze stejného výsledku spočítat **stejnou** částku, proto jsou pravidla
celočíselná a bez náhody. Čísla jsou v `content/tuning.yaml` pod `economy` (a jízdní část odměny
pod `feed`, aby karta feedu ukazovala stejné číslo, jaké hráč dostane za 3★).

Hotovost je jedno číslo (`Save.cash`). Za běhu ho drží stav modulu `cars` (`specs/cars.md`, kvůli
`buy`); klient před každou akcí ekonomiky vezme `cash` ze stavu aut, akci použije a nové `cash`
zapíše zpět. Nákup auta v garáži jde dál přes `cars` (`buy`, cena = `price` auta).

## Stav

```
{
  cash: int,         // ≥ 0
  earned: int,       // součet všech odměn za sezení
  paid: int,         // součet zaplacených poplatků a pokut
  last: {op, amount, base, trip, band, first}   // rozpis poslední akce (pro výsledkovou obrazovku)
}
```

`last` po `init` je `{op: "", amount: 0, base: 0, trip: 0, band: 0, first: 0}`. U `tow` a `fine` je
`amount` zaplacená částka a ostatní části jsou 0.

## Config

```
{cash, base, enginePct: {engine: int}, starPct: [4 int], scoreBands: [int…], bandBonus: [int…],
 firstBonus, firstMinStars, rewardBase, rewardPerMin, driveDmPerS, towFee}
```

- `cash` – hotovost na začátku (ze stavu aut).
- `base`, `enginePct`, `starPct`, `scoreBands`, `bandBonus`, `firstBonus`, `firstMinStars`, `towFee`
  z `economy.*` (camelCase). `enginePct` chybějícího enginu = 100.
- `rewardBase`, `rewardPerMin`, `driveDmPerS` z `feed.*` (stejný vzorec jako `reward` karty feedu).
- `scoreBands` vzestupně; `bandBonus` má o jeden prvek víc než `scoreBands`.

## Akce

Všechny `{"by": "player", "op": …}`:

- `{op: "reward", engine, stars, score, first, driveDm, aborted}` – výsledek smyčky. `engine`
  z katalogu miniher, `stars` 0–3, `score` celé číslo, `first` = hráč tuhle minihru ještě nikdy
  nedohrál s aspoň 1★ (v uložení nemá `best` nebo má `best.stars = 0`), `driveDm` = `distDm`
  přijaté karty feedu, která vedla na tenhle spot (0 = bez karty), `aborted` = hráč hru vzdal.
- `{op: "tow"}` – odtah rozbitého auta (systém poškození zatím není; klient volá jen háček).
- `{op: "fine", amount}` – pokuta od policie (`amount ≥ 0`, posílá policejní feature).

## Pravidla

`÷` je celočíselné dělení nezáporných čísel (dolů).

### init(config, seed)

`cash = config.cash`, `earned = 0`, `paid = 0`, `last` prázdné. `seed` se nepoužívá.

### apply – reward

1. Když `aborted` nebo `stars = 0`: všechny části 0, `amount = 0` (hotovost beze změny).
2. Jinak:
   - `base = (config.base × enginePct[engine] ÷ 100) × starPct[stars] ÷ 100`
   - `trip = driveDm > 0 ? (rewardBase + (driveDm ÷ driveDmPerS) × rewardPerMin ÷ 60) × starPct[stars] ÷ 100 : 0`
     (při 3★ a `starPct[3] = 100` přesně `reward` karty feedu)
   - `band = bandBonus[k]`, kde `k` = počet prahů `scoreBands` ≤ `score`
   - `first = (first a stars ≥ firstMinStars) ? firstBonus : 0`
   - `amount = base + trip + band + first`
3. `cash += amount`, `earned += amount`, `last = {op: "reward", amount, base, trip, band, first}`.

Nelegální: `stars` mimo 0–3, `score`, `driveDm` nebo `engine` špatného typu, `driveDm < 0`,
`first`/`aborted` ne bool.

### apply – tow, fine

- `tow`: `fee = min(cash, towFee)`.
- `fine`: `amount` musí být celé číslo ≥ 0 (jinak nelegální); `fee = min(cash, amount)`.
- `cash −= fee`, `paid += fee`, `last = {op, amount: fee, base: 0, trip: 0, band: 0, first: 0}`.
  Hotovost nikdy neklesne pod 0 (žádný dluh, žádný fail state).

### Ostatní

- `legalActions(state)`: `[{op: "tow"}]` (odměna a pokuta závisí na světě, nevyjmenovávají se).
- `aiAction`: modul nemá soupeře (volání je chyba).
- `result(state)`: vždy `null` (modul nekončí).
- Neznámé `op` nebo `by ≠ "player"` → `IllegalAction`.

## Nákup auta (garáž)

Garáž (`specs/cars.md`) ukáže pod vlastními auty i auta na prodej: každé auto katalogu, které hráč
nemá, se jménem a cenou; tlačítko „Koupit“ je aktivní jen pro auta z `buyable` (dost hotovosti).
Koupě = akce `cars` `buy`; koupené auto se přidá do vlastních (vyjet s ním jde hned v tomtéž
seznamu). Po koupi se uloží (`specs/save.md`).

## Hraniční případy

- 0★ nebo vzdaná hra → 0 hotovosti, ale výsledková obrazovka se ukáže.
- Spot bez přijaté karty (hráč zastavil sám) → `trip = 0`.
- Odtah nebo pokuta při `cash < poplatek` → zaplatí se jen to, co hráč má.
- Neznámý engine → `enginePct = 100`.

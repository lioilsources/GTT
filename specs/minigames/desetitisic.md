# Desetitisíc

**version: 1** · engine `dice` · P0 · vektory `vectors/desetitisic.json` · kontrakt `specs/minigames/README.md`

## Účel

České kostky se šesti kostkami (METROPOLE_PLAN 9.5) proti NPC, o body (R11). Hraje se do 5000,
nejvýš 10 kol.

## Config

`content/tuning.yaml` → `minigames.desetitisic`; ve vektoru
`{target, maxRounds, aiBankAt, aiErrorPct, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `target` | kdo uloží celkem aspoň tolik, vyhrál | 5000 |
| `max_rounds` | nejvýš kol (kolo = tah hráče + tah AI) | 10 |
| `ai_bank_at` | AI ukládá od tohoto zisku v tahu, úroveň 1–5 | [250, 300, 350, 400, 450] |
| `ai_error_pct` | šance, že AI odloží náhodný legální výběr | [40, 25, 10, 5, 0] |
| `star_margins` | náskok pro 3★ a 2★ | [1500, 500] |

## Bodování výběru

Výběr = multimnožina hodnot odložených kostek. Platný je, když jde **celý** rozložit na:

- postupka 1–6 (všech šest kostek) = 1500,
- trojice stejných hodnot `v` = 100 × v, trojice jedniček = 1000 (víc trojic jde sečíst),
- jednotlivá 1 = 100, jednotlivá 5 = 50.

Hodnota výběru = nejvyšší součet ze všech platných rozkladů. Kostka mimo kombinaci výběr zneplatní.

## Stav

```
{ player, ai, turn, phase, roll, dice, turnScore, round, lastBust, over, rng }
```

`player`, `ai` uložené body; `phase`: `"roll"` | `"keep"` | `"decide"` | `"over"`; `roll` hodnoty
posledního hodu (prázdné, dokud se nehodí); `dice` kolik kostek se hodí příště (1–6);
`turnScore` zisk v rozehraném tahu; `round` od 1; `lastBust`: poslední tah skončil bez bodu.

## Akce

`{"by": strana, "op": "roll"}`, `{"by": strana, "op": "keep", "dice": [indexy do roll, vzestupně]}`,
`{"by": strana, "op": "bank"}`, `{"by": "timeout"}`.

## Pravidla

- `init`: 0:0, `turn = "player"`, `phase = "roll"`, `dice = 6`, `round = 1`, `rng = Prng(seed).state`.
- `roll` (fáze `roll` nebo `decide`): `roll = [nextInt(6) + 1 pro každou z dice kostek]`.
  Nemá-li hod žádný platný výběr → **ztráta**: `turnScore = 0`, `lastBust = true`, konec tahu.
  Jinak `phase = "keep"`, `lastBust = false`.
- `keep` (fáze `keep`): indexy tvoří platný výběr; `turnScore += hodnota`, `dice −= počet`;
  `dice == 0` → `dice = 6` (všechny kostky bodovaly, hází se znovu se všemi). `phase = "decide"`.
- `bank` (fáze `decide`): připiš `turnScore` straně na tahu, konec tahu.
- **Konec tahu:** `turnScore = 0`, `dice = 6`, `roll = []`, `phase = "roll"`, tah přejde.
  Když tah končí AI, `round += 1`. Konec hry, když strana uložením dosáhne `target`, nebo když
  po tahu AI je `round > maxRounds`: `over = true`, `phase = "over"`.
- `timeout`: `over = true`, `phase = "over"`.

**`legalActions`:** `roll`: `[roll]`; `keep`: všechny platné výběry jako vzestupné seznamy indexů,
seřazené podle bitové masky (`Σ 2^i`) vzestupně; `decide`: `[roll, bank]`; `over`: prázdné.

## AI

`level` 1–5, `err = aiErrorPct[level−1]`, `bankAt = aiBankAt[level−1]`.

- fáze `roll`: `roll`.
- fáze `keep`: `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len)]`. Jinak výběr s nejvyšší
  hodnotou; při shodě ten s méně kostkami; pak první v pořadí `legalActions`.
- fáze `decide`: `bank`, když `turnScore ≥ bankAt`, nebo `dice ≤ 2` a `turnScore ≥ 200`, nebo by
  uložení dosáhlo `target`; jinak `roll`. Při `dice == 6` (všechny bodovaly) vždy `roll`, pokud
  uložení nedosáhne `target`.

## Výsledek a hvězdy

`{winner, stars, score, player, ai}`; `winner` podle vyšších bodů, shoda `"draw"`.
Hráč vyhrál s náskokem `≥ starMargins[0]` → 3★, `≥ starMargins[1]` → 2★, jinak 1★; jinak 0★.
`score = player`.

## Časový strop

7 min (`minigames.desetitisic.time_cap_s`).

## Hraniční případy

- 1-1-1-1 = trojice (1000) + jednička (100) = 1100; 2-2-2-2-2-2 = dvě trojice = 400.
- Postupka i dvě trojice jsou jen při šesti kostkách.
- Hod 2-3-4-6-6 je ztráta.

## Upřesnění v1 (podle implementace, vektory je pokrývají)

- Konec tahu se provede celý (předání tahu, u AI `round += 1`) a teprve potom se nastaví `over`;
  konečný stav tak může mít `turn` druhé strany a `round = maxRounds + 1`.
- Ztráta nastaví `roll = []`; UI si propadlý hod dopočítá ze stavu před akcí.
- Fáze `decide` u AI v tomto pořadí: uložení dosáhne `target` → `bank`; `dice == 6` → `roll`;
  `turnScore ≥ bankAt` nebo (`dice ≤ 2` a `turnScore ≥ 200`) → `bank`; jinak `roll`.
  Proud `ai` se volá jen ve fázi `keep`.
- Prázdný výběr je nelegální; indexy musí být ostře vzestupné. Hvězdy: náskok `≥` prahu.

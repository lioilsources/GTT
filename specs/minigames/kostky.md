# Kostkový poker

**version: 1** · engine `dice` · P0 · vektory `vectors/kostky.json` · kontrakt `specs/minigames/README.md`

## Účel

Pět kostek a tabulka kombinací (M2 bod 9, dávka B; METROPOLE_PLAN 9.5 č. 20) proti NPC, o body
(R11). Každý tah až tři hody, pak se zapíše jedna kolonka; po 13 kolech vyhrává vyšší součet.

## Config

`content/tuning.yaml` → `minigames.kostky`; ve vektoru `{bonusAt, bonus, aiErrorPct, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `bonus_at` | součet horních kolonek pro bonus | 63 |
| `bonus` | bonus za horní kolonky | 35 |
| `ai_error_pct` | šance náhodné akce AI, úroveň 1–5 | [40, 25, 12, 5, 0] |
| `star_margins` | náskok pro 3★ a 2★ | [60, 20] |
| `time_cap_s` | časový strop (UI) | 480 |
| `ai_think_s` | pauza před akcí AI (jen UI) | 0.7 |

## Kolonky

Index, název, hodnota pro kostky `d` (`n[v]` = počet kostek s hodnotou `v`, `sum` = součet):

| # | kolonka | hodnota |
|---|---|---|
| 0–5 | jedničky … šestky | `(i + 1) × n[i + 1]` |
| 6 | trojice | `sum`, když nějaké `n[v] ≥ 3`, jinak 0 |
| 7 | čtveřice | `sum`, když nějaké `n[v] ≥ 4`, jinak 0 |
| 8 | full | 25, když počty nenulových hodnot jsou přesně {3, 2}, jinak 0 |
| 9 | malá postupka | 30, když `d` obsahuje 1-2-3-4, 2-3-4-5 nebo 3-4-5-6, jinak 0 |
| 10 | velká postupka | 40, když `d` obsahuje 1-2-3-4-5 nebo 2-3-4-5-6, jinak 0 |
| 11 | poker | 50, když `n[v] = 5`, jinak 0 |
| 12 | šance | `sum` |

**Celkem** strany = součet zapsaných kolonek + `bonus`, je-li součet kolonek 0–5 `≥ bonusAt`.

## Stav

```
{ player, ai, turn, round, dice, rolls, over, rng }
```

- `player`, `ai`: 13 kolonek, `−1` = nezapsaná.
- `turn`: `"player"` | `"ai"`; `round` od 1, +1 po tahu AI (po posledním zápisu 14).
- `dice`: 5 hodnot posledního hodu (`[]` před prvním hodem tahu); `rolls`: hodů v tahu (0–3).

## Akce

- `{"by": strana, "op": "roll", "keep": [indexy vzestupně]}` – hod; kostky na indexech `keep`
  zůstanou, ostatní se hodí znovu (vzestupně podle indexu, každá `rng.nextInt(6) + 1`). V prvním
  hodu tahu je `keep = []` a hází se všech 5.
- `{"by": strana, "op": "score", "cat": i}` – zápis do nezapsané kolonky `i` (i za 0 bodů).
- `{"by": "timeout"}`.

**`legalActions`:** `rolls = 0` → `[roll []]`. `rolls` 1–2 → `roll` pro každou masku
`m = 0 … 30` (keep = indexy s bitem v `m`, vzestupně; maska 31 = držet vše chybí), pak `score`
pro každou nezapsanou kolonku vzestupně. `rolls = 3` → jen `score`.

## Pravidla

- `init`: obě tabulky `−1`, `turn = "player"`, `round = 1`, `dice = []`, `rolls = 0`,
  `rng = Prng(seed).state`.
- `roll`: `rolls += 1`, nové hodnoty viz výše.
- `score`: kolonka = hodnota pro `dice`; `dice = []`, `rolls = 0`, tah přejde; po tahu AI
  `round += 1`. Má-li AI zapsaných všech 13 kolonek, `over = true`.
- `timeout`: `over = true`.

## AI

`err = aiErrorPct[level−1]`; `r = ai.nextInt(100)` u **každé** akce AI (i při jediné legální).
`r < err` → `legal[ai.nextInt(len)]`. Jinak (`t` = tabulka AI, „volná“ = nezapsaná):

1. `rolls = 0` → `roll []`; `rolls = 3` → zápis (krok 3).
2. `rolls` 1–2: zapiš hned (krok 3), když platí první z: poker volný a `n[v] = 5`; velká postupka
   volná a hodnota > 0; full volný a hodnota > 0; malá postupka volná, velká zapsaná a hodnota
   > 0 (kolonku pak vybere krok 3). Jinak `roll` s `keep` podle:
   - `f` = nejčastější hodnota (shoda → vyšší), `c = n[f]`.
   - `c ≥ 3` → drž všechny kostky s `f`.
   - jinak úroveň ≥ 3, malá nebo velká postupka volná a nejdelší řada po sobě jdoucích různých
     hodnot v `dice` má délku ≥ 3 (shoda → řada s vyššími hodnotami) → drž z každé hodnoty řady jednu
     kostku (nejnižší index).
   - jinak `c = 2` → drž obě kostky s `f`.
   - jinak `keep = []`.
   Vyjde-li `keep` všech 5 kostek, zapiš (krok 3).
3. Zápis: kolonka s nejvyšší hodnotou `val` (shoda → nižší index):
   - hodnota `h > 0`: `val = 10 × h`; úroveň ≥ 3: kolonky 0–5 s `n[i + 1] ≥ 3` `+ 50`,
     šance `− 50`.
   - `h = 0`: `val = −pot[i]`, `pot = [5, 10, 15, 20, 25, 30, 30, 30, 25, 30, 40, 50, 30]`.

## Výsledek a hvězdy

`{winner, stars, score, player, ai}` (`player`, `ai` = celkem). Vyšší vyhrává, shoda
`"draw"`. Hráč vyhrál o `≥ starMargins[0]` → 3★, `≥ starMargins[1]` → 2★, jinak 1★; jinak 0★.
`score = player`.

## UI

Pět kostek nahoře, klepnutí přepne držení, tlačítko „Hodit“ (`kostkyRoll`, s počtem zbylých
hodů). Pod nimi tabulka obou stran; volné kolonky hráče ukazují náhled hodnoty a klepnutí
zapíše. Názvy kolonek `kostkyCat0` … `kostkyCat12`, bonus `kostkyBonus`.

## Hraniční případy

- Poker se počítá i jako trojice, čtveřice a šance; jako full ne.
- Zápis 0 je legální (škrt).
- Horní bonus se počítá do výsledku i po `timeout`.

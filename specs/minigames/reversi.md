# Reversi

**version: 1** · engine `board` · P0 · vektory `vectors/reversi.json` · kontrakt `specs/minigames/README.md`

## Účel

Reversi 8×8 proti NPC (M2 bod 9, dávka A): kámen musí sevřít soupeřovy kameny, ty se otočí.
Hráč (`x`, tmavý) začíná.

## Config

`content/tuning.yaml` → `minigames.reversi`; ve vektoru `{aiDepth, aiErrorPct, star3Margin}`.

| klíč | význam | default |
|---|---|---|
| `ai_depth` | hloubka negamaxu v půltazích | [1, 2, 3, 4, 5] |
| `ai_error_pct` | šance náhodného tahu | [35, 20, 10, 5, 0] |
| `star3_margin` | výhra o aspoň tolik kamenů = 3★ | 20 |
| `time_cap_s` | časový strop (UI) | 480 |

## Deska a stav

Pole `i = r × 8 + c`, řádek 0 nahoře. `board` řetězec 64 znaků `.`, `x` (hráč), `o` (AI). Start:
27 a 36 `o`, 28 a 35 `x`.

```
{ board, turn, plies, passes, over, winner, byCount, rng }
```

`passes` = po sobě jdoucí vynechání (0–2).

## Akce

`{"by": strana, "cell": i}` – položení kamene; `{"by": strana, "cell": −1}` – vynechání, legální
jen když strana nemá jiný tah. `{"by": "timeout"}`. `legalActions`: tahy vzestupně podle `cell`,
nebo jen vynechání.

## Pravidla

- Tah je legální, když v aspoň jednom z 8 směrů od `cell` vede souvislá řada soupeřových kamenů
  zakončená vlastním kamenem; všechny takové řady se otočí.
- Po tahu `plies += 1`, `passes = 0`; po vynechání `passes += 1`. Tah přejde.
- **Konec:** plná deska, nebo `passes = 2`, nebo strana na tahu nemá kámen. Víc kamenů vyhrává,
  shoda `"draw"`.
- `timeout`: rozhoduje počet kamenů, `byCount = true`.

## AI

`depth = aiDepth[level−1]`, `err = aiErrorPct[level−1]`.

1. `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len)]`.
2. Jinak negamax s alfa-beta do `depth` nad `legalActions` (vynechání je tah). Koncový uzel:
   `100000 × sign(vlastní − soupeřovy) + (vlastní − soupeřovy)`. List: součet vah polí
   (vlastní +, soupeřovy −) podle tabulky; řádky 4–7 zrcadlí 3–0, tabulka je symetrická:

   ```
   100 -20  10   5   5  10 -20 100
   -20 -50  -2  -2  -2  -2 -50 -20
    10  -2  -1  -1  -1  -1  -2  10
     5  -2  -1  -1  -1  -1  -2   5
   ```
   Shoda: první v pořadí.

## Výsledek a hvězdy

`{winner, stars, score, byCount, player, ai}` (`player`, `ai` = počty kamenů). Výhra: na
`timeout` → 1★; jinak `player − ai ≥ star3Margin` → 3★, jinak 2★. Remíza, prohra 0★.
`score = player × 10`.

## UI

Legální pole jako malé tečky; klepnutí = tah. Bez legálního tahu UI samo pošle vynechání s
krátkým toastem.

## Upřesnění v1

- Uzel negamaxu: nejdřív konec hry (plná deska, `passes ≥ 2`, strana na tahu bez kamene) →
  koncová hodnota; pak `depth = 0` → váhy polí; jinak synové (vynechání zvýší `passes`, tah ho vynuluje).
- `score = player × 10` pro každý výsledek.

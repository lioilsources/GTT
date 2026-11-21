# Sirky (duel)

**version: 1** · engine `puzzle` · P0 · vektory `vectors/sirky.json` · kontrakt `specs/minigames/README.md`

## Účel

Nejjednodušší minihra a referenční implementace kontraktu (METROPOLE_PLAN 9.5). Hráč a soupeř
střídavě berou 1–3 sirky z hromádky; kdo vezme poslední, prohrál kolo. Hraje se do 5 vyhraných kol.

## Config

Z `content/tuning.yaml` → `minigames.sirky`:

| klíč | význam | default |
|---|---|---|
| `start` | sirek v 1. kole | 15 |
| `min_start`, `max_start` | rozsah náhodného počtu v dalších kolech | 12, 25 |
| `max_take` | nejvýš sirek na tah | 3 |
| `rounds_to_win` | vyhraných kol na vítězství | 5 |
| `ai_error_pct` | pravděpodobnost chyby AI v % pro úroveň 1–5 | [60, 45, 30, 15, 0] |

Ve vektoru je config objekt `{start, minStart, maxStart, maxTake, roundsToWin, aiErrorPct}`.

## Stav

```
{ left, turn: "player"|"ai", starter: "player"|"ai", round, player, ai, over, rng }
```

`player`, `ai` = vyhraná kola; `round` od 1; `over` = konec hry.

## Akce

`{"by": "player"|"ai", "take": k}`, `1 ≤ k ≤ min(maxTake, left)`; `{"by": "timeout"}`.

## Pravidla

- `init`: `left = start`, `starter = turn = "player"`, `round = 1`, skóre 0:0, `over = false`, `rng = Prng(seed).state`.
- `legalActions`: prázdné, je-li `over`; jinak `take` 1…min(maxTake, left) za stranu na tahu, vzestupně.
- `apply(take)`: akce musí patřit straně na tahu a být legální, jinak chyba. `left -= k`.
  - `left > 0`: tah přejde na druhou stranu.
  - `left == 0`: kolo prohrál ten, kdo bral; druhá strana dostane bod.
    - Dosáhla-li `roundsToWin`: `over = true` (`turn` se nemění, PRNG se nevolá).
    - Jinak nové kolo: `round += 1`, `starter` se přepne, `turn = starter`,
      `left = minStart + nextInt(maxStart − minStart + 1)` z `rng`.
- `apply(timeout)`: `over = true`.

## AI

`level` 1–5, `err = aiErrorPct[level − 1]`, `m = min(maxTake, left)`:

1. `r = ai.nextInt(100)` (vždy, i když `err = 0`).
2. `r < err`: chyba, `take = 1 + ai.nextInt(m)`.
3. jinak optimum: `t = (left − 1) mod (maxTake + 1)`; `take = t`, je-li `t ≥ 1`, jinak `1`
   (prohraná pozice; bere minimum a čeká na chybu soupeře).

## Výsledek a hvězdy

`null`, dokud není `over`. Pak `{winner, stars, score, player, ai}`:

- `winner`: kdo má víc kol; při shodě (jen po `timeout`) `"ai"`.
- `stars`: hráč vyhrál a soupeř má ≤ 2 kola → 3; 3 kola → 2; 4 a víc → 1; hráč nevyhrál → 0.
- `score = 100 × player`.

## Časový strop

5 min (`minigames.sirky.time_cap_s`); po něm UI pošle `timeout` a rozhodne stav kol.

## Hraniční případy

- `left = 1` na tahu: jediný legální tah je vzít poslední sirku a prohrát kolo.
- Chybový tah AI může být i optimální; na výsledku to nic nemění, PRNG se spotřebuje stejně.
- Nelegální akce = chyba (výjimka), nikdy tichý tah.

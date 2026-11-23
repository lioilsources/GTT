# Posuvné puzzle

**version: 1** · engine `puzzle` · P0 · vektory `vectors/posuvne.json` · kontrakt `specs/minigames/README.md`

## Účel

Patnáctka 4×4 pro jednoho hráče (M2 bod 9, dávka A): posouváním dílků do prázdného pole
srovnat 1–15. Obtížnost = délka zamíchání. Soupeř není.

## Config

`content/tuning.yaml` → `minigames.posuvne`; ve vektoru `{shuffleMoves}`.

| klíč | význam | default |
|---|---|---|
| `shuffle_moves` | počet náhodných posunů při zamíchání pro úroveň 1–5 | [10, 20, 35, 60, 100] |
| `time_cap_s` | časový strop (UI) | 300 |

`level` = `MinigameContext.difficulty`; pravidla ho dostanou v configu jako `level` (vektor
`{shuffleMoves, level}`).

## Stav

```
{ tiles, moves, par, over, solved, rng }
```

`tiles` pole 16 čísel po řádcích shora, 0 = prázdné. Složeno = `[1..15, 0]`. `par` = počet
posunů zamíchání.

## Zamíchání (`init`)

`rng = Prng(seed)`, start ze složeného stavu, `last = −1`. `par = shuffleMoves[level−1]` krát:
sousedé prázdného pole (nahoru, dolů, vlevo, vpravo – v tomto pořadí, jen na desce) kromě pole
`last`; vybere se `sousedé[rng.nextInt(len)]`, dílek se přesune do prázdného pole a `last` = pole,
kde bylo prázdné. Je-li výsledek složený, provede se ještě jeden posun stejným postupem a
`par += 1`.

## Akce

`{"by": "player", "tile": n}` – dílek `n` sousedící s prázdným polem se do něj přesune.
`{"by": "timeout"}`. `legalActions`: dílky sousedící s prázdným polem, vzestupně podle `n`.
`aiAction` neexistuje.

## Pravidla

`moves += 1` po každém posunu. Složeno → `over`, `solved = true`. `timeout` → `over`, `solved = false`.

## Výsledek a hvězdy

`{winner, stars, score, moves, par}`. Složeno: `winner = "player"`; `moves ≤ par` → 3★,
`moves ≤ 2 × par` → 2★, jinak 1★; `score = max(100, 1000 − 10 × max(0, moves − par))`.
Nesloženo: `winner = "ai"`, 0★, `score = 0`.

## UI

Klepnutí na dílek v řadě nebo sloupci s prázdným polem přesune celou řadu dílků (UI pošle akce
jednotlivě od prázdného pole). Počítadlo tahů a „par“ nahoře.

## Upřesnění v1

- `level` se ořízne do 1…`len(shuffleMoves)`. Dodatečný posun při složeném výsledku je nejvýš jeden.

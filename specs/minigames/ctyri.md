# Čtyři v řadě

**version: 1** · engine `board` · P0 · vektory `vectors/ctyri.json` · kontrakt `specs/minigames/README.md`

## Účel

Svislá deska 7 sloupců × 6 řad proti NPC (M2 bod 9, dávka A): žetony padají dolů, kdo první
spojí čtyři (vodorovně, svisle, šikmo), vyhrává. Hráč (`x`) začíná.

## Config

`content/tuning.yaml` → `minigames.ctyri`; ve vektoru `{aiDepth, aiErrorPct, fastMoves}`.

| klíč | význam | default |
|---|---|---|
| `ai_depth` | hloubka negamaxu v půltazích pro úroveň 1–5 | [1, 2, 3, 5, 7] |
| `ai_error_pct` | šance náhodného tahu | [35, 20, 10, 5, 0] |
| `fast_moves` | výhra do tolika tahů hráče = 3★ | 12 |
| `time_cap_s` | časový strop (UI) | 300 |

## Deska a stav

Pole `i = r × 7 + c`, řádek 0 nahoře, 5 dole. `board` řetězec 42 znaků `.`, `x` (hráč), `o` (AI).

```
{ board, turn, moves, over, winner, rng }
```

Význam polí jako u `specs/minigames/piskvorky.md`.

## Akce

`{"by": strana, "col": c}` – žeton do sloupce `c`, dopadne na nejnižší prázdné pole.
`{"by": "timeout"}`. `legalActions`: sloupce s prázdným polem v řádku 0, vzestupně.

## Pravidla

- Po tahu hráče `moves += 1`. Čtyři a víc v řadě přes nový žeton → výhra táhnoucího. Jinak plná
  deska → `"draw"`. Jinak tah přejde. `timeout` → `"draw"`.

## AI

`depth = aiDepth[level−1]`, `err = aiErrorPct[level−1]`.

1. `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len(legal))]`.
2. Jinak negamax s alfa-beta do `depth` půltahů nad `legalActions` (pořadí sloupců vzestupně).
   Uzel, kde soupeř právě vyhrál: `−(100000 + zbývající hloubka)`; plná deska 0. List =
   hodnocení z pohledu strany na tahu přes všech 69 oken po 4 polích (vodorovná, svislá, obě
   šikmá): okno jen s vlastními žetony (`k` kusů, zbytek prázdný): `k = 3` → +50, `k = 2` → +5;
   jen se soupeřovými: `k = 3` → −60, `k = 2` → −5; plus +3 za každý vlastní žeton ve sloupci 3
   a −3 za soupeřův. Shoda: první tah v pořadí.

## Výsledek a hvězdy

`{winner, stars, score, moves}`. Výhra: `moves ≤ fastMoves` → 3★, jinak 2★. Remíza, prohra 0★.
`score = (42 − počet žetonů) × 20` při výhře, jinak 0.

## UI

Klepnutí kamkoli do sloupce = tah; žeton spadne s krátkou animací. Vítězná čtveřice zvýrazněná.

## Upřesnění v1

- Pořadí kontrol v uzlu negamaxu: soupeř právě vyhrál → `−(100000 + depth)`; plná deska → 0;
  `depth = 0` → hodnocení listu; jinak synové v pořadí sloupců. Kořen hledá s oknem `(α, +∞)`,
  nový nejlepší tah jen při ostře vyšší hodnotě.
- Okna se smíšenými žetony a okna s 1 kusem přispívají 0.

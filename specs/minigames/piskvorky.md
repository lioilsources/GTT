# Piškvorky

**version: 1** · engine `board` · P0 · vektory `vectors/piskvorky.json` · kontrakt `specs/minigames/README.md`

## Účel

Piškvorky na desce 15×15 proti NPC (M2 bod 9, dávka A). Kdo první postaví pět nebo víc svých
značek v řadě (vodorovně, svisle, šikmo), vyhrává. Hráč (`x`) začíná.

## Config

`content/tuning.yaml` → `minigames.piskvorky`; ve vektoru `{size, aiErrorPct, defensePct, fastMoves}`.

| klíč | význam | default |
|---|---|---|
| `size` | strana desky | 15 |
| `ai_error_pct` | šance náhodného tahu AI pro úroveň 1–5 | [40, 25, 12, 5, 0] |
| `defense_pct` | váha obrany (blokování hráče) v % pro úroveň 1–5 | [50, 70, 90, 100, 110] |
| `fast_moves` | výhra do tolika tahů hráče = 3★ | 15 |
| `time_cap_s` | časový strop (UI) | 480 |

## Deska a stav

Pole `i = r × size + c`, řádek `r` shora. `board` je řetězec `size²` znaků: `.` prázdné, `x` hráč,
`o` AI.

```
{ board, turn, moves, over, winner, rng }
```

`turn`: `"player"`|`"ai"`; `moves` = počet tahů hráče; `winner` `""` za hry, pak `"player"`|`"ai"`|`"draw"`.
`init`: prázdná deska, `turn = "player"`, `moves = 0`, `rng = Prng(seed)` (pravidla náhodu nepoužívají).

## Akce

`{"by": strana, "cell": i}` – značka na prázdné pole. `{"by": "timeout"}`.
`legalActions`: prázdná pole vzestupně podle `i` (za hry), jinak `[]`.

## Pravidla

- Po tahu hráče `moves += 1`. Řada = souvislá řada značek téže strany v jednom ze čtyř směrů
  (→, ↓, ↘, ↙) přes právě položené pole. Délka ≥ 5 → táhnoucí vyhrává (`over`, `winner`).
- Jinak plná deska → `"draw"`. Jinak tah přejde.
- `timeout` → `"draw"`.

## AI

`level` 1–5: `err = aiErrorPct[level−1]`, `def = defensePct[level−1]`.

**Kandidáti:** prázdná pole, která mají v Čebyševově vzdálenosti ≤ 2 nějakou značku, vzestupně
podle `i`. Prázdná deska: jen středové pole `(size div 2) × size + size div 2`.

1. `r = ai.nextInt(100)`; `r < err` → `kandidáti[ai.nextInt(len)]`.
2. Jinak skóre kandidáta `p = útok(p, o) + útok(p, x) × def ÷ 100` a vybere se nejvyšší (shoda:
   první v pořadí). `útok(p, s)`: součet přes 4 směry hodnoty řady, kterou by vytvořila značka `s`
   položená na `p`: `L` = délka souvislé řady `s` přes `p` v tom směru (včetně `p`), `E` = počet
   otevřených konců (pole hned za koncem řady je na desce a prázdné, 0–2).

   | L | E = 2 | E = 1 | E = 0 |
   |---|---|---|---|
   | ≥ 5 | 100000 | 100000 | 100000 |
   | 4 | 10000 | 1000 | 0 |
   | 3 | 1000 | 100 | 0 |
   | 2 | 100 | 10 | 0 |
   | 1 | 10 | 1 | 0 |

   `÷` je celočíselné dělení.

## Výsledek a hvězdy

`{winner, stars, score, moves}`. Výhra: `moves ≤ fastMoves` → 3★, jinak 2★. Remíza a prohra 0★.
`score = (size² − počet značek na desce) × 10` při výhře, jinak 0.

## UI

Deska se vejde na šířku (15 polí ≈ 24 px na 360 px displeji); klepnutí vybere pole, druhé klepnutí
na stejné pole potvrdí (velké prsty). Poslední tah AI zvýrazněný, vítězná řada podtržená.

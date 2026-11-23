# Bouchni krtka

**version: 1** · engine `arcade` · P0 · vektory `vectors/krtek.json` · kontrakt
`specs/minigames/README.md`

## Účel

Pouťová klasika (whack-a-mole; M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 36): z devíti děr
vylézají krtci, hráč je klepnutím praští. Zlatý krtek dá víc, bomba bere body. Minuta hry, sám
na skóre. Simulace v celých tikách (60 za sekundu).

## Config

`content/tuning.yaml` → `minigames.krtek`; ve vektoru
`{level, holes, gameTicks, firstSpawn, spawnEvery, upTicks, goldPct, bombPct, points, goldPoints, bombPenalty, starScores}`.

| klíč | význam | default |
|---|---|---|
| `holes` | děr (mřížka 3 × 3, index po řádcích) | 9 |
| `game_ticks` | délka hry | 3600 |
| `first_spawn` | tik prvního krtka | 30 |
| `spawn_every` | tiků mezi krtky, obtížnost 1–5 | [50, 42, 36, 30, 26] |
| `up_ticks` | jak dlouho je krtek venku, obtížnost 1–5 | [80, 68, 56, 46, 38] |
| `gold_pct` | šance zlatého krtka | 10 |
| `bomb_pct` | šance bomby, obtížnost 1–5 | [0, 5, 8, 10, 12] |
| `points`, `gold_points` | body za krtka a zlatého | 10, 30 |
| `bomb_penalty` | ztráta za bombu | 20 |
| `star_scores` | skóre pro 3★, 2★, 1★ | [700, 450, 250] |
| `tick_hz`, `time_cap_s` | jen UI | 60, 120 |

## Stav

```
{ tick, holes, nextSpawn, score, hits, misses, over, rng }
```

`holes` = pole `{kind, left}`: `kind` `""` (prázdná), `"mole"`, `"gold"`, `"bomb"`; `left` tiky
do schování. `nextSpawn` tiky do dalšího krtka (`init`: `firstSpawn`). `misses` = utečení krtci
(ne bomby).

## Akce

`{"by": "player", "op": "tick", "n": int ≥ 1}`, `{"by": "player", "op": "hit", "hole": 0…holes−1}`,
`{"by": "timeout"}`. Po konci nelegální. `legalActions` prázdné.

## Pravidla

- **Tik** (v tomto pořadí): `tick += 1`.
  1. Každá díra s `left > 0` (pořadí indexů): `left −= 1`; při 0 se schová (`kind = ""`); utekl-li
     krtek nebo zlatý, `misses += 1`.
  2. `nextSpawn −= 1`; při 0: `nextSpawn = spawnEvery[level − 1]`; prázdné díry v pořadí
     indexů; je-li aspoň jedna: `díra = prázdné[rng.nextInt(počet)]`, pak
     `roll = rng.nextInt(100)`: `roll < bombPct[level − 1]` → bomba, jinak
     `roll < bombPct + goldPct` → zlatý, jinak krtek; `left = upTicks[level − 1]`. Bez prázdné
     díry se `rng` nevolá.
  3. `tick ≥ gameTicks` → `over = true` (zbylé tiky akce se zahodí).
- **Úder** do díry: krtek → `score += points`, `hits += 1`; zlatý → `score += goldPoints`,
  `hits += 1`; bomba → `score = max(0, score − bombPenalty)`; díra se vyprázdní (`kind = ""`,
  `left = 0`). Úder do prázdné díry nic nemění (legální).
- `timeout`: `over = true`.

## AI

Bez soupeře; `aiAction` vrací `{by: "player", op: "tick", n: 1}`; `ai` nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, hits, misses}`; hvězdy podle `starScores`, `winner = "player"` při ≥ 1★,
jinak `"ai"`.

## UI

Mřížka 3 × 3 děr, krtek vyjede a zajede (animace jen podle `left`), klepnutí = `hit`. Zbývající
čas a skóre nahoře.

## Hraniční případy

- Krtek, kterému v tomto tiku vyprší `left`, už se trefit nedá (schová se v kroku 1).
- Bomba, která sama zajede, nic nestojí.
- Dva rychlé údery do jedné díry: druhý nic.

# Had

**version: 1** · engine `arcade` · P0 · vektory `vectors/had.json` · kontrakt
`specs/minigames/README.md`

## Účel

Had na mřížce (M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 37) v herně s automaty. Hráč mění směr
tahem prstem, had roste s každým jídlem a zrychluje. Sám na skóre. Simulace běží v celých
tikách (60 za sekundu), UI posílá uplynulé tiky a otočení.

## Config

`content/tuning.yaml` → `minigames.had`; ve vektoru
`{level, w, h, startInterval, minInterval, speedupEvery, foodPoints, starScores}`.

| klíč | význam | default |
|---|---|---|
| `w`, `h` | mřížka (buňky), x doprava, y nahoru | 15, 21 |
| `start_interval` | tiků na posun hada na začátku, obtížnost 1–5 | [14, 12, 10, 9, 8] |
| `min_interval` | nejrychlejší had, obtížnost 1–5 | [8, 7, 6, 5, 4] |
| `speedup_every` | po kolika jídlech se interval zkrátí o 1 | 5 |
| `food_points` | body za jídlo | 10 |
| `star_scores` | skóre pro 3★, 2★, 1★ | [250, 150, 80] |
| `tick_hz`, `time_cap_s` | jen UI | 60, 300 |

## Stav

```
{ body, dir, next, food, t, interval, score, eaten, over, rng }
```

- `body` = pole `[x, y]`, hlava první. Na začátku `[[w div 2, h div 2], [w div 2, h div 2 − 1],
  [w div 2, h div 2 − 2]]`.
- `dir` směr posledního posunu, `next` směr dalšího: 0 nahoru (0, +1), 1 doprava (+1, 0),
  2 dolů (0, −1), 3 doleva (−1, 0). Na začátku oba 0.
- `food` = `[x, y]`; `t` tiky od posledního posunu; `interval` = `startInterval[level − 1]`.

## Akce

`{"by": "player", "op": "tick", "n": int ≥ 1}`, `{"by": "player", "op": "turn", "dir": 0–3}`,
`{"by": "timeout"}`. Po konci nelegální vše. `legalActions` prázdné.

## Pravidla

- **Jídlo:** volné buňky (ne v `body`) po řádcích (y od 0, v řádku x od 0); `food =
  volné[rng.nextInt(počet)]`. `init` položí první jídlo. Žádná volná buňka → `over = true`.
- `turn d`: `d = (dir + 2) mod 4` (obrátka) se ignoruje, jinak `next = d`. Více otočení mezi
  posuny: platí poslední, každé se porovnává s `dir`.
- `tick n`: po jednom tiku: `t += 1`; při `t ≥ interval` je `t = 0` a **posun**. Po konci se
  zbylé tiky zahodí.
- **Posun:** `dir = next`, nová hlava = hlava + směr.
  1. Mimo mřížku → `over = true` (had se nehne).
  2. `jí` = nová hlava je `food`. Srážka: nová hlava leží v `body`, a když had nejí, nepočítá se
     poslední článek (ocas odjede). Srážka → `over = true`.
  3. Hlava se vloží na začátek `body`; když nejí, poslední článek se odebere.
  4. Když jí: `score += foodPoints`, `eaten += 1`; je-li `eaten mod speedupEvery = 0`,
     `interval = max(interval − 1, minInterval[level − 1])`; nové jídlo.
- `timeout`: `over = true`.

## AI

Bez soupeře; `aiAction` vrací `{by: "player", op: "tick", n: 1}`; `ai` nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, length}`: `length = len(body)`; hvězdy podle `starScores`, `winner =
"player"` při ≥ 1★, jinak `"ai"`.

## UI

Mřížka přes celou šířku, tah prstem = otočení (podle převládající osy tahu). Skóre nahoře.

## Hraniční případy

- Obrátka do protisměru se ignoruje, i když `next` už ukazuje jinam.
- Hlava smí vjet na buňku, kterou v témž posunu opouští ocas.
- Zaplněná mřížka = konec (hráč snědl všechno).

## Upřesnění v1

- `init` položí první jídlo hned (jedno volání `rng`).
- Náraz (zeď i tělo): `dir = next` a `t = 0` už platí, tělo, jídlo a skóre beze změny.
- Zaplnění: posun se dokončí (hlava vložena, skóre a případné zrychlení započteny), `over = true`
  a `food` zůstane na snědené buňce; `rng` se nevolá.
- `turn` se směrem `dir` nastaví `next = dir` (není to obrátka).

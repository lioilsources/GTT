# Kuličky

**version: 1** · engine `flick` · P0 · vektory `vectors/kulicky.json` · kontrakt `specs/minigames/README.md`

## Účel

Pražská dvorková klasika (METROPOLE_PLAN 9.4 č. 83, `plans/M3_PRAHA.md` bod 7): hráč a soupeř
střídavě cvrnkají kuličku k důlku. Kulička v důlku dá body, jinak bod bere ta bližší. Hraje se na
ve Vrchlického sadech u Hlavního nádraží. Gesto (tah prstem) převádí UI na bod míření; pravidla přičtou rozptyl a spočítají body
v celých číslech.

## Config

`content/tuning.yaml` → `minigames.kulicky`; ve vektoru
`{rounds, holeR, holePoints, closerPoints, scatter, aiScatter, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `rounds` | kol (v každém cvrnká hráč, pak soupeř) | 5 |
| `hole_r` | poloměr důlku (mm), důlek je ve (0, 0) | 25 |
| `hole_points` | body za kuličku v důlku | 3 |
| `closer_points` | body za bližší kuličku, když žádná není v důlku | 1 |
| `scatter` | rozptyl hráče pro obtížnost 1–5 (mm) | [30, 40, 50, 60, 70] |
| `ai_scatter` | rozptyl soupeře pro obtížnost 1–5 (mm) | [110, 90, 70, 55, 40] |
| `star_margins` | náskok bodů pro 3★, 2★, 1★ | [6, 3, 1] |

## Stav

```
{ round, turn, playerPts, aiPts, playerShot, aiShot, over, rng }
```

`round` 1–`rounds`, `turn` `"player"` | `"ai"`, `playerShot` / `aiShot` = `{x, y, inHole}`
posledního cvrnku (na začátku nuly a `false`).

## Akce

`{"by": "player" | "ai", "x": int, "y": int, "level": int}` – bod míření v mm (důlek (0, 0),
y nahoru) a obtížnost; `{"by": "timeout"}`. Na tahu je vždy jen `turn`.

## Pravidla

`legalActions` vrací prázdné pole (spojité akce); `apply` odmítne chybou akci strany, která není
na tahu, a jakoukoli akci po konci.

- Cvrnk: `s = scatter[level − 1]` (hráč) nebo `aiScatter[level − 1]` (soupeř); dopad
  `x' = x + nextInt(2s + 1) − s`, pak `y'` stejně (z `rng`). `inHole = x'² + y'² ≤ holeR²`.
- Hráčův cvrnk uloží `playerShot`, `turn = "ai"`. Soupeřův uloží `aiShot` a vyhodnotí kolo:
  - každá kulička v důlku dá své straně `holePoints`;
  - když není v důlku žádná, bližší (menší `x'² + y'²`) dostane `closerPoints`, stejná vzdálenost
    nikomu;
  - `round += 1`, `turn = "player"`; po posledním kole `over = true` (dohraná hra má
    `round = rounds + 1`).
- `timeout`: `over = true` (rozehrané kolo se nepočítá).

## AI

`aiAction` míří do důlku: `{by: "ai", x: 0, y: 0, level}`; přesnost dělá `aiScatter`. Proud `ai`
nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, playerPts, aiPts}`: `score = playerPts`, `margin = playerPts − aiPts`;
`winner` podle znaménka (`"draw"` při 0); `stars` = 3, 2, 1 podle prvního `margin ≥
starMargins[i]`, jinak 0.

## Časový strop

5 min (`minigames.kulicky.time_cap_s`).

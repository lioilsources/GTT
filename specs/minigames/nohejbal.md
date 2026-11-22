# Nohejbal

**version: 1** · engine `sport` · P0 · vektory `vectors/nohejbal.json` · kontrakt `specs/minigames/README.md`

## Účel

Český sport přes síť (METROPOLE_PLAN 9.4 č. 85, `plans/M3_PRAHA.md` bod 7), zjednodušený na
souboj jeden na jednoho na Letné. Hráč tahem prstem volí, kam soupeři do pole míč posílá; míč mimo
pole je bod pro soupeře, míč mimo soupeřův dosah bod pro hráče. První engine `sport`.

## Hřiště

Každá polovina je obdélník `x ∈ [−halfWidth, halfWidth]`, `y ∈ [0, depth]` (mm, y od sítě
dozadu). Hráč i soupeř stojí na středu své poloviny `(0, depth / 2)`.

## Config

`content/tuning.yaml` → `minigames.nohejbal`; ve vektoru
`{halfWidth, depth, winPoints, winBy, maxPoints, scatter, aiScatter, aiReach, aiMargin, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `half_width`, `depth` | polovina hřiště (mm) | 450, 900 |
| `win_points`, `win_by`, `max_points` | hraje se do 10 s rozdílem 2, nejvýš do 15 | 10, 2, 15 |
| `scatter` | rozptyl hráče pro obtížnost 1–5 (mm) | [40, 55, 70, 85, 100] |
| `ai_scatter` | rozptyl soupeře pro obtížnost 1–5 (mm) | [160, 130, 100, 80, 60] |
| `ai_reach` | dosah soupeře od středu jeho poloviny (mm) | [250, 300, 350, 400, 450] |
| `ai_margin` | jak daleko od čar soupeř míří (mm) | [220, 180, 140, 110, 80] |
| `star_margins` | náskok bodů pro 3★, 2★, 1★ | [6, 3, 1] |

## Stav

```
{ playerPts, aiPts, turn, server, rally, lastShot, over, rng }
```

`turn` = kdo hraje míč (`"player"` | `"ai"`), `server` = kdo podával výměnu, `rally` = počet
úderů ve výměně, `lastShot` = `{by, x, y, in, reached}` (na začátku prázdné hodnoty).

## Akce

`{"by": "player" | "ai", "x": int, "y": int, "level": int}` – míření do soupeřovy poloviny (mm)
a obtížnost; `{"by": "timeout"}`.

## Pravidla

`legalActions` vrací prázdné pole; `apply` odmítne akci strany mimo tah a akci po konci.

- Úder: `s` podle strany (`scatter` / `aiScatter`), dopad `x' = x + nextInt(2s + 1) − s`, pak
  `y'` stejně (z `rng`). `in = |x'| ≤ halfWidth a 0 ≤ y' ≤ depth`.
- Míč mimo (`!in`): bod soupeři útočníka.
- Míč v poli od hráče: soupeř ho vrátí, když `x'² + (y' − depth/2)² ≤ aiReach[level − 1]²`
  (`reached`), pak `turn = "ai"`; jinak bod hráči.
- Míč v poli od soupeře: hráč ho vrátí vždycky (jeho dovednost je míření), `turn = "player"`.
- Po bodu: nová výměna, podává vítěz bodu (`server = turn = vítěz`), `rally = 0`; jinak
  `rally += 1`.
- Konec: strana s `≥ winPoints` a náskokem `≥ winBy`, nebo kdo první dosáhne `maxPoints` →
  `over = true`. `timeout`: `over = true`.

## AI

`aiAction` míří do jednoho ze čtyř rohů: `k = ai.nextInt(4)`, `x = (k mod 2 = 0 ? −1 : 1) ·
(halfWidth − aiMargin[level − 1])`, `y = k < 2 ? aiMargin[level − 1] : depth − aiMargin[level − 1]`.

## Výsledek a hvězdy

`{winner, stars, score, playerPts, aiPts}`, `score = playerPts`; vítěz podle bodů (`"draw"` jen
po `timeout` při shodě), hvězdy podle `starMargins` jako u Kuliček.

## Časový strop

6 min (`minigames.nohejbal.time_cap_s`).

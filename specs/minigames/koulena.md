# Koulená

**version: 1** · engine `flick` · P0 · vektory `vectors/koulena.json` · kontrakt `specs/minigames/README.md`

## Účel

Koulení koulí do kruhů na boardwalku v New Yorku (METROPOLE_PLAN 9.4 č. 71, 9.5): 3 série po 9
koulích, kruhy 10–100. Hraje se sám na skóre. Gesto (tah prstem) převádí UI na bod míření; pravidla
přičtou rozptyl a spočítají body v celých číslech.

## Config

`content/tuning.yaml` → `minigames.koulena`; ve vektoru
`{series, balls, ringR, ringPoints, pockets, pocketR, pocketPoints, scatter, starScores}`.

| klíč | význam | default |
|---|---|---|
| `series`, `balls` | sérií × koulí | 3, 9 |
| `ring_r` | vnější poloměry kruhů od středu (mm) | [80, 160, 240, 320, 400] |
| `ring_points` | body kruhů | [50, 40, 30, 20, 10] |
| `pockets` | středy kapes za 100 (x, y po dvojicích) | [-300, 360, 300, 360] |
| `pocket_r` | poloměr kapsy | 50 |
| `pocket_points` | body kapsy | 100 |
| `scatter` | rozptyl dopadu pro obtížnost 1–5 (mm) | [40, 55, 70, 85, 100] |
| `star_scores` | součet pro 3★, 2★, 1★ | [700, 520, 360] |

## Stav

```
{ series, ball, score, seriesScores, lastHit, over, rng }
```

`series` 1–3, `ball` 0–8 (kolikátá koule v sérii), `seriesScores` součty dohraných sérií,
`lastHit = {x, y, points}` (na začátku nuly).

## Akce

`{"by": "player", "x": int, "y": int, "level": int}` – bod míření v mm (střed kruhů (0, 0), y nahoru)
a obtížnost (rozptyl); `{"by": "timeout"}`.

## Pravidla

`legalActions` vrací prázdné pole: akce jsou spojité, jejich legalitu (strana na tahu, konec
hry) kontroluje `apply` a nelegální akci odmítne chybou.


- Hod: `s = scatter[level − 1]`, dopad `x' = x + nextInt(2s + 1) − s`, pak `y'` stejně (z `rng`).
- Body: nejdřív kapsy v pořadí z configu: `(x' − px)² + (y' − py)² ≤ pocketR²` → `pocketPoints`;
  jinak první kruh `i` s `x'² + y'² ≤ ringR[i]²` → `ringPoints[i]`; jinak 0.
- `score += body`, `lastHit = {x', y', points}`, `ball += 1`. Po `balls` koulích se série uzavře
  (`seriesScores` přidá součet série), `series += 1`, `ball = 0`; po poslední sérii `over = true`.
- `timeout`: `over = true`.

## AI

Hra nemá soupeře; `aiAction` vrací míření do středu (0, 0) s `level` 3 (kontrakt ho vyžaduje).

## Výsledek a hvězdy

`{winner, stars, score, seriesScores}`: `stars` podle `starScores` (≥ první → 3★ …), `winner =
"player"` při ≥ 1★, jinak `"ai"`.

## Časový strop

6 min (`minigames.koulena.time_cap_s`).

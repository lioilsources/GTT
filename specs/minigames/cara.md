# Čára

**version: 1** · engine `flick` · P0 · vektory `vectors/cara.json` · kontrakt `specs/minigames/README.md`

## Účel

Házení mincí ke zdi (METROPOLE_PLAN 9.4 č. 84, `plans/M3_PRAHA.md` bod 7): kdo dohodí minci
nejblíž čáře u zdi a nepřehodí ji, bere kolo. Mince přesně na čáře je „čára!“ a bere víc. Hraje se
na Malostranském náměstí. UI převádí tah prstem na vzdálenost hodu; pravidla přičtou rozptyl.

## Config

`content/tuning.yaml` → `minigames.cara`; ve vektoru
`{rounds, linePoints, roundPoints, scatter, aiScatter, aiAim, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `rounds` | kol (hází hráč, pak soupeř) | 7 |
| `line_points` | body za minci přesně na čáře (`y' = 0`) | 3 |
| `round_points` | body za bližší minci | 1 |
| `scatter` | rozptyl hráče pro obtížnost 1–5 (mm) | [20, 28, 36, 44, 52] |
| `ai_scatter` | rozptyl soupeře pro obtížnost 1–5 (mm) | [90, 70, 55, 40, 28] |
| `ai_aim` | jak daleko před čáru soupeř míří (mm), obtížnost 1–5 | [90, 70, 55, 40, 28] |
| `star_margins` | náskok bodů pro 3★, 2★, 1★ | [5, 3, 1] |

## Stav

```
{ round, turn, playerPts, aiPts, playerCoin, aiCoin, over, rng }
```

`playerCoin` / `aiCoin` = `{y, burnt}` posledního hodu (na začátku `0`, `false`); `y` je
vzdálenost od čáry v mm, záporná před čárou.

## Akce

`{"by": "player" | "ai", "y": int, "level": int}` – míření (y < 0 před čárou), obtížnost;
`{"by": "timeout"}`.

## Pravidla

`legalActions` vrací prázdné pole; `apply` odmítne akci strany mimo tah a akci po konci.

- Hod: `s` podle strany jako u Kuliček, `y' = y + nextInt(2s + 1) − s` (z `rng`);
  `burnt = y' > 0` (přehozená přes čáru).
- Hráčův hod uloží `playerCoin`, `turn = "ai"`. Soupeřův uloží `aiCoin` a vyhodnotí kolo:
  - mince s `y' = 0` dá své straně `linePoints` (obě mohou);
  - jinak bližší nepřehozená mince (větší `y'`, tj. menší `|y'|`) dá `roundPoints`; obě
    přehozené nebo stejná vzdálenost = nikdo;
  - `round += 1`, `turn = "player"`; po posledním kole `over = true`.
- `timeout`: `over = true`.

## AI

`aiAction` = `{by: "ai", y: −aiAim[level − 1], level}` (čím lepší soupeř, tím blíž čáře míří).

## Výsledek a hvězdy

Jako Kuličky: `{winner, stars, score, playerPts, aiPts}`, `score = playerPts`, hvězdy podle
`starMargins`.

## Časový strop

4 min (`minigames.cara.time_cap_s`).

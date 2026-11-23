# Bowling

**version: 1** · engine `flick` · P0 · vektory `vectors/bowling.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1

## Účel

Deset framů na bowlingové dráze (M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 27), sám na skóre.
Pohled shora, dráha na výšku. Hráč posune kouli na čáře, táhne prstem k kuželkám: směr a síla;
obtížnost přidá rozptyl. Kuželky jsou kotouče, sražená = posunutá z místa.

## Config

`content/tuning.yaml` → `minigames.bowling`; ve vektoru
`{level, laneW, headY, pinDx, pinDy, ballR, ballM, pinR, pinM, minSpeed, maxSpeed, pinDec, ePin, eWall, deckY0, deckY1, knock, maxSteps, scatter, starScores}`.

| klíč | význam | default |
|---|---|---|
| `lane_w` | šířka dráhy (u = 0,01 mm), x 0…`lane_w` | 106600 |
| `head_y` | y první kuželky od čáry přešlapu (y = 0) | 1829000 |
| `pin_dx`, `pin_dy` | půl rozteče kuželek v řadě, vzdálenost řad | 15240, 26396 |
| `ball_r`, `ball_m` | koule | 10900, 70 |
| `pin_r`, `pin_m` | kuželka (kotouč) | 6050, 15 |
| `min_speed`, `max_speed` | rychlost koule při síle 1 a 100 (u/krok, 240 kroků/s) | 2000, 3600 |
| `pin_dec` | zpomalení kuželek (koule se nezpomaluje) | 12 |
| `e_pin`, `e_wall` | odrazivost těleso–těleso, kuželka–boční stěna (‰) | 700, 500 |
| `deck_y0`, `deck_y1` | začátek a konec plata kuželek | 1799000, 1950000 |
| `knock` | o kolik se kuželka musí posunout, aby padla | 1500 |
| `max_steps` | strop kroků na hod | 1500 |
| `scatter` | rozptyl normovaného míření (u), obtížnost 1–5 | [600, 900, 1200, 1500, 1800] |
| `star_scores` | skóre pro 3★, 2★, 1★ | [170, 130, 90] |
| `steps_per_frame`, `time_cap_s` | jen UI | 4, 480 |

## Kuželky

Kuželka `i` = 0–9 (čísla 1–10): řada 0 = [1], 1 = [2, 3], 2 = [4, 5, 6], 3 = [7, 8, 9, 10];
v řadě `k` kuželka `j` (zleva) stojí na `x = laneW div 2 + (2j − k) × pinDx`,
`y = headY + k × pinDy`. Těleso 0 je koule, tělesa 1–10 kuželky 1–10.

## Svět hodu

- Stojící kuželky (`standing`) se postaví na svá místa (`on`, rychlost 0), ostatní `on = false`.
  Koule na `(x, 0)`.
- Statika: levá stěna `[−50000, 0] × [deckY0, deckY1 + 50000]`, pravá `[laneW, laneW + 50000] ×
  [deckY0, deckY1 + 50000]`, odrazivost `eWall`. Těleso–těleso `ePin`. Tření: koule 0, kuželky
  `pinDec`.
- Zachycení (krok 2) v pořadí těles: `y > deckY1` → `on = false` (jáma); koule s `y < deckY0`
  a `x < 0` nebo `x > laneW` → `on = false` (žlab).
- Simulace do klidu (`maxSteps`). Kuželka **padla**, když po simulaci není `on`, nebo
  `(x − x0)² + (y − y0)² > knock²` od svého místa.

## Stav

```
{ frame, roll, standing, rolls, score, lastKnocked, over, rng }
```

`frame` 1–10, `roll` 1–3 (hod ve framu), `standing` 10 × bool, `rolls` sražené kuželky po hodech,
`score` = `total(rolls)`, `lastKnocked` posledního hodu (na začátku 0).

## Akce

`{"by": "player", "op": "roll", "x": int, "aim": int, "power": int}` – start koule na čáře
(`ballR ≤ x ≤ laneW − ballR`), bod míření `(aim, headY)` a síla 1–100; `{"by": "timeout"}`.
Nelegální: mimo rozsah, po konci. `legalActions` prázdné.

## Pravidla

- Hod: normované míření z `(x, 0)` na `(aim, headY)` (fyzika), rozptyl
  `ex = rng.nextInt(2s + 1) − s`, pak `ey` stejně, `s = scatter[level − 1]`; rychlost
  `sp = minSpeed + trunc((maxSpeed − minSpeed) × power / 100)`. Simulace.
- `k` = kolik ze `standing` padlo; `rolls` přidá `k`, padlé se z `standing` vyškrtnou.
- **Framy 1–9:** strike (`roll = 1`, `k = 10`) nebo druhý hod → další frame, `roll = 1`, všech
  10 stojí. Jinak `roll = 2`.
- **Frame 10:** po každém hodu, když nestojí žádná kuželka, postaví se znovu všech 10. Třetí hod
  je, když první byl strike nebo první dva daly 10. Po posledním hodu `over = true`.
- `total(rolls)` = běžné bowlingové skóre: po framech, strike = 10 + další dva hody, spare =
  10 + další hod, jinak součet; chybějící budoucí hody se počítají 0.
- `timeout`: `over = true`.

## AI

Hra nemá soupeře; `aiAction` vrací `{by: "player", op: "roll", x: laneW div 2, aim: laneW div 2,
power: 80}`; `ai` nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, rolls}`: `stars` podle `starScores` (≥ první → 3★…), `winner = "player"`
při ≥ 1★, jinak `"ai"`.

## UI

Dráha na výšku, kamera jede s koulí, kuželky nahoře. Před hodem tah prstem koulí do strany
(start), pak tah ke kuželkám. Tabulka framů nahoře (`bowlingFrame`), strike/spare toast
(`bowlingStrike`, `bowlingSpare`).

## Hraniční případy

- Žlab: koule zmizí, kuželky stojí, `k = 0`.
- Kuželka odražená od stěny zpět na plato a zastavená daleko od místa = padlá.
- Ve framu 10 se po spare postaví všech 10 kuželek pro třetí hod.

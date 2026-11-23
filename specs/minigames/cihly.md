# Cihly

**version: 1** · engine `arcade` · P0 · vektory `vectors/cihly.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1 (jen aritmetika a nejbližší bod)

## Účel

Odrážení míčku do zdi z cihel (breakout; M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 38) v herně
s automaty. Hráč posouvá pálku prstem, míček boří cihly. Sám na skóre, tři životy. Simulace
v celých tikách (60 za sekundu).

## Config

`content/tuning.yaml` → `minigames.cihly`; ve vektoru
`{level, w, h, ballR, paddleY, paddleH, paddleW, speed, maxVxPct, serveTicks, lives, rows, cols, brickX0, brickTop, brickW, brickH, brickGap, rowPoints, livesBonus, starScores}`.

| klíč | význam | default |
|---|---|---|
| `w`, `h` | hřiště (u), y nahoru | 10000, 16000 |
| `ball_r` | poloměr míčku | 120 |
| `paddle_y`, `paddle_h` | střed pálky na ose y, poloviční výška | 1200, 150 |
| `paddle_w` | poloviční šířka pálky, obtížnost 1–5 | [1300, 1150, 1000, 900, 800] |
| `speed` | rychlost míčku (u/tik), obtížnost 1–5 | [70, 80, 90, 100, 110] |
| `max_vx_pct` | nejvyšší vodorovná složka po odrazu od pálky (% rychlosti) | 80 |
| `serve_ticks` | tiků na pálce před výstřelem | 60 |
| `lives` | životy | 3 |
| `rows`, `cols` | cihel | 6, 8 |
| `brick_x0`, `brick_top` | levý okraj první cihly, horní okraj první řady | 80, 14500 |
| `brick_w`, `brick_h`, `brick_gap` | cihla a mezera | 1150, 450, 80 |
| `row_points` | body za cihlu po řadách shora | [70, 70, 50, 50, 30, 10] |
| `lives_bonus` | bonus za každý zbylý život při vyčištění | 100 |
| `star_scores` | skóre pro 3★, 2★, 1★ | [2400, 1600, 900] |
| `tick_hz`, `time_cap_s` | jen UI | 60, 360 |

## Cihly

Cihla `i = row × cols + col` (řada 0 nahoře): `x0 = brickX0 + col × (brickW + brickGap)`,
`x1 = x0 + brickW`, `y1 = brickTop − row × (brickH + brickGap)`, `y0 = y1 − brickH`.

## Stav

```
{ ball, paddle, serve, bricks, score, lives, over, rng }
```

`ball = {x, y, vx, vy}`, `paddle` = x středu pálky, `serve` tiky do výstřelu (0 = míček letí),
`bricks` = pole bool (stojí), `score`, `lives`.

`init`: `paddle = w div 2`, `serve = serveTicks`, míček na pálce (`x = paddle`,
`y = paddleY + paddleH + ballR`, rychlost 0), všechny cihly stojí.

## Akce

`{"by": "player", "op": "move", "x": int}` – pálka na `clamp(x, hw, w − hw)` (`hw =
paddleW[level − 1]`), okamžitě; `{"by": "player", "op": "tick", "n": int ≥ 1}`;
`{"by": "timeout"}`. Po konci nelegální. `legalActions` prázdné.

## Tik

`sp = speed[level − 1]`, `hw = paddleW[level − 1]`.

1. **Podání** (`serve > 0`): `serve −= 1`, míček na pálce (jako v `init`). Když `serve` klesne na
   0: `sv = sp div 2`, `vx = rng.nextInt(2·sv + 1) − sv`, `vy = isqrt(sp² − vx²)`. Konec tiku.
2. **Pohyb:** `x += vx`, `y += vy`.
3. **Stěny:** `x − r < 0` a `vx < 0` → `vx = −vx`; `x + r > w` a `vx > 0` → `vx = −vx`;
   `y + r > h` a `vy > 0` → `vy = −vy`.
4. **Cihly** v pořadí `i`, jen stojící: nejbližší bod obdélníku `q` (fyzika), `dx = x − qx`,
   `dy = y − qy`, `d2 = dx² + dy²`. Dotyk při `d2 < r²`:
   - `d2 = 0` → `vy = −vy`;
   - jinak při `vx·dx + vy·dy ≥ 0` se cihla přeskočí (bez zásahu);
   - jinak `|dx| > |dy|` → `vx = −vx`; `|dy| > |dx|` → `vy = −vy`; shoda → obojí.
   Zasažená cihla padne, `score += rowPoints[row]`; v jednom tiku nejvýš jedna cihla.
5. **Pálka** `[paddle − hw, paddle + hw] × [paddleY − paddleH, paddleY + paddleH]`: při
   `vy < 0`, `y ≥ paddleY` a `d2 < r²` (nejbližší bod): `mx = trunc(sp × maxVxPct / 100)`,
   `vx = clamp(trunc(mx × (x − paddle) / hw), −mx, mx)`, `vy = isqrt(sp² − vx²)`.
6. **Ztráta:** `y + r < 0` → `lives −= 1`; `lives = 0` → `over = true`; jinak `serve =
   serveTicks` a míček na pálku.
7. **Vyčištěno:** žádná cihla nestojí → `score += lives × livesBonus`, `over = true`.

`tick n` provede tiky po jednom; po konci zbylé zahodí. `timeout`: `over = true`.

## AI

Bez soupeře; `aiAction` vrací `{by: "player", op: "tick", n: 1}`; `ai` nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, lives, cleared}`: `cleared` = žádná cihla nestojí; hvězdy podle
`starScores`, `winner = "player"` při ≥ 1★, jinak `"ai"`.

## UI

Pálka sleduje prst ve spodní třetině (posílá `move` při každém pohybu, `tick` po snímcích).
Životy a skóre nahoře.

## Hraniční případy

- Rychlost míčku se mění jen odrazem od pálky (velikost zůstává `sp` až na zaokrouhlení `isqrt`).
- Míček zespodu pálky (`y < paddleY`) se neodrazí a propadne.
- Při podání se míček hýbe s pálkou.

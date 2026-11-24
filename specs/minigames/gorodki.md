# Gorodki

**version: 1** · engine `flick` · P0 · vektory `vectors/gorodki.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1 · plán: `plans/M6_MOSKVA.md`
bod 6 (místní hry) · parita F-081 · jen Moskva

## Účel

Ruské městečko z Gorkého parku: ve čtverci („gorod“) stojí figura z pěti špalíků, hráč na ni hází
pálku. Špalík, který skončí mimo čtverec, je vybitý. První hod na figuru jde z daleké čáry („kon“),
po prvním vybitém špalíku z poloviční čáry („polukon“). Pět figur, pálek je na celou hru omezeně.
Hraje se sám (jako Bowling), AI nehraje.

## Config

`content/tuning.yaml` → `minigames.gorodki`; ve vektoru `{level, gorodW, gorodY0, gorodY1,
polukonY, batR, batM, batDec, pieceR, pieceM, pieceDec, minSpeed, maxSpeed, eBody, fieldPad,
maxSteps, bats, scatter, starFigs, figures}`, kde `figures` = `[fig1, …, fig5]`.

| klíč | význam | default |
|---|---|---|
| `gorod_w`, `gorod_y0`, `gorod_y1` | čtverec `x ∈ [0, gorodW]`, `y ∈ [gorodY0, gorodY1]` (u = 0,01 mm, kon na `y = 0`) | 200000, 1300000, 1500000 |
| `polukon_y` | poloviční čára | 650000 |
| `bat_r`, `bat_m`, `bat_dec` | pálka jako kotouč (rotující hůl): poloměr, hmotnost, zpomalení | 16000, 200, 3 |
| `piece_r`, `piece_m`, `piece_dec` | špalík | 5000, 20, 40 |
| `min_speed`, `max_speed` | rychlost hodu v u za krok pro sílu 0 až 100 | 3000, 5200 |
| `e_body` | restituce těleso–těleso (‰) | 600 |
| `field_pad` | těleso dál než tolik od čtverce opouští hřiště | 300000 |
| `max_steps` | strop kroků simulace hodu | 900 |
| `bats` | pálek na celou hru podle obtížnosti 1–5 | [24, 21, 18, 16, 14] |
| `scatter` | rozptyl míření podle obtížnosti | [600, 900, 1200, 1500, 1800] |
| `star_figs` | rozbité figury pro 3★, 2★, 1★ | [5, 3, 1] |
| `fig1`…`fig5` | pět špalíků `[dx, dy, …]` od středu přední čáry (`gorodW / 2`, `gorodY0`) | dělo, hvězda, studna, šíp, rak |
| `steps_per_frame`, `time_cap_s` | jen UI | 4, 420 |

## Stav

```
{ fig, px, py, up, bats, throws, cleared, knocked, polukon, lastOut, over, rng }
```

- `fig` = číslo figury 1–5; `px`, `py`, `up` = pět špalíků (poloha, stojí/vybitý). Nová figura:
  `px[k] = gorodW / 2 + dx_k` (celočíselně `floor`), `py[k] = gorodY0 + dy_k`, `up[k] = true`.
- `bats` = zbývající pálky (start `bats[level−1]`), `throws` = hody, `cleared` = rozbité figury,
  `knocked` = vybité špalíky celkem, `polukon` = hází se z poloviční čáry, `lastOut` = vybité
  posledním hodem.
- `init`: `rng = Prng(seed).state`, figura 1, čísla 0, `polukon = false`, `over = false`.

## Akce

- `{"by": "player", "op": "throw", "x": int, "aim": int, "power": int}` – hod z bodu `(x, ly)`,
  kde `ly = polukon ? polukonY : 0`; `x ∈ [0, gorodW]`, `power ∈ [1, 100]`, `aim` = x bodu míření
  na přední čáře (`y = gorodY0`).
- `{"by": "timeout"}` – kdykoli před koncem.
- `legalActions` → `[]` (spojitý hod); legalitu ověřuje `apply`.

## Pravidla

### Hod

1. Míření: `n = normalizedAim(x, ly, aim, gorodY0)`; rozptyl `s = scatter[level − 1]`,
   `ex = rng.nextInt(2s + 1) − s`, pak `ey = rng.nextInt(2s + 1) − s` (vždy obě čísla).
2. Rychlost `sp = minSpeed + trunc((maxSpeed − minSpeed) × power, 100)`;
   `v = shotVelocity(x, ly, n.x + ex, n.y + ey, sp)`.
3. Svět: tělesa `[pálka (x, ly, v, batR, batM), špalík 0…4 (px, py, 0, pieceR, pieceM, on = up)]`,
   bez statik, `eBody`. Zachycení po pohybu: těleso s `x < −fieldPad`, `x > gorodW + fieldPad`
   nebo `y > gorodY1 + fieldPad` → `off`. Zpomalení: pálka `batDec`, špalík `pieceDec`.
   `simulate(world, maxSteps)`.
4. Špalík, který stál, je **vybitý**, když je `off` nebo jeho střed leží mimo čtverec
   (`x < 0`, `x > gorodW`, `y < gorodY0` nebo `y > gorodY1`). Ostatní stojí na nové poloze.
5. `bats −= 1`, `throws += 1`, `lastOut` = vybité, `knocked += lastOut`; `lastOut > 0` →
   `polukon = true`.
6. Všech pět vybitých → `cleared += 1`; `fig = 5` → `over`, jinak další figura a `polukon = false`.
7. `bats = 0` → `over`.

### timeout

`over = true`, nic jiného se nemění.

### Ostatní

- Hod po konci, jiné `by`, neceločíselná pole nebo mimo rozsah → `IllegalAction`.
- `aiAction` vrací `{by: "player", op: "throw", x: gorodW / 2, aim: gorodW / 2, power: 60}` (jen
  pro testy, AI nehraje).

## Výsledek a hvězdy

`{winner, stars, score, cleared, knocked, throws}`: `score = knocked × 10 + cleared × 50`, při
`cleared = 5` ještě `+ bats × 20`; `stars` = 3 při `cleared ≥ starFigs[0]`, 2 při `≥ starFigs[1]`,
1 při `≥ starFigs[2]`, jinak 0; `winner = "player"` při ≥ 1★, jinak `"ai"`.

## UI

- Na výšku: čtverec s figurou nahoře zvětšený, čára hodu dole (kon nebo polukon), mezi nimi
  zkrácený prostor jako u Bowlingu.
- Vodorovný tah posouvá místo hodu po čáře, švih nahoru hází: směr = míření, délka = síla.
- Nahoře figura (`gorodkiFig` s `gorodkiFig_<n>`) a pálky (`gorodkiBats`); po prvním vybitém
  `gorodkiPolukon`, po rozbití figury toast `gorodkiClear`.
- Hod se přehraje z kroků simulace (`steps_per_frame`), stav pak dá `apply`.

## Hraniční případy

- Hod mimo figuru nic nevybije, ale stojí pálku a nemění `polukon`.
- Odražený špalík, který zůstane ve čtverci, stojí dál na nové poloze (i natlačený k okraji).
- Poslední pálka, která rozbije pátou figuru, dá výsledek s bonusem 0 za pálky.

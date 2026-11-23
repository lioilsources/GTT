# Minigolf

**version: 1** · engine `flick` · P0 · vektory `vectors/minigolf.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1

## Účel

Šest jamek minigolfu (M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 28), sám proti paru. Pohled
shora, dráha na výšku. Tah prstem od míčku = směr a síla; obtížnost přidá rozptyl. Dráhy jsou
stejné ve všech městech, místní památky kreslí UI jen jako dekorace kolem (jamka 6 = řeka
s mostem).

## Config

`content/tuning.yaml` → `minigames.minigolf`; ve vektoru
`{level, holes, ballR, cupR, cupSpeed, maxSpeed, dec, sandDec, eWall, eBumper, maxSteps, maxStrokes, scatter, starOver}`.
`holes` = pole jamek `[h1, …, h6]` (v tuningu klíče `h1`…`h6`).

| klíč | význam | default |
|---|---|---|
| `h1` … `h6` | jamky (formát níže, **mm**) | viz tuning |
| `ball_r` | poloměr míčku (u = 0,01 mm) | 2135 |
| `cup_r` | míček s středem do této vzdálenosti od jamky… | 5400 |
| `cup_speed` | …a rychlostí nejvýš touto (u/krok) spadne | 350 |
| `max_speed` | rychlost při síle 100 (u/krok, 240 kroků/s) | 800 |
| `dec`, `sand_dec` | zpomalení na trávě a v písku | 1, 6 |
| `e_wall`, `e_bumper` | odrazivost stěn a kruhových překážek (‰) | 700, 800 |
| `max_steps` | strop kroků na úder | 3600 |
| `max_strokes` | úderů na jamku, pak se míček zvedne | 6 |
| `scatter` | rozptyl normovaného míření (u), obtížnost 1–5 | [500, 900, 1300, 1700, 2100] |
| `star_over` | nejvýš úderů nad par celkem pro 3★, 2★, 1★ | [2, 5, 9] |
| `steps_per_frame`, `time_cap_s` | jen UI | 4, 480 |

## Formát jamky

Plochý seznam celých čísel v mm, uvnitř hry ×100 na u:

```
[w, h, par, sx, sy, cx, cy,
 nRect,  (x0, y0, x1, y1) × nRect,      // stěny
 nCirc,  (x, y, r) × nCirc,              // kruhové překážky
 nSand,  (x0, y0, x1, y1) × nSand,      // písek
 nWater, (x0, y0, x1, y1) × nWater]     // voda
```

Hřiště `[0, w] × [0, h]`, start `(sx, sy)`, jamka `(cx, cy)`. Statika v pořadí: okraje levý
`[−200, 0] × [−200, h + 200]`, pravý `[w, w + 200] × [−200, h + 200]`, dolní `[0, w] × [−200, 0]`,
horní `[0, w] × [h, h + 200]` (mm), pak stěny v pořadí seznamu (vše `eWall`), pak kruhy
(`eBumper`). `metro validate` nekontroluje tvar; špatný seznam je chyba načtení v klientu.

## Svět úderu

- Jediné těleso: míček, hmotnost 1. Tření: `sandDec`, když je střed v některém písku
  (`x0 ≤ x ≤ x1` a `y0 ≤ y ≤ y1`, v u), jinak `dec`.
- Zachycení (krok 2): (a) střed ve vodě (stejná podmínka) → **šplouchnutí**, simulace končí
  hned; (b) `(x − cx)² + (y − cy)² ≤ cupR²` a `vx² + vy² ≤ cupSpeed²` → **v jamce**, konec.
- Jinak simulace do klidu (`maxSteps`). Míček, který se zastavil se středem do `cupR` od
  jamky, je také v jamce (kontrola jednou po skončení simulace).

## Stav

```
{ hole, strokes, scores, x, y, over, rng }
```

`hole` 1–6 (dohraná hra 7), `strokes` údery na rozehrané jamce (s trestnými), `scores` výsledky
dohraných jamek, `x, y` poloha míčku (u).

## Akce

`{"by": "player", "op": "putt", "x": int, "y": int, "power": int}` – bod míření (u), síla 1–100;
`{"by": "timeout"}`. Nelegální: po konci, síla mimo rozsah, bod míření ve středu míčku.
`legalActions` prázdné.

## Pravidla

- `init`: `hole = 1`, míček na startu jamky 1, `strokes = 0`, `scores = []`.
- Úder: `strokes += 1`; normované míření z míčku (fyzika), rozptyl
  `ex = rng.nextInt(2s + 1) − s`, pak `ey`, `s = scatter[level − 1]`;
  `sp = trunc(power × maxSpeed / 100)`. Simulace.
- Šplouchnutí: `strokes += 1` (trest), míček zpět na polohu před úderem.
- V jamce: `scores` přidá `strokes`, další jamka (míček na její start, `strokes = 0`).
- Jinak, když `strokes ≥ maxStrokes`: `scores` přidá `maxStrokes + 1`, další jamka.
- Po šesté jamce `over = true`, `hole = 7`.
- `timeout`: `over = true`.

## AI

Bez soupeře; `aiAction` vrací `{by: "player", op: "putt", x: cx, y: cy, power: 50}` (míření na
jamku aktuální díry v u); `ai` nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, scores, par}`: `score` = součet `scores`, `par` = součet parů dohraných
jamek. Jen dohraná hra (6 jamek) má hvězdy: `score − par ≤ starOver[0]` → 3★, `≤ starOver[1]`
→ 2★, `≤ starOver[2]` → 1★, jinak 0★; `winner = "player"` při ≥ 1★, jinak `"ai"`. Méně je lépe.

## UI

Dráha shora na výšku, kamera drží míček a jamku. Řádek nahoře: jamka a par (`minigolfHole`),
údery. Šplouchnutí = toast `minigolfWater`, jamka = `minigolfHoled`.

## Hraniční případy

- Rychlý míček přes jamku nespadne (vylétne z ní).
- Trestný úder se počítá do `maxStrokes`.
- Míček zastavený v písku hraje se odtud.

## Upřesnění v1

- Všechny délky z formátu jamky (rozměry, start, jamka, stěny, kruhy, písek, voda) i tloušťka
  okrajů (200 mm = 20000 u) se násobí 100; `ballR`, `cupR`, `cupSpeed` jsou už v u.
- Zachycení v kroku 2: nejdřív voda, pak jamka; poloha po pohybu, rychlost z konce předchozího
  kroku. Zachycení končí simulaci hned (kroky 3–5 se neprovedou).
- Kontrola „zastavený míček do `cupR`" proběhne po každé simulaci, která neskončila zachycením,
  i když skončila stropem `maxSteps`.
- Šplouchnutí: `strokes += 1` a návrat míčku; teprve pak se kontroluje `maxStrokes`.
- Po dohrané jamce `strokes = 0`; po šesté `hole = 7` a `x, y` zůstanou, kde míček skončil
  (u šplouchnutí poloha před úderem).
- Písek i voda: `x0 ≤ x ≤ x1` a `y0 ≤ y ≤ y1` ve středu míčku (v u).
- `result.par` = součet parů dohraných jamek; `timeout` změní jen `over`.

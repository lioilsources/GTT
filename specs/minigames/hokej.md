# Vzdušný hokej

**version: 2** · engine `sport` · P0 · vektory `vectors/hokej.json` · kontrakt
`specs/minigames/README.md` · fyzika `specs/minigames/fyzika.md` v1

## Účel

Air hockey proti automatu v herně (M2 bod 9, dávka C; METROPOLE_PLAN 9.4 č. 70). Stůl na výšku,
hráč dole, soupeř nahoře. Hráč vede pálku prstem, kdo dá první `goals` gólů, vyhrál. Simulace
v celých tikách (60 za sekundu); soupeř je deterministický automat uvnitř tiku.

## Config

`content/tuning.yaml` → `minigames.hokej`; ve vektoru
`{level, w, h, puckR, malletR, goalHalf, eWall, eMallet, dec, maxPuck, malletSpeed, aiSpeed, aiReact, aiDefY, homeY, serveY, goals, goalPause, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `w`, `h` | stůl (u), y nahoru, hráč dole | 6000, 10000 |
| `puck_r`, `mallet_r` | poloměr puku a pálky | 250, 350 |
| `goal_half` | polovina šířky branky (střed `w div 2`) | 900 |
| `e_wall`, `e_mallet` | odrazivost (‰) | 900, 900 |
| `dec` | zpomalení puku (u/tik²) | 1 |
| `max_puck` | nejvyšší rychlost puku (u/tik) | 450 |
| `mallet_speed` | nejvyšší rychlost hráčovy pálky (u/tik) | 600 |
| `ai_speed` | rychlost pálky soupeře, obtížnost 1–5 | [100, 140, 180, 220, 260] |
| `ai_react` | po kolika tikách soupeř přehodnotí cíl, obtížnost 1–5 | [16, 12, 8, 5, 3] |
| `ai_def_y` | jak daleko od své čáry soupeř brání | 1200 |
| `home_y` | výchozí vzdálenost pálek od své čáry | 1200 |
| `serve_y` | jak daleko od středu se puk staví po gólu | 1500 |
| `goals` | gólů k výhře | 7 |
| `goal_pause` | tiků pauzy po gólu | 60 |
| `star_margins` | rozdíl gólů pro 3★, 2★ | [5, 3] |
| `tick_hz`, `time_cap_s` | jen UI | 60, 360 |

## Stav

```
{ tick, puck, me, ai, playerGoals, aiGoals, pause, aiClock, over }
```

`puck = {x, y, vx, vy}`; `me`, `ai` = `{x, y, tx, ty}` (poloha pálky a její cíl). `init`: puk
`(w div 2, h div 2 − serveY)` v klidu, `me = (w div 2, homeY)`, `ai = (w div 2, h − homeY)`, cíle
= polohy, `pause = 0`, `aiClock = 0`.

**Poloviny:** hráčova pálka `x ∈ [rm, w − rm]`, `y ∈ [rm, h div 2 − rm]`; soupeřova
`x` stejně, `y ∈ [h div 2 + rm, h − rm]` (`rm = malletR`). Cíle se do své poloviny ořezávají.

## Akce

`{"by": "player", "op": "move", "x": int, "y": int}` – nový cíl hráčovy pálky (ořízne se);
`{"by": "player", "op": "tick", "n": int ≥ 1}`; `{"by": "timeout"}`. Po konci nelegální.
`legalActions` prázdné.

## Tik

1. `tick += 1`. Při `pause > 0`: `pause −= 1`, nic dalšího.
2. **Hráčova pálka** k cíli: `d = t − m`, `L = isqrt(d²)`; `L ≤ malletSpeed` → `m = t`, jinak
   `m += trunc(d × malletSpeed / L)` po složkách. Rychlost pálky `mv` = posun v tomto tiku.
3. **Soupeř:** `aiClock += 1`; při `aiClock ≥ aiReact[level − 1]`: `aiClock = 0` a nový cíl (níže,
   ořízne se). Pak pohyb stejně jako v kroku 2 s `aiSpeed[level − 1]`; `ma` = posun.
4. **Puk:** `x += vx`, `y += vy`.
5. **Brankové čáry** (v2; `(x0, y0)` = poloha puku před krokem 4, `mid = w div 2`). Při `y < 0`
   nebo `y > h` se spočte `xc`, `x` středu puku v okamžiku průchodu čárou:
   `y < 0`: `y0 ≤ 0` → `xc = x0`, jinak `xc = x0 + trunc(vx × y0 / (y0 − y))`;
   `y > h`: `y0 ≥ h` → `xc = x0`, jinak `xc = x0 + trunc(vx × (h − y0) / (y − y0))`.
   - `|xc − mid| ≤ goalHalf` → **gól:** `y < 0` → `aiGoals += 1`, puk na `(w div 2, h div 2 − serveY)`;
     `y > h` → `playerGoals += 1`, puk na `(w div 2, h div 2 + serveY)`. Puk v klidu, obě pálky
     a cíle na výchozí místa, `pause = goalPause`, `aiClock = 0`; dosáhl-li někdo `goals`,
     `over = true`. Konec tiku.
   - Jinak **odraz od čela:** `y < 0` → `y = −y`, `y > h` → `y = 2h − y`; `vy = −trunc(vy × eWall / 1000)`.
     Tik pokračuje krokem 6.
6. **Mantinely** (`r = puckR`, `e = eWall`): `x − r < 0` a `vx < 0` nebo `x + r > w` a `vx > 0` →
   `vx = −trunc(vx × e / 1000)`; `y − r < 0` a `vy < 0` nebo `y + r > h` a `vy > 0`, a zároveň
   `|x − w div 2| > goalHalf` → `vy = −trunc(vy × e / 1000)` (v ústí branky puk projede).
7. **Pálky** (hráčova, pak soupeřova), `R = puckR + malletR`: `dx = px − mx`, `dy = py − my`,
   `d2 = dx² + dy²`; při `0 < d2 < R²`: relativní rychlost `u = v − mv` (u soupeře `ma`),
   `vn = u·d`; při `vn < 0` odraz jako u statiky ve fyzice s `eMallet`, ale z `vn` relativní
   rychlosti (`k = trunc(vn × (1000 + eMallet) × 1000 / d2)`, `v −= trunc(k × d / 1000000)`).
   Pak se puk vysune na dotyk: `L = isqrt(d2)`, `p = m + trunc(d × R / L)` po složkách, a ořízne
   se na `x ∈ [r, w − r]`, a mimo ústí branky (`|x − w div 2| > goalHalf`) i na `y ∈ [r, h − r]`.
8. **Strop:** `s = isqrt(vx² + vy²)`; `s > maxPuck` → `v = trunc(v × maxPuck / s)` po složkách.
9. **Tření** `dec` (fyzika).

`tick n` provede tiky po jednom; po konci zbylé zahodí. `timeout`: `over = true`.

## Soupeř (automat)

Cíl z polohy puku `p` a soupeřovy pálky `a` v okamžiku přehodnocení, `G = rp + rm + 100`:

- Puk v soupeřově polovině (`py ≥ h div 2`): když `ay > py + rp`, cíl = `(px, py)` (útok shora);
  jinak obchvat: `(px − G, py + G)` při `ax ≤ px`, jinak `(px + G, py + G)`.
- Jinak obrana: `(clamp(px, w div 2 − goalHalf, w div 2 + goalHalf), h − aiDefY)`.

`aiAction` hra nepoužívá (vrací `{by: "player", op: "tick", n: 1}`); proud `ai` se nevolá. Hra
nemá ve stavu `rng` a náhodu nepoužívá.

## Výsledek a hvězdy

`{winner, stars, score, playerGoals, aiGoals}`: víc gólů vyhrává, shoda (jen po `timeout`)
`"draw"`; `score = playerGoals`. Výhra hráče o `≥ starMargins[0]` → 3★, `≥ starMargins[1]` → 2★,
jinak 1★; jinak 0★.

## UI

Stůl na výšku, pálka pod prstem (každý pohyb prstu = `move`, každý snímek `tick`). Skóre u
středové čáry, po gólu krátký nápis `hokejGoal`.

## Hraniční případy

- Puk zastavený v soupeřově polovině soupeř dřív nebo později trefí (obchvat a útok).
- Pálka se do soupeřovy poloviny nedostane, puk přes středovou čáru ano.
- Puk vysunutý pálkou do mantinelu se ořízne; odraz od mantinelu proběhne až v dalším tiku.
- (v2) Rychlý puk, který za jeden tik přeletí brankovou čáru mimo ústí, gól nedá a odrazí se od čela.

## Upřesnění v1

- Tik v pauze: jen `tick += 1` a `pause −= 1`; `aiClock` ani nic jiného se nemění.
- Cíl soupeře se přepočítá z polohy puku **před** jeho pohybem v tomto tiku (krok 3 je před 4)
  a z polohy soupeřovy pálky před jejím pohybem; pak se ořízne do jeho poloviny. `mv`, `ma` =
  skutečný posun pálky v tomto tiku.
- Gól: viz krok 5 a Upřesnění v2 (ve v1 se počítal jen podle `y`, bez ohledu na `x`).
- Krok 6: x i y nezávisle, nejdřív x; podmínka ústí bere `x` po pohybu.
- Krok 7: vysunutí na dotyk se provede při každém překryvu `0 < d2 < R²`, i když `vn ≥ 0`
  (odraz jen při `vn < 0`). Ořez: nejdřív `x` do `[r, w − r]`, podmínka ústí se počítá z už
  ořezaného `x`, `y` se ořezává jen mimo ústí. Soupeřova pálka už vidí puk po vysunutí
  a odrazu od hráčovy. Puk vysunutý v ústí za brankovou čáru dá gól až v kroku 5 dalšího
  tiku; odraz od mantinelu po vysunutí až v dalším tiku.
- `move` mění jen cíl; `timeout` jen `over`.

## Upřesnění v2

- Oprava v1: gól rozhodovalo jen `y`, takže rychlý puk (`|vy| > puckR`), který za jeden tik
  přeletěl brankovou čáru mimo ústí, dal gól (odraz v kroku 6 přichází až po přeletu). Ve v2 se
  rozhoduje podle `xc`, místa průchodu čárou; kroky 1–4 a 6–9 se nemění.
- `(x0, y0)` je poloha puku těsně před krokem 4 (tj. po vysunutí a ořezu z předchozího tiku,
  případně výchozí poloha po gólu); `vx`, `vy` jsou rychlosti použité v kroku 4. Interpolace je jen v celých číslech:
  `trunc` = ořez k nule (fyzika); jmenovatel `y0 − y` (resp. `y − y0`) je kladný, protože
  průchod znamená `vy < 0` (resp. `vy > 0`). `xc` se neořezává na stůl. `y0 = 0` (resp. `y0 = h`)
  dává `xc = x0`.
- `y0 < 0` (`y0 > h`) nastane jen po vysunutí puku pálkou za čáru v ústí (Upřesnění v1, krok 7):
  tam se `y` neořezává jen při `|x0 − mid| ≤ goalHalf`, takže `xc = x0` je v ústí a gól padne
  v kroku 5 dalšího tiku jako ve v1.
- Okraj ústí se počítá do branky: `|xc − mid| = goalHalf` je gól. O gólu rozhoduje jen `xc`,
  ne `x` po pohybu (puk může průchodem mimo ústí doletět za čáru nad ústí, a naopak).
- Odraz od čela: poloha se zrcadlí přes čáru (`y = 0 − y`, resp. `y = 2h − y`, `x` beze změny)
  a `vy` se otočí s útlumem `eWall` jako u mantinelu. Po odrazu má `vy` opačné znaménko, takže
  podmínka pro `y` v kroku 6 už nesplní (`vy < 0` u spodní, `vy > 0` u horní čáry) a druhý odraz
  ve stejném tiku nenastane; `x` v kroku 6 se kontroluje jako vždy (z `x` po pohybu). Kroky 7–9
  proběhnou normálně.
- Ústí v kroku 6 (`|x − mid| ≤ goalHalf` → bez odrazu) a pravidla ořezu v kroku 7 zůstávají jako
  ve v1; puk, který v ústí zajede pod `r` od čáry, gól dá, jen když čáru opravdu protne v ústí.

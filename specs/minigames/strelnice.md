# Střelnice

**version: 1** · engine `flick` · P0 · vektory `vectors/strelnice.json` · kontrakt `specs/minigames/README.md`

## Účel

Pouťová střelnice (METROPOLE_PLAN 9.5): 3 kola po 90 s, terče jezdí ve třech drahách, hráč střílí
klepnutím. Simulace běží v celých tikách (`tick_hz`), UI posílá uplynulé tiky a výstřely.

## Config

`content/tuning.yaml` → `minigames.strelnice`; ve vektoru
`{rounds, roundTicks, targets, width, lanes, kinds, magazine, reloadTicks, starScores}`.

| klíč | význam | default |
|---|---|---|
| `tick_hz` | tiků za sekundu (jen UI) | 30 |
| `rounds`, `round_ticks` | kol × tiků | 3, 2700 |
| `targets` | terčů za kolo | 36 |
| `width` | šířka pole (jednotky) | 1000 |
| `lanes` | y drah | [250, 500, 750] |
| `kinds` | druhy terčů po trojicích (poloměr, rychlost/tik, body): malý, střední, velký | [40, 9, 50, 60, 6, 20, 80, 4, 10] |
| `kind_pct` | hranice hodu pro malý, střední (zbytek velký) | [15, 55] |
| `magazine` | nábojů v zásobníku | 6 |
| `reload_ticks` | přebíjení po vystřílení | 45 |
| `star_scores` | součet pro 3★, 2★, 1★ | [1500, 1000, 600] |

## Terče kola

Na začátku každého kola se z `rng` vygeneruje `targets` terčů, `i = 0…targets−1`, s
`spacing = (roundTicks · 9) div (10 · targets)`:

```
lane  = nextInt(len(lanes))
roll  = nextInt(100)            → kind 0 při roll < kindPct[0], 1 při < kindPct[1], jinak 2
spawn = i · spacing + nextInt(spacing)
dir   = +1 pro sudou dráhu (index), −1 pro lichou
```

Terč `{lane, kind, spawn, dir, hit: false}`. Poloha v tiku `t ≥ spawn`:
`x = x0 + dir · speed · (t − spawn)`, `x0 = −r` pro `dir = +1`, jinak `width + r`; `y = lanes[lane]`.
Terč je na poli, když `t ≥ spawn`, není `hit` a `−r ≤ x ≤ width + r`.

## Stav

```
{ round, tick, score, shots, hits, ammo, reload, targets, over, rng }
```

`tick` v rámci kola od 0; `ammo` náboje v zásobníku; `reload` zbývající tiky přebíjení (0 = nabito).

## Akce

`{"by": "player", "op": "tick", "n": int ≥ 1}` – posun času; `{"by": "player", "op": "shoot",
"x": int, "y": int}` – výstřel v aktuálním tiku; `{"by": "timeout"}`.

## Pravidla

`legalActions` vrací prázdné pole: akce jsou spojité, jejich legalitu (strana na tahu, konec
hry) kontroluje `apply` a nelegální akci odmítne chybou.


- `init`: `round = 1`, `tick = 0`, skóre 0, `ammo = magazine`, `reload = 0`, terče kola 1.
- `tick n`: po jednom tiku `n`krát: `tick += 1`; `reload > 0` → `reload −= 1`, při 0 `ammo = magazine`.
  `tick ≥ roundTicks` → nové kolo: `round += 1`, `tick = 0`, `ammo = magazine`, `reload = 0`,
  nové terče; po posledním kole `over = true` (zbylé tiky se zahodí).
- `shoot`: jen při `ammo > 0` a `reload = 0`, jinak akce nic nemění (je legální, UI ji může poslat).
  `ammo −= 1`, `shots += 1`; zásah = první terč v pořadí `i`, který je na poli a
  `(x − tx)² + (y − ty)² ≤ r²`: `hit = true`, `score += body`, `hits += 1`. `ammo = 0` → `reload = reloadTicks`.
- `timeout`: `over = true`.

## AI

Bez soupeře; `aiAction` vrací `tick 1`.

## Výsledek a hvězdy

`{winner, stars, score, shots, hits}`: hvězdy podle `starScores`, `winner = "player"` při ≥ 1★.

## Časový strop

Hra sama trvá 4,5 min; strop 6 min (`minigames.strelnice.time_cap_s`).

## Upřesnění v1 (podle implementace, vektory je pokrývají)

- Vektorový config obsahuje i `kindPct`.
- Když `tick` dosáhne `roundTicks` v posledním kole: `over = true`, `round` a `tick` zůstanou,
  terče se negenerují, `rng` se nevolá; přebíjení v tom tiku ještě proběhne.
- `winner = "ai"` při 0★. `aiAction` vrací `{by: "player", op: "tick", n: 1}`.
- Výstřel s prázdným zásobníkem nebo při přebíjení vrací stav beze změny (legální akce).

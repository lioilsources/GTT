# Šipky 301

**version: 1** · engine `flick` · P0 · vektory `vectors/sipky.json` · kontrakt `specs/minigames/README.md`

## Účel

Jeden leg 301 proti NPC v hospodě (METROPOLE_PLAN 9.5): míření tahem prstu, zaměřovač se kolébá.
Pravidla P0 počítají jen v celých číslech; kolébání zaměřovače a převod gesta na bod je UI (P2).

## Config

`content/tuning.yaml` → `minigames.sipky`; ve vektoru `{start, maxRounds, playerScatter, aiScatter, starDarts}`.

| klíč | význam | default |
|---|---|---|
| `start` | počáteční skóre | 301 |
| `max_rounds` | nejvýš kol (kolo = 3 šipky hráče + 3 šipky AI) | 15 |
| `player_scatter` | rozptyl dopadu hráčovy šipky (jednotky) | 60 |
| `ai_scatter` | rozptyl AI pro úroveň 1–5 | [420, 300, 210, 150, 100] |
| `star_darts` | výhra nejvýš po tolika hráčových šipkách = 3★, 2★ | [18, 27] |

UI: `player_wobble` (amplituda kolébání, jednotky) a `wobble_hz`.

## Terč

Souřadnice v jednotkách 0,1 mm, střed terče (0, 0), osa y nahoru. Kruhy (poloměr² se porovnává
s `r²` dopadu): `r ≤ 64` → 50 · `r ≤ 159` → 25 · `990 ≤ r < 1070` → trojnásobek · `1620 ≤ r < 1700`
→ dvojnásobek · `r ≥ 1700` → 0 (mimo) · jinak jednoduchá hodnota výseče.

Výseče `k = 0…19` mají hodnoty `[20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]`
(od horní po směru hodinových ručiček). Hranice `B[j]` (směr 9° + 18°·j od +y po směru ručiček, ×10⁶):

```
B = [(156434,987688),(453990,891007),(707107,707107),(891007,453990),(987688,156434),
     (987688,-156434),(891007,-453990),(707107,-707107),(453990,-891007),(156434,-987688),
     (-156434,-987688),(-453990,-891007),(-707107,-707107),(-891007,-453990),(-987688,-156434),
     (-987688,156434),(-891007,453990),(-707107,707107),(-453990,891007),(-156434,987688)]
```

Bod `p` leží ve výseči `k`, když `cross(B[k−1 mod 20], p) ≤ 0` a `cross(B[k], p) > 0`,
kde `cross(a, b) = a.x·b.y − a.y·b.x`. Hledá se od `k = 0` výš, bere se první vyhovující.

Středy výsečí `C[k]` (směr 18°·k, ×10⁶) pro míření AI:

```
C = [(0,1000000),(309017,951057),(587785,809017),(809017,587785),(951057,309017),
     (1000000,0),(951057,-309017),(809017,-587785),(587785,-809017),(309017,-951057),
     (0,-1000000),(-309017,-951057),(-587785,-809017),(-809017,-587785),(-951057,-309017),
     (-1000000,0),(-951057,309017),(-809017,587785),(-587785,809017),(-309017,951057)]
```

Bod na výseči `k` v poloměru `r`: `x = rnd(C[k].x · r)`, `y = rnd(C[k].y · r)`,
`rnd(q) = trunc((q + sign(q) · 500000) / 1000000)`.

## Stav

```
{ player, ai, turn, dart, turnStart, playerDarts, round, lastHit, over, rng }
```

`player`, `ai` zbývající skóre; `dart` 0–2 (kolikátá šipka v tahu); `turnStart` skóre strany na tahu
na začátku tahu; `playerDarts` hráčovy hozené šipky; `lastHit = {x, y, points, mult}` posledního
hodu (na začátku nuly).

## Akce

`{"by": strana, "x": int, "y": int}` – bod míření; `{"by": "timeout"}`.

## Pravidla

`legalActions` vrací prázdné pole: akce jsou spojité, jejich legalitu (strana na tahu, konec
hry) kontroluje `apply` a nelegální akci odmítne chybou.


- `init`: obě strany `start`, `turn = "player"`, `dart = 0`, `turnStart = start`, `round = 1`.
- Hod: `s = playerScatter` pro hráče, `aiScatter[level − 1]` pro AI (úroveň nese akce AI v poli
  `level`; hráčova akce `level` nemá). Dopad `x' = x + nextInt(2s + 1) − s`, `y' = y + nextInt(2s + 1) − s`
  (nejdřív x, pak y, z `rng`). Body podle terče; `lastHit = {x', y', points, mult}`
  (`mult` 1/2/3, bull 50 → 2, 25 → 1, mimo → 0). U hráče `playerDarts += 1`.
- `nové = skóre − points`. `nové < 0` → **přehoz**: skóre = `turnStart`, konec tahu.
  `nové = 0` → výhra strany, `over = true`. Jinak skóre = `nové`; po třetí šipce konec tahu.
- Konec tahu: `dart = 0`, tah přejde, `turnStart` = skóre nové strany na tahu. Když tah končí AI,
  `round += 1`; `round > maxRounds` → `over = true`.
- `timeout`: `over = true`.

## AI

Akce AI je `{"by": "ai", "x", "y", "level"}`; ve vektoru jen `{"by": "ai", "level"}` a doplní ji
`aiAction`. Cíl podle zbývajícího skóre `z` (bez náhody, `ai` se nevolá):

1. `z = 50` → bull (0, 0). 2. `z ≤ 20` → výseč hodnoty `z`, poloměr 574 (vnitřní jednoduchá).
3. `z ≤ 40` a sudé → dvojitá výseč `z/2`, poloměr 1660. 4. `z ≤ 60` a dělitelné 3 → trojitá výseč
`z/3`, poloměr 1030. 5. `z ≤ 60` → výseč hodnoty `z − 20` vnitřní jednoduchá (574), je-li 1–20,
jinak trojitá 20. 6. Jinak trojitá 20 (0, 1030).

## Výsledek a hvězdy

`{winner, stars, score, player, ai, playerDarts}`; vítěz podle nuly, po `timeout` nebo `maxRounds`
nižší zbývající skóre, shoda `"draw"`. Hráč vyhrál: `playerDarts ≤ starDarts[0]` → 3★,
`≤ starDarts[1]` → 2★, jinak 1★. `score = start − player`.

## Časový strop

6 min (`minigames.sipky.time_cap_s`).

## Upřesnění v1 (podle implementace, vektory je pokrývají)

- Šipka, která dá přesně nulu, nastaví `over`; `dart` ani `turn` se už nemění.
- Úroveň AI mimo 1–5 se ořízne do rozsahu.
- Hráč, který vyhraje po `timeout` nebo `maxRounds`, dostane hvězdy také podle `starDarts`.

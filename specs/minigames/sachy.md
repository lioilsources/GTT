# Bulvárové šachy

**version: 1** · engine `board` · P0 · vektory `vectors/sachy.json` · kontrakt
`specs/minigames/README.md` · plán: `plans/M6_MOSKVA.md` bod 6 (místní hry) · parita F-080 ·
jen Moskva

## Účel

Šachy na lavičce Gogolova bulváru, ale krátké jako blitz do feedu: Gardnerovy minišachy na desce
5 × 5 se všemi kameny. Hráč hraje bílými a začíná, NPC černými. Bez rošády, bez dvojkroku pěšce
a bez braní mimochodem; pěšec se na poslední řadě promění v dámu.

## Config

`content/tuning.yaml` → `minigames.sachy`; ve vektoru `{aiDepth, aiErrorPct, quietLimit, fastPlies}`.

| klíč | význam | default |
|---|---|---|
| `ai_depth` | hloubka negamaxu v půltazích podle úrovně 1–5 | [1, 1, 2, 3, 4] |
| `ai_error_pct` | šance náhodného tahu | [40, 25, 12, 5, 0] |
| `quiet_limit` | tolik půltahů bez braní a bez tahu pěšcem = remíza | 30 |
| `fast_plies` | výhra do tolika půltahů = 3★ | 40 |
| `time_cap_s`, `ai_think_s` | jen UI | 420, 0,6 |

## Deska a stav

Pole `i = r × 5 + c`, řádek 0 nahoře (strana AI). `board` = řetězec 25 znaků: `.` prázdné,
velká písmena hráč (bílý), malá AI (černý): `K` král, `Q` dáma, `R` věž, `B` střelec, `N` jezdec,
`P` pěšec. Start `"rnbqkppppp.....PPPPPRNBQK"`.

```
{ board, turn, plies, quiet, over, winner, byCount, rng }
```

- `turn` `"player"` | `"ai"`, start `"player"`; `plies` = odehrané půltahy; `quiet` = půltahy od
  posledního braní nebo tahu pěšcem; `winner` `""` | `"player"` | `"ai"` | `"draw"`.
- `rng = Prng(seed).state` (pravidla ho nepoužívají).

## Akce

- `{"by": strana, "from": i, "to": j}` – tah strany na tahu.
- `{"by": "timeout"}` – kdykoli před koncem.
- `legalActions`: legální tahy strany na tahu vzestupně podle `from`, pak `to`.

## Pravidla

- Pohyby: král o 1 pole v 8 směrech; věž po řádku a sloupci, střelec po úhlopříčkách, dáma obojí
  (klouzají přes prázdná pole, zastaví se na prvním obsazeném, soupeřův kámen berou); jezdec skokem
  (±1, ±2) a (±2, ±1). Pěšec hráče jde na `r − 1`, pěšec AI na `r + 1`: o jedno pole vpřed na
  prázdné, šikmo vpřed jen braním. Pěšec na řádku 0 (hráč) nebo 4 (AI) se promění v dámu.
- Tah je legální, když po něm vlastní král není napaden (pseudolegální tahy filtrované šachem).
- Po tahu `plies += 1`; `quiet = 0` při braní nebo tahu pěšcem, jinak `quiet += 1`. Tah přejde.
- **Konec** (kontrola po každém tahu, pro stranu nově na tahu): nemá legální tah → při šachu
  vyhrává táhnoucí (mat), jinak `"draw"` (pat); jinak na desce zbyli jen dva králové, nebo
  `quiet ≥ quietLimit` → `"draw"`.
- `timeout`: rozhoduje materiál (P 1, N 3, B 3, R 5, Q 9, K 0), víc vyhrává, shoda `"draw"`;
  `byCount = true`.

## AI

`depth = aiDepth[level−1]`, `err = aiErrorPct[level−1]` (úroveň oříznutá na 1–5).

1. `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len)]`.
2. Jinak negamax s alfa-beta nad `legalActions` v jejich pořadí; z kořene se volí první tah
   s nejvyšší hodnotou (ostré `>`), alfa kořene roste, beta kořene `+∞`.

Uzel (strana `s` na tahu, zbývá `d`): nejdřív legální tahy; žádný → v šachu `−(100000 + d)`, jinak
0; dva králové nebo `quiet ≥ quietLimit` → 0; `d = 0` → hodnocení; jinak
`max(−uzel(syn, d − 1))` s řezem `alpha ≥ beta`. Hodnocení z pohledu `s`: součet
`(materiál × 100 + postup pěšce × 10)` vlastních kamenů minus soupeřových; postup pěšce hráče
`= 4 − r`, AI `= r`, ostatní kameny 0. `+∞ = 2³⁰`.

## Výsledek a hvězdy

`{winner, stars, score, byCount, player, ai, plies}` (`player`, `ai` = materiál). Výhra na
`timeout` → 1★; jinak `plies ≤ fastPlies` → 3★, jinak 2★. Remíza a prohra 0★.
`score = player × 10`.

## UI

- Deska 5 × 5 přes šířku telefonu, figury jako šachové glyfy (bez textu), poslední tah zvýrazněný.
- Klepnutí na vlastní kámen ukáže tečky legálních cílů, klepnutí na cíl táhne; jinam zruší výběr.
- Nahoře materiál (`sachyMaterial`), při šachu krátce `sachyCheck`.
- Pauza a vzdání podle kontraktu.

## Hraniční případy

- Tah, po kterém by vlastní král zůstal v šachu (i vázaný kámen), je nelegální.
- Mat i pat se poznají hned po tahu; AI nikdy nedostane stav bez tahu.
- Proměněná dáma se počítá jako dáma v materiálu i hodnocení.

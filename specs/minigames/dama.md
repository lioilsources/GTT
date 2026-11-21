# Dáma

**version: 1** · engine `board` · P0 · vektory `vectors/dama.json` · kontrakt `specs/minigames/README.md`

## Účel

Česká dáma 8×8 proti NPC (METROPOLE_PLAN 9.5): povinné braní, dálková dáma, strop 8 min,
pak rozhoduje materiál.

## Config

`content/tuning.yaml` → `minigames.dama`; ve vektoru `{aiDepth, aiErrorPct, quietLimit, fastPlies}`.

| klíč | význam | default |
|---|---|---|
| `ai_depth` | hloubka minimaxu v půltazích pro úroveň 1–5 | [1, 2, 3, 4, 5] |
| `ai_error_pct` | šance, že AI zahraje náhodný legální tah | [35, 20, 10, 5, 0] |
| `quiet_limit` | remíza po tolika půltazích bez braní a bez tahu kamenem | 50 |
| `fast_plies` | výhra do tolika půltazích = rychlá výhra | 80 |

## Deska

32 tmavých polí, index 0–31 po řádcích shora (řádek `r = i div 4`, 0 = strana AI). Pole `i` má
sloupec `c = 2·(i mod 4) + (1 − r mod 2)`. Sousední pole se hledají přes (r, c).

`board` je řetězec 32 znaků: `.` prázdné, `w` kámen hráče, `W` dáma hráče, `b` kámen AI, `B` dáma AI.
Start: pole 0–11 `b`, 20–31 `w`, zbytek `.`. Hráč (bílý, dole) táhne první a jde nahoru (r klesá).

## Stav

```
{ board, turn, plies, quiet, over, winner, byMaterial, rng }
```

`turn`: `"player"`|`"ai"`; `plies` odehrané půltahy; `quiet` půltahy od posledního braní nebo tahu
kamenem; `winner`: `""` za hry, pak `"player"`|`"ai"`|`"draw"`; `byMaterial`: konec na materiál.

## Akce

`{"by": strana, "path": [z, na, …]}` – cesta po polích; u braní každé další pole je dopad po
přeskočení soupeřova kusu. `{"by": "timeout"}`.

## Pravidla

- **Kámen** táhne o jedno pole šikmo dopředu; bere skokem šikmo **jen dopředu** přes soupeřův kus
  na prázdné pole hned za ním.
- **Dáma** táhne o libovolný počet volných polí šikmo; bere přes jediný soupeřův kus na libovolném
  diagonále (pole mezi ní a kusem volná) a dopadne na kterékoli volné pole hned za ním v tom směru.
- **Braní je povinné.** Když může brát kterýkoli kus, legální jsou jen tahy s braním. Skok musí
  pokračovat, dokud jde brát; legální jsou jen úplné cesty. Přednost dámy ani počtu se neuplatňuje.
- Přeskočené kusy zůstávají na desce do konce tahu (nejdou přeskočit znovu a blokují), pak zmizí.
- **Proměna:** kámen, který tah skončí na poslední řadě soupeře (hráč řádek 0, AI řádek 7), se změní
  v dámu. Projde-li poslední řadou jen během skoku, nemění se.
- Po tahu: `plies += 1`; `quiet = 0` při braní nebo tahu kamenem, jinak `quiet += 1`; tah přejde.
- **Konec:** strana na tahu nemá legální tah → prohrává. `quiet ≥ quietLimit` → `"draw"`.
- `timeout`: rozhodne materiál (kámen 1, dáma 3): víc vyhrává, shoda `"draw"`; `byMaterial = true`.

**Pořadí `legalActions`:** podle `path` lexikograficky (čísla polí vzestupně).

## AI

`level` 1–5: `depth = aiDepth[level−1]`, `err = aiErrorPct[level−1]`.

1. `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len(legal))]`.
2. Jinak negamax s alfa-beta do `depth` půltahů nad `legalActions`; list = hodnocení z pohledu
   strany na tahu: `100 × (vlastní kameny − soupeřovy) + 300 × (vlastní dámy − soupeřovy)`;
   strana bez tahu = −100000 (+ zbývající hloubka, aby se preferovala rychlejší výhra).
   Remízový uzel (`quiet ≥ quietLimit`) = 0. Při shodě první tah v pořadí `legalActions`.

## Výsledek a hvězdy

`{winner, stars, score, byMaterial, plies}`. Hráč vyhrál: na materiál → 1★; jinak `plies ≤
fastPlies` → 3★ (rychlá výhra, náhrada „do 4 min“ z plánu, protože pravidla neznají čas), jinak 2★.
Remíza i prohra 0★. `score = 100 × (počet AI kusů sebraných hráčem)` (12 − AI kusů na desce).

## Časový strop

8 min (`minigames.dama.time_cap_s`), pak `timeout`.

## Hraniční případy

- Dáma s braním přes více směrů: každá větev je samostatná cesta.
- Kámen, který se v cestě dostane na poslední řadu, pokračuje v braní jako kámen (dopředu).

## Upřesnění v1 (podle implementace, vektory je pokrývají)

- Strana bez tahu má v hledání hodnotu `−(100000 + zbývající hloubka)`, aby AI dávala přednost rychlejší výhře.
- Konec se kontroluje v pořadí: strana na tahu nemá tah → prohra; pak `quiet ≥ quietLimit` → remíza.
  V hledání se konec kontroluje před řezem v hloubce 0.
- Tah, který hru ukončí, předá `turn` poražené straně.
- Během braní je výchozí pole táhnoucího kusu prázdné (dáma jím smí projet).
- Kámen, který projde poslední řadou během skoku, dál brát nemůže (bere jen dopředu); případ z „Hraničních
  případů“ proto nenastane.

# Lodě

**version: 1** · engine `board` · P0 · vektory `vectors/lode.json` · kontrakt `specs/minigames/README.md`

## Účel

Námořní bitva 10×10 proti NPC (M2 bod 9, dávka A). Flotily rozmístí náhoda (hráč může
přerozmístit, než poprvé vystřelí), pak se střílí; zásah = střílí znovu.

## Config

`content/tuning.yaml` → `minigames.lode`; ve vektoru `{fleet, shuffles, aiErrorPct, fastShots, okShots}`.

| klíč | význam | default |
|---|---|---|
| `fleet` | délky lodí v pořadí rozmisťování | [5, 4, 3, 3, 2] |
| `shuffles` | kolikrát smí hráč flotilu přerozmístit | 3 |
| `ai_error_pct` | šance zcela náhodného výstřelu AI | [50, 30, 15, 5, 0] |
| `fast_shots` | výhra do tolika výstřelů hráče = 3★ | 45 |
| `ok_shots` | výhra do tolika = 2★, jinak 1★ | 70 |
| `time_cap_s` | časový strop (UI) | 480 |

## Pole a rozmístění

Pole `i = y × 10 + x`. Rozmístění jedné flotily: pro každou loď v pořadí `fleet` opakuj:
`dir = rng.nextInt(2)` (0 vodorovně), `x = rng.nextInt(dir = 0 ? 11 − len : 10)`,
`y = rng.nextInt(dir = 1 ? 11 − len : 10)`; pole lodi od `(x, y)` doprava nebo dolů. Loď se
položí, když žádné její pole není loď ani s lodí nesousedí (i šikmo); jinak další pokus.
`init`: `rng = Prng(seed)`, nejdřív flotila hráče, pak flotila AI.

## Stav

```
{ pShips, aShips, pShots, aShots, turn, shots, shuffles, over, winner, rng }
```

`pShips`, `aShips`: seznam lodí, loď = pole polí vzestupně. `pShots` = 100 znaků výstřelů AI na
desku hráče, `aShots` = výstřely hráče na desku AI: `.` nestříleno, `o` voda, `x` zásah.
`shots` = výstřely hráče, `shuffles` = zbývající přerozmístění.

## Akce

- `{"by": "player", "op": "shuffle"}` – nové rozmístění flotily hráče (stejný postup z `rng`);
  legální jen když `shots = 0`, `shuffles > 0` a hráč je na tahu; `shuffles −= 1`.
- `{"by": strana, "op": "shot", "cell": i}` – výstřel na nestřílené pole soupeřovy desky.
- `{"by": "timeout"}`.

`legalActions`: hráč `shuffle` (když legální) a pak výstřely vzestupně; AI výstřely vzestupně.

## Pravidla

- Výstřel hráče `shots += 1`. Zásah → `x`, střílí znovu; voda → `o`, tah přejde.
- Loď je potopená, když jsou zasažena všechna její pole. Všechny soupeřovy lodě potopené → výhra.
- `timeout` → vyhrává strana s víc zásahy, shoda `"draw"`.

## AI

`err = aiErrorPct[level−1]`. Nestřílená pole desky hráče = `volná`.

1. `r = ai.nextInt(100)`; `r < err` → `volná[ai.nextInt(len)]` (vzestupně).
2. **Cíl:** zásahy na nepotopených lodích. Když jsou aspoň dva v jedné řadě nebo sloupci,
   kandidáti = volná pole, která tu řadu prodlužují na obou koncích; jinak volní ortogonální
   sousedé všech takových zásahů. Kandidáti vzestupně, bez duplicit, výběr
   `kandidáti[ai.nextInt(len)]`.
3. **Hledání** (bez cílů): úroveň ≥ 3 – volná pole s `(x + y) mod 2 = 0`, prázdné → všechna volná;
   úroveň 1–2 – všechna volná. Úroveň ≥ 4 navíc vyřadí pole sousedící (i šikmo) s potopenou lodí
   (když tím nezůstane prázdno). Výběr `ai.nextInt(len)`.

AI ví o potopení jen to, co by viděl hráč (potopená loď se v UI odhalí).

## Výsledek a hvězdy

`{winner, stars, score, shots}`. Výhra: `shots ≤ fastShots` → 3★, `≤ okShots` → 2★, jinak 1★.
Prohra, remíza 0★. `score = max(0, 1000 − 10 × shots)` při výhře, jinak 0.

## UI

Nahoře soupeřova deska (klepnutí = výstřel), dole menší vlastní. Před prvním výstřelem tlačítko
„Přerozmístit“ s počtem zbývajících. Potopená loď se obtáhne.

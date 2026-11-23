# Mlýn

**version: 1** · engine `board` · P0 · vektory `vectors/mlyn.json` · kontrakt `specs/minigames/README.md`

## Účel

Mlýn (devět kamenů) proti NPC (M2 bod 9, dávka A): kladení, posun a skákání, mlýn bere soupeři
kámen. Hráč (`w`) začíná.

## Config

`content/tuning.yaml` → `minigames.mlyn`; ve vektoru `{aiDepth, aiErrorPct, quietLimit, flying, star3Pieces}`.

| klíč | význam | default |
|---|---|---|
| `ai_depth` | hloubka negamaxu v půltazích | [1, 2, 2, 3, 4] |
| `ai_error_pct` | šance náhodného tahu | [35, 20, 10, 5, 0] |
| `quiet_limit` | remíza po tolika půltazích fáze posunu bez mlýna | 50 |
| `flying` | strana se 3 kameny smí skákat | true |
| `star3_pieces` | výhra s aspoň tolika vlastními kameny na desce = 3★ | 6 |
| `time_cap_s` | časový strop (UI) | 480 |

## Deska

24 bodů: 0 1 2 vnější horní řada, 3 4 5 prostřední horní, 6 7 8 vnitřní horní, 9 10 11 levá
střední řada (vnější, prostřední, vnitřní), 12 13 14 pravá (vnitřní, prostřední, vnější), 15 16 17
vnitřní dolní, 18 19 20 prostřední dolní, 21 22 23 vnější dolní.

Mlýny (pořadí je součást specifikace): `[0,1,2] [3,4,5] [6,7,8] [9,10,11] [12,13,14] [15,16,17]
[18,19,20] [21,22,23] [0,9,21] [3,10,18] [6,11,15] [1,4,7] [16,19,22] [8,12,17] [5,13,20] [2,14,23]`.
Body jsou sousední, když leží za sebou v jednom mlýně (`m[0]–m[1]`, `m[1]–m[2]`).

## Stav

```
{ board, hand: {player, ai}, turn, plies, quiet, over, winner, byPieces, rng }
```

`board` řetězec 24 znaků `.`, `w` (hráč), `b` (AI). `hand` = kameny ke kladení (start 9 a 9).
`quiet` = půltahy od posledního mlýna, počítá se jen ve fázi posunu (obě `hand` = 0).

## Akce

`{"by": strana, "from": f, "to": t, "remove": r}`:
- **kladení** (`hand` strany > 0): `from = −1`, `to` prázdný bod;
- **posun** (`hand` = 0): `from` vlastní kámen, `to` prázdný sousední bod; má-li strana 3 kameny
  na desce a `flying`, `to` libovolný prázdný bod;
- `remove`: když tah uzavře nový mlýn (`to` leží v mlýně, jehož všechny body jsou po tahu kameny
  táhnoucího), bod soupeřova kamene k odebrání, jinak `−1`. Odebrat jde kámen mimo mlýn; jsou-li
  všechny soupeřovy kameny v mlýnech, jakýkoli. Uzavře-li tah dva mlýny najednou, bere se jeden kámen.
- `{"by": "timeout"}`.

`legalActions`: seřazené podle `(from, to, remove)` vzestupně.

## Pravidla

- Po tahu: kladení `hand −= 1`; `plies += 1`; mlýn → `quiet = 0`, jinak ve fázi posunu `quiet += 1`.
- **Konec** (kontrola po tahu, pro stranu, která je teď na tahu): má-li po skončení kladení
  (`hand = 0`) méně než 3 kameny, nebo nemá legální tah → prohrává. Jinak `quiet ≥ quietLimit` →
  `"draw"`.
- `timeout`: víc kamenů (deska + ruka) vyhrává, shoda `"draw"`; `byPieces = true`.

## AI

`depth = aiDepth[level−1]`, `err = aiErrorPct[level−1]`.

1. `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len)]`.
2. Jinak negamax s alfa-beta do `depth` nad `legalActions`; prohraný uzel `−(100000 + zbývající
   hloubka)`, remíza 0; list z pohledu strany na tahu:
   `100 × (vlastní kameny na desce + v ruce − soupeřovy) + 10 × (vlastní uzavřené mlýny − soupeřovy)
   + (počet vlastních legálních posunů − soupeřových)` (posuny se počítají jen ve fázi posunu, jinak 0).
   Shoda: první v pořadí.

## Výsledek a hvězdy

`{winner, stars, score, byPieces, plies}`. Výhra: na kameny → 1★; jinak vlastních kamenů na
desce ≥ `star3Pieces` → 3★, jinak 2★. Remíza, prohra 0★. `score = 100 × (9 − kameny AI na desce
a v ruce)`.

## UI

Kladení klepnutím na bod; posun klepnutím na kámen a pak na cíl; po mlýnu desku přebarví a hráč
klepne na kámen soupeře k odebrání (UI složí jednu akci). Počty kamenů v ruce u okraje.

## Upřesnění v1

- `quiet += 1` jen u posunu (`from ≥ 0`) bez mlýna; kladení `quiet` nemění.
- Uzavře-li tah mlýn a soupeř nemá na desce žádný kámen, je jediná akce s `remove = −1`.
- „Nemá legální tah“ ve fázi kladení = žádný prázdný bod (prakticky nenastane).
- Uzel negamaxu: nejdřív prohra strany na tahu, pak `quiet ≥ quietLimit` (0), pak list; `apply`
  po tahu kontroluje ve stejném pořadí.
- „Počet legálních posunů“ v hodnocení = počet dvojic `(from, to)` včetně skoků (bez variant
  `remove`), jen když jsou obě `hand` = 0.
- `score = 100 × (9 − kameny AI na desce a v ruce)` platí pro každý výsledek, i prohru.

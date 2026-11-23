# Prší

**version: 1** · engine `cards` · P0 · vektory `vectors/prsi.json` · kontrakt `specs/minigames/README.md`

## Účel

Česká karetní hra s mariášovými kartami (M2 bod 9, dávka B; METROPOLE_PLAN 9.5 č. 2) proti
jednomu NPC, o body (R11). Kdo se první zbaví karet, vyhrál kolo; kdo první vyhraje
`roundsToWin` kol, vyhrál partii.

## Config

`content/tuning.yaml` → `minigames.prsi`; ve vektoru `{hand, roundsToWin, aiErrorPct}`.

| klíč | význam | default |
|---|---|---|
| `hand` | karet do ruky při rozdání | 4 |
| `rounds_to_win` | vyhraných kol na vítězství | 3 |
| `ai_error_pct` | šance náhodného tahu AI, úroveň 1–5 | [40, 25, 12, 5, 0] |
| `time_cap_s` | časový strop (UI) | 360 |
| `ai_think_s` | pauza před tahem AI (jen UI) | 0.7 |

## Karty

32 karet, karta je číslo 0–31: `suit = c div 8` (0 červené, 1 zelené, 2 kule, 3 žaludy),
`rank = c mod 8` (0 = 7, 1 = 8, 2 = 9, 3 = 10, 4 = spodek, 5 = svršek, 6 = král, 7 = eso).
Zvláštní karty: **sedma** (`rank 0`), **svršek** (`rank 5`, mění barvu), **eso** (`rank 7`).

## Stav

```
{ deck, player, ai, pile, suit, sevens, ace, turn, starter, round, playerWins, aiWins,
  last, over, rng }
```

- `deck`: dobírací balík, líže se `deck[0]`. `player`, `ai`: karty v ruce v pořadí lízání
  (nová karta na konec). `pile`: odkládací balík, vrchní karta = poslední prvek.
- `suit`: platná barva (0–3) – barva vrchní karty, po svrškovi zvolená barva.
- `sevens`: počet sedem v řadě, které ještě nikdo nevzal (0–4); strana na tahu lízne `2 × sevens`.
- `ace`: vrchní eso ještě platí (strana na tahu stojí, nebo přebije esem).
- `turn`: `"player"` | `"ai"`; `starter`: kdo začal kolo; `round` od 1.
- `last`: `""` | `"player"` | `"ai"` – vítěz posledního dohraného kola (pro UI).

## Akce

- `{"by": strana, "op": "play", "card": c, "suit": s}` – vyložení; `s` je zvolená barva u svrška
  (0–3), u ostatních karet `−1`.
- `{"by": strana, "op": "draw"}` – líznutí (jedna karta, nebo trest za sedmy).
- `{"by": strana, "op": "stand"}` – stání na eso.
- `{"by": "timeout"}`.

## Pravidla

**Líznutí karty:** je-li `deck` prázdný, vezme se `pile` bez vrchní karty, zamíchá se
`shuffle` z `rng` a stane se z něj `deck`; `pile = [vrchní]`. Je-li i pak prázdný, karta se
nelízne (líznutí víc karet skončí dřív).

**Rozdání kola** (`init`, a po dohraném kole, dokud není konec): `deck = shuffle([0..31])` z `rng`;
`player = []`, `ai = []`; `hand`krát lízne hráč a pak AI (střídavě, hráč první); pak se z `deck[0]`
otočí karta na `pile` (`pile = [ta karta]`), `suit` = její barva, `sevens` = 1, je-li sedma, jinak 0,
`ace` = je-li eso. Otočený svršek barvu nemění (`suit` = jeho barva). `starter` = `"player"`
v lichých kolech, `"ai"` v sudých; `turn = starter`. `init`: `round = 1`, `playerWins = aiWins = 0`,
`last = ""`, `rng = Prng(seed).state`.

**`legalActions`** (strana na tahu, ruka v pořadí `card` vzestupně):
- `sevens > 0`: každá sedma v ruce (`suit −1`), pak `draw`.
- jinak `ace`: každé eso v ruce, pak `stand`.
- jinak: každá karta, kde `rank` = `rank` vrchní karty nebo `suit` karty = `suit`, a každý svršek
  (svršek jde na cokoli); svršek se rozvine na 4 akce se `suit` 0, 1, 2, 3; pak `draw`.
  Pořadí: podle `card` vzestupně, u svrška podle `suit`; `draw` poslední.

**Účinek:**
- `play`: karta z ruky (první výskyt) na konec `pile`. `suit` = zvolená barva u svrška, jinak barva
  karty. Sedma → `sevens += 1`, `ace = false`; eso → `ace = true`, `sevens = 0`; jiná karta →
  `sevens = 0`, `ace = false`. Je-li ruka prázdná, **kolo končí** (vyhrála strana na tahu). Jinak
  tah přejde.
- `draw`: `sevens > 0` → lízne `2 × sevens` karet, `sevens = 0`; jinak lízne 1 kartu. Tah přejde.
- `stand`: `ace = false`, tah přejde.

**Konec kola:** vítěz `wins += 1`, `last` = vítěz. Dosáhne-li `roundsToWin`, `over = true` (ruce
a `pile` zůstanou). Jinak `round += 1` a nové rozdání.

- `timeout`: `over = true`.

## AI

`err = aiErrorPct[level−1]`. `r = ai.nextInt(100)` se losuje u **každého** tahu AI, i když je
legální jediná akce. `r < err` → `legal[ai.nextInt(len)]`. Jinak akce s nejvyšším hodnocením
(shoda → první v pořadí `legalActions`). `h` = ruka AI po vyložení, `opp` = počet karet hráče.

- `draw`, `stand`: 0.
- svršek: `50 + 10 × (počet karet barvy suit v h)`.
- sedma: `100 + (úroveň ≥ 3 a opp ≤ 2 ? 30 : 0)`.
- eso: `100 + (úroveň ≥ 3 a opp ≤ 2 ? 20 : 0)`.
- jiná karta: `100 + 5 × (počet karet stejné barvy v h)`.

## Výsledek a hvězdy

`{winner, stars, score, playerWins, aiWins}`. `winner`: víc vyhraných kol, shoda (jen po
`timeout`) `"draw"`. Hráč vyhrál: `aiWins = 0` → 3★, `aiWins = 1` → 2★, jinak 1★; jinak 0★.
`score = 100 × playerWins`.

## UI

Karty hráče dole, AI jen rubem s počtem, uprostřed balík a vrchní karta s ikonou platné barvy.
Klepnutí na kartu = vyložení; svršek otevře výběr barvy (4 tlačítka). Tlačítko „Líznout“
(`prsiDraw`, při sedmách `prsiDrawN`) nebo „Stojím“ (`prsiStand`). Karty kreslí klient
stejně jako u Oko bere (barvy jen z existujících tokenů), mariášové barvy jako jednoduché symboly
(srdce, list, kule, žalud), hodnoty textem (7, 8, 9, 10, `prsiJack` spodek, `prsiQueen` svršek,
`prsiKing` král, `prsiAce` eso).

## Hraniční případy

- Svršek se smí dát i na svrška; na sedmu nebo platné eso ne (jen sedma, resp. eso).
- Poslední karta sedma nebo eso ukončí kolo; trest už se neplní.
- Všechny karty v rukou a `pile` o jedné kartě: líznutí nic nepřidá, tah přesto přejde.
- Otočená sedma při rozdání trestá stranu, která začíná; otočené eso ji nechá stát.

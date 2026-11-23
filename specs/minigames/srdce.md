# Srdce

**version: 1** · engine `cards` · P0 · vektory `vectors/srdce.json` · kontrakt `specs/minigames/README.md`

## Účel

Zdvihová hra pro čtyři (hearts; M2 bod 9, dávka B; METROPOLE_PLAN 9.5 č. 4): hráč a tři NPC.
Kdo bere srdce a pikovou dámu, dostává trestné body; vyhrává nejméně bodů. Bez přehazování
karet na začátku rozdání (v1).

## Config

`content/tuning.yaml` → `minigames.srdce`; ve vektoru `{target, maxDeals, aiErrorPct, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `target` | partie končí po rozdání, kde má někdo aspoň tolik bodů | 50 |
| `max_deals` | nejvýš rozdání | 3 |
| `ai_error_pct` | šance náhodné karty AI, úroveň 1–5 | [40, 25, 12, 5, 0] |
| `star_margins` | náskok (nejlepší AI − hráč) pro 3★ a 2★ | [15, 5] |
| `time_cap_s` | časový strop (UI) | 540 |
| `ai_think_s` | pauza před kartou AI (jen UI) | 0.5 |

## Karty a místa

Karta 0–51 jako u Oko bere: `rank = c mod 13` (0 = 2 … 12 = eso), `suit = c div 13`
(0 ♠, 1 ♥, 2 ♦, 3 ♣). **Křížová dvojka** = 39, **piková dáma** = 10. Body karty: srdce 1,
piková dáma 13, ostatní 0. Místa 0–3: 0 = hráč (dole), 1 vlevo, 2 naproti, 3 vpravo; hraje se
v pořadí 0 → 1 → 2 → 3 → 0.

## Stav

```
{ hands, trick, leader, turn, taken, scores, deal, tricks, broken, lastTrick, over, rng }
```

- `hands`: 4 pole karet seřazená vzestupně. `trick`: karty rozehraného zdvihu v pořadí
  vynesení (vynesl `leader`).
- `taken`: trestné body v rozdání po místech; `scores`: součty z dohraných rozdání.
- `deal` od 1, `tricks` dohraných zdvihů v rozdání (0–13), `broken`: srdce už padlo.
- `lastTrick`: `{cards: [4 karty v pořadí vynesení], leader, winner}`, na začátku
  `{cards: [], leader: −1, winner: −1}`.

## Akce

`{"by": "player"|"ai", "card": c}` – karta místa `turn` (hráč na místě 0, AI na místech 1–3);
`{"by": "timeout"}`. `legalActions`: legální karty vzestupně.

## Pravidla

**Rozdání:** `deck = shuffle([0..51])` z `rng`, karta `deck[i]` jde místu `i mod 4`, ruce se
seřadí. `taken = [0,0,0,0]`, `trick = []`, `tricks = 0`, `broken = false`, `leader = turn` =
místo s křížovou dvojkou. `init`: `deal = 1`, `scores = [0,0,0,0]`, rozdání.

**Legální karty:**
- První zdvih rozdání, vynáší se: jen křížová dvojka.
- Vynáší se (jinak): cokoli, ale srdce jen když `broken`, nebo ruka má jen srdce.
- Přiznává se: má-li ruka barvu vynesené karty, jen tu barvu.
- Nemá-li barvu: cokoli; v prvním zdvihu rozdání ale ne srdce ani pikovou dámu, pokud ruka má
  i jinou kartu.

**Zahrání:** karta z ruky na konec `trick`; srdce → `broken = true`. Mají-li všichni 4 kartu:
vítěz = místo s nejvyšší kartou barvy vynesené karty; `taken[vítěz] +=` body karet,
`lastTrick = {cards: trick, leader, winner}`, `trick = []`, `tricks += 1`, `leader = turn = vítěz`.
Jinak `turn = (turn + 1) mod 4`.

**Konec rozdání** (po 13. zdvihu, ve stejném `apply`): má-li jedno místo `taken = 26`
(„trefil měsíc“), dostanou ostatní po 26 a ono 0; jinak `scores += taken`. Pak má-li někdo
`scores ≥ target` nebo `deal = maxDeals`, `over = true` (ruce prázdné, `trick = []`). Jinak
`deal += 1` a nové rozdání.

- `timeout`: `over = true`; hodnotí se `scores` (rozehrané rozdání se nepočítá).

## AI

`err = aiErrorPct[level−1]`; `r = ai.nextInt(100)` u **každé** karty AI, i když je legální
jediná. `r < err` → `legal[ai.nextInt(len)]`. Jinak karta s nejvyšším hodnocením (shoda →
první v pořadí). `rank` = rank karty, `w` = nejvyšší rank barvy vynesené karty ve zdvihu,
`pts` = body karet ve zdvihu, `lastSeat` = zdvih už má 3 karty.

- **Vynáší:** `−rank − (srdce ? 5 : 0)`.
- **Přiznává** (karta má vynesenou barvu): úroveň ≤ 2 → `−rank`. Úroveň ≥ 3:
  `rank < w` → `1000 + rank`; jinak piková dáma → `−1000`; jinak `lastSeat` a `pts = 0` →
  `500 + rank`; jinak `100 − rank`.
- **Shazuje** (nemá barvu): úroveň ≤ 2 → `rank`. Úroveň ≥ 3: piková dáma `3000`, srdce
  `2000 + rank`, jinak `1000 + rank`.

## Výsledek a hvězdy

`{winner, stars, score, scores}`. `best` = nejmenší `scores` ze tří AI. `scores[0] < best` →
`"player"`, `=` → `"draw"`, jinak `"ai"`. Hráč vyhrál: `best − scores[0] ≥ starMargins[0]` → 3★,
`≥ starMargins[1]` → 2★, jinak 1★; jinak 0★. `score = max(0, 100 − scores[0])`.

## UI

Ruka hráče dole jako vějíř (nelegální karty ztlumené), soupeři jen rubem s počtem bodů
(`srdcePoints`), zdvih uprostřed; dohraný zdvih zůstane chvíli vidět (`lastTrick`) a odjede
k vítězi. Po rozdání tabulka bodů (`srdceDeal`). Jména soupeřů `srdceWest`, `srdceNorth`,
`srdceEast`.

## Hraniční případy

- Měsíc se počítá i hráči (ostatní +26).
- Shoda nejmenších bodů hráče s AI = remíza, 0★.
- `scores` po rozdání může překročit `target` u víc míst; konec je stejný.
- Nové rozdání `lastTrick` nemění (UI ještě ukáže poslední zdvih předchozího rozdání).
- Zdvih s pikovou dámou a srdci: body se sečtou (dáma 13 + srdce).

## Upřesnění v1

- Konec partie: `taken` zůstane z posledního rozdání, `tricks = 13`, `leader = turn` = vítěz
  posledního zdvihu, `deal` beze změny. Konec rozdáním: `deal ≥ maxDeals`.
- „Jiná karta“ v prvním zdvihu = karta za 0 bodů. Ruka bez křížů jen ze srdcí a pikové dámy z
  náhodného rozdání prakticky nevznikne; vektor tuto větev nepokrývá (je v unit testu).
- AI: `w` a `pts` se počítají ze zdvihu před kartou AI, `lastSeat` = zdvih má před ní 3 karty.
- `by` musí odpovídat místu na tahu: `"player"` na místě 0, `"ai"` na 1–3.
- `timeout` mění jen `over`.

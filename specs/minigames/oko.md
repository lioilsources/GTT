# Oko bere

**version: 1** · engine `cards` · P0 · vektory `vectors/oko.json` · kontrakt `specs/minigames/README.md`

## Účel

Karetní hra proti bankéři (METROPOLE_PLAN 9.5): líznout, nebo stát; bankéř stojí na 17; bez sázek
a bez dělení (R11: hraje se o body). Kdo první vyhraje 5 kol, vyhrál.

## Config

`content/tuning.yaml` → `minigames.oko`; ve vektoru `{roundsToWin, dealerStand}`.

| klíč | význam | default |
|---|---|---|
| `rounds_to_win` | vyhraných kol na vítězství | 5 |
| `dealer_stand` | bankéř stojí od tohoto součtu (i měkkého) | 17 |

## Karty

Karta je číslo 0–51: `rank = c mod 13` (0 = 2, …, 8 = 10, 9 = J, 10 = Q, 11 = K, 12 = A),
`suit = c div 13` (0 ♠, 1 ♥, 2 ♦, 3 ♣). Hodnota: 2–10 podle čísla, J/Q/K = 10, A = 11 nebo 1.
**Součet ruky:** sečti esa jako 11, pak dokud je součet nad 21 a zbývá eso za 11, odečti 10.
**Oko** = 21 ze dvou karet.

## Stav

```
{ deck, player, dealer, playerWins, dealerWins, round, phase, last, over, rng }
```

- `deck`: zbylé karty v pořadí lízání (líže se `deck[0]`), `player`, `dealer`: karty v ruce.
- `phase`: `"play"` (hráč na tahu) nebo `"over"`.
- `last`: výsledek posledního dohraného kola pro UI:
  `{player: [...], dealer: [...], outcome: "win"|"lose"|"push"|""}` (na začátku prázdná pole a `""`).

## Akce

`{"by": "player", "op": "hit"|"stand"}`, `{"by": "timeout"}`. Bankéř nemá rozhodnutí; jeho tahy
proběhnou uvnitř `apply`. `legalActions` ve fázi `play`: `[hit, stand]`; jinak prázdné.

## Pravidla

**Rozdání kola** (v `init` a po každém dohraném kole, dokud není konec):
`deck = shuffle([0..51])` z `rng`, pak lízne hráč, bankéř, hráč, bankéř; `phase = "play"`.
Ihned po rozdání se kontroluje oko: obě strany oko → `push`; jen hráč → `win`; jen bankéř → `lose`.
Rozhodnuté kolo se hned vyhodnotí (viz níže) a případně se rozdá další.

- `hit`: hráč lízne. Součet > 21 → `lose`. Součet = 21 → automaticky `stand`.
- `stand`: bankéř líže, dokud má součet < `dealerStand`. Pak: bankéř > 21 → `win`;
  jinak vyšší součet vyhrává, shoda → `push`.

**Vyhodnocení kola:** `win` → `playerWins += 1`, `lose` → `dealerWins += 1`, `push` nic.
`last = {player, dealer, outcome}` (ruce v okamžiku konce kola). Dosáhne-li některá strana
`roundsToWin`, `over = true`, `phase = "over"` a ruce zůstanou. Jinak `round += 1` a nové rozdání.

- `timeout`: `over = true`, `phase = "over"`.

## AI

Bankéř hraje podle pravidla výše; obtížnost hru nemění. `aiAction` vrací první legální akci
(kontrakt ho vyžaduje, hra ho nevolá).

## Výsledek a hvězdy

`{winner, stars, score, playerWins, dealerWins}`; `winner`: víc vyhraných kol, shoda (jen po
`timeout`) `"draw"`. Hvězdy jako Sirky: hráč vyhrál a bankéř má ≤ 2 → 3; 3 → 2; 4 → 1; jinak 0.
`score = 100 × playerWins`.

## Časový strop

7 min (`minigames.oko.time_cap_s`).

## Hraniční případy

- Balíček na kolo stačí vždy (nejvýš 21 karet na kolo).
- Eso se přepočítá z 11 na 1 i opakovaně (A+A+9 = 21).
- Bankéř dolízá i při měkké 16 (A+5) a stojí na měkké 17.

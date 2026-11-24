# Durak

**version: 1** · engine `cards` · P0 · vektory `vectors/durak.json` · kontrakt
`specs/minigames/README.md` · plán: `plans/M6_MOSKVA.md` bod 6 (místní hry) · parita F-082 ·
jen Moskva

## Účel

Podkidnoj durak ve dvoře: 36 karet, trumf, útok a obrana, přihazování. Hráč proti 1–3 NPC podle
obtížnosti. Kdo se první zbaví karet, vyhrál; kdo poslední drží karty, je durak.

## Config

`content/tuning.yaml` → `minigames.durak`; ve vektoru `{hand, opponents, aiErrorPct, level}`.

| klíč | význam | default |
|---|---|---|
| `hand` | karet v ruce po dobrání | 6 |
| `opponents` | počet NPC podle obtížnosti 1–5 | [1, 1, 2, 2, 3] |
| `ai_error_pct` | šance náhodné akce | [35, 20, 10, 5, 0] |
| `time_cap_s`, `ai_think_s` | jen UI | 420, 0,7 |

## Karty a stav

Karta `c` 0–35: hodnota `rank = c mod 9` (0 = 6 … 8 = eso), barva `suit = c div 9` (♠ ♥ ♦ ♣).
Karta `a` **přebije** `b`: stejná barva a vyšší hodnota, nebo `a` je trumf a `b` ne. „Cena“ karty
`= (trumf ? 9 : 0) + rank`.

```
{ n, hands, stock, trump, trumpCard, table, attacker, defender, thrower, passes, limit,
  finished, over, durak, byCount, rng }
```

- `n` = hráčů (`opponents[level−1] + 1`), místo 0 hráč, 1…n−1 NPC, pořadí po směru 0, 1, …
- `hands[i]` vzestupně; `stock` = balíček, bere se zepředu, poslední je trumfová karta.
- `table` = `[{a, d}]` útočné karty a jejich přebití (`d = −1` nepřebitá).
- `thrower` = místo, které teď může přihodit; `passes` = po sobě jdoucí „bito“ přihazujících od
  posledního přebití; `limit` = nejvýš útočných karet v kole.
- `finished` = místa v pořadí, jak vyšla; `durak` = místo duraka, nebo −1.
- **init:** `r = Prng(seed)`, balíček = `r.shuffle([0 … 35])`; rozdá se po jedné `hand`-krát
  (karta `k` dostane místo `k mod n`), zbytek je `stock`, `trumpCard` = poslední karta `stock`,
  `trump` = její barva. Útočí místo s nejnižším trumfem v ruce (žádné → 0); `rng = r.state`.

## Akce a tah

Na tahu je obránce, když na stole leží nepřebitá karta, jinak `thrower` (na prázdném stole je
`thrower = attacker`). `by = "player"` pro místo 0, jinak `"ai"`.

- `{"by", "op": "play", "card"}` – útok nebo přihození. Prázdný stůl: kterákoli karta z ruky.
  Jinak jen hodnota, která na stole už leží (útočná i přebíjející), a jen při `len(table) < limit`.
  První karta kola nastaví `limit = min(6, len(hands[defender]))`. Po přihození `passes = 0`.
- `{"by", "op": "beat", "card"}` – obránce přebije nepřebitou kartu (vždy je jen jedna).
  Pak `thrower = attacker`, `passes = 0`.
- `{"by", "op": "take"}` – obránce bere všechny karty ze stolu (útočné i přebíjející) do ruky;
  kolo končí **braním**.
- `{"by", "op": "pass"}` – přihazující nechce nebo nemůže (jen na neprázdném přebitém stole):
  `passes += 1`; `passes = počet přihazujících` → kolo končí **bito**; jinak `thrower` = další
  přihazující po směru.
- `{"by": "timeout"}` – kdykoli před koncem.

Přihazující = místa ve hře (ne `finished`) kromě obránce. `legalActions`: obránce – `beat`
vzestupně podle karty, pak `take`; přihazující – `play` vzestupně, pak `pass` (na prázdném stole
bez `pass`).

## Konec kola

1. Bito: stůl jde ze hry. Braní: karty jdou obránci do ruky.
2. Dobírání do `hand` ze `stock`: útočník, pak ostatní přihazující po směru od útočníka, obránce
   poslední.
3. Kdo má prázdnou ruku a `stock` je prázdný, vyšel: přidá se do `finished` (po směru od útočníka,
   obránce poslední).
4. Ve hře zůstal nejvýš jeden → `over`; ten jeden je `durak`, nikdo → `durak = −1`.
5. Jinak nový útočník: po bito obránce (je-li ve hře), po braní a vyšlém obránci další místo ve hře
   po směru za obráncem; obránce = další místo ve hře po útočníkovi. `thrower = attacker`,
   `passes = 0`, `table = []`.

## AI

`err = aiErrorPct[level−1]`; `r = ai.nextInt(100)`; `r < err` → `legal[ai.nextInt(len)]`. Jinak:

- **Útok** (prázdný stůl): nejlevnější karta v ruce.
- **Přihození:** nejlevnější legální netrumfová karta; trumf jen při prázdném `stock`; nic → `pass`.
- **Obrana:** nejlevnější přebíjející karta; žádná → `take`.

Shoda ceny → nižší číslo karty.

## Výsledek a hvězdy

`{winner, stars, score, byCount, place, durak}`: `place` = pořadí hráče ve `finished` od 1, nebo 0.
Hráč je durak → `"ai"`, 0★; hráč vyšel první → `"player"`, 3★; nikdo není durak → `"draw"`, 1★;
jinak (hráč vyšel) → `"player"`, 2★. `timeout`: `byCount = true`; hráč vyšel, nebo má méně karet než
každé NPC ve hře → `"player"`, 1★; jinak `"ai"`, 0★. `score = stars × 100`.

## UI

- Nahoře NPC s počtem karet (`durakOpp`, `durakCards`, vyšlí `durakOut`), uprostřed stůl s páry
  útok/přebití, vedle balíček a trumfová karta (`durakTrump`). Dole ruka jako vějíř, legální karty
  ťukací, ostatní ztlumené.
- Tlačítka `durakTake` (obrana) a `durakPass` (přihazování), stav `durakAttack`, `durakDefend`,
  `durakThrow`.
- NPC táhnou po `ai_think_s`, hráč na tahu má zvýrazněné místo.

## Hraniční případy

- Při braní už nikdo nepřihazuje (zjednodušení podkidného).
- Přihazující bez karet může jen `pass`; obránce, který vyšel, končí kolo bito.
- Útočník, který kartu vynese jako poslední z ruky při prázdném `stock`, vyjde až na konci kola.

# Double Dutch

**version: 1** · engine `rhythm` · P0 · vektory `vectors/doubledutch.json` · kontrakt
`specs/minigames/README.md` · plán: `plans/M2_NYC.md` bod 9 (místní hry, „rhythm jen pro Double
Dutch“) · parita F-068 · jen New York

## Účel

Skákání přes dvě švihadla točená proti sobě, pouliční hra z Harlemu a Brooklynu. Lana točí v rytmu,
hráč klepne v okamžiku úderu (skok), u trikového úderu táhne prstem nahoru (otočka). Rytmus se
postupně zrychluje. Přesnost dává body a kombo, minutí je zakopnutí; tři zakopnutí končí hru.
První hra enginu `rhythm`: na rozdíl od `arcade` (simulace v tikách) se hodnotí jednotlivé údery
podle časové odchylky, kterou měří UI.

## Config

`content/tuning.yaml` → `minigames.doubledutch`; ve vektoru
`{level, beats, introBeats, startGapMs, minGapMs, speedupEvery, speedupMs, trickPct, perfectMs,
goodMs, okMs, maxTrips, perfectPts, goodPts, okPts, trickMult, comboStep, maxMult, starPct}`.

| klíč | význam | default |
|---|---|---|
| `beats` | počet úderů | 60 |
| `intro_beats` | prvních N úderů vždy obyčejný skok | 4 |
| `start_gap_ms`, `min_gap_ms` | rozestup úderů na začátku / nejmenší, obtížnost 1–5 | [700, 640, 580, 520, 470], [520, 470, 420, 380, 340] |
| `speedup_every`, `speedup_ms` | po kolika úderech se rozestup zkrátí a o kolik | 8, 20 |
| `trick_pct` | % trikových úderů podle obtížnosti | [0, 10, 15, 20, 25] |
| `perfect_ms`, `good_ms`, `ok_ms` | okna přesnosti (\|err\|) | 45, 90, 140 |
| `max_trips` | zakopnutí do konce | 3 |
| `perfect_pts`, `good_pts`, `ok_pts` | body za úder | 100, 60, 30 |
| `trick_mult` | násobek bodů trikového úderu | 2 |
| `combo_step`, `max_mult` | +1 k násobiči každých N úderů v kombu, strop | 10, 4 |
| `star_pct` | % maximálního skóre pro 3★, 2★, 1★ | [85, 65, 40] |
| `lead_in_ms` | čas do prvního úderu (jen UI) | 1500 |
| `time_cap_s` | jen UI | 180 |

## Stav

```
{ kinds: [int], next, score, combo, bestCombo, trips, perfect, good, ok, misses, over, rng }
```

- `kinds` = druh každého úderu: 0 skok (klepnutí), 1 trik (tah nahoru).
- `next` = index úderu, který se právě hodnotí.
- `init`: `rng = Prng(seed)`; pro `i = 0 … beats − 1`: při `i < introBeats` je `kinds[i] = 0`,
  jinak `kinds[i] = (rng.nextInt(100) < trickPct[level − 1]) ? 1 : 0` (losuje se u každého
  `i ≥ introBeats`, i při `trickPct = 0`). Uloží se `rng`, ostatní 0, `over = false`.

## Rozestupy úderů

Pro UI i výpočet délky: úder 0 je `lead_in_ms` po startu, úder `i ≥ 1` je
`gap(i) = max(minGapMs[level − 1], startGapMs[level − 1] − (i ÷ speedupEvery) × speedupMs)` ms
po úderu `i − 1`.

## Akce

- `{"by": "player", "op": "hit", "input": 0 | 1, "errMs": int}` – vstup k úderu `next`
  (0 klepnutí, 1 tah nahoru), `errMs` = čas vstupu − čas úderu.
- `{"by": "player", "op": "miss"}` – úder `next` prošel bez vstupu.
- `{"by": "timeout"}`.

## Pravidla

- **hit:** `e = |errMs|`. Je-li `input ≠ kinds[next]` nebo `e > okMs`, je to **minutí**. Jinak
  `combo += 1`, `bestCombo = max(bestCombo, combo)`,
  `mult = 1 + min(combo ÷ comboStep, maxMult − 1)`, základ = `perfectPts` při `e ≤ perfectMs`
  (`perfect += 1`), `goodPts` při `e ≤ goodMs` (`good += 1`), jinak `okPts` (`ok += 1`);
  `score += základ × (kinds[next] = 1 ? trickMult : 1) × mult`.
- **miss** a minutí: `misses += 1`, `trips += 1`, `combo = 0`.
- Po každém `hit` i `miss`: `next += 1`; `over = true`, když `next = beats` nebo
  `trips = maxTrips`.
- **timeout:** `over = true`.
- `legalActions`: před koncem `[{hit, input: kinds[next], errMs: 0}, {miss}]`, po konci `[]`.
- `aiAction`: hra nemá soupeře (volání je chyba).
- Po konci nelegální vše; `input` jiné než 0/1 nebo chybějící `errMs` → `IllegalAction`.

## Výsledek a hvězdy

`maxScore = Σ_{i=0}^{beats−1} perfectPts × (kinds[i] = 1 ? trickMult : 1) ×
(1 + min((i + 1) ÷ comboStep, maxMult − 1))` (vše perfektní, nepřerušené kombo).
`pct = score × 100 ÷ maxScore` (`maxScore > 0`, jinak 0).
`{winner, stars, score, pct, bestCombo, misses}`: `stars` = 3 při `pct ≥ starPct[0]`, 2 při
`≥ starPct[1]`, 1 při `≥ starPct[2]`, jinak 0; `winner = "player"` při ≥ 1★, jinak `"ai"`.

## UI

- Na výšku: dvě švihadla (oblouky `color.doubledutch.ropeA`, `ropeB`) točená proti sobě s periodou
  rovnou rozestupu úderů, mezi nimi skokan; dole kroužek blížícího se úderu, trikový úder se
  šipkou nahoru (`color.doubledutch.trick`).
- Vstup patří k úderu `next`, když přijde do `ok_ms` před jeho časem nebo později; dřívější
  vstup se ignoruje. Bez vstupu do `ok_ms` po čase úderu UI pošle `miss`. Klepnutí = `input 0`,
  tah nahoru (svisle ≥ 40 px, rychlejší než 300 ms) = `input 1`.
- Hodnocení úderu krátkým nápisem (`ddPerfect`, `ddGood`, `ddOk`, `ddMiss`), kombo (`ddCombo`),
  zakopnutí (`ddTrips`), skóre nahoře. Zakopnutí = skokan klopýtne, lana se na chvíli zastaví a
  rozběhnou se v rytmu dalšího úderu (časy úderů se neposouvají).
- Pauza zastaví hudbu i lana; po pokračování běží čas úderů dál od místa pauzy.

## Hraniční případy

- Špatný vstup v přesném čase (klepnutí na trik) = minutí.
- Kombo se počítá i přes trikové údery; minutí ho nuluje, ale skóre zůstává.
- Tři zakopnutí v úvodu = konec s nízkým `pct`.
- Obtížnost 1 nemá triky (`trickPct = 0`), ale `rng` se losuje stejně.

## Upřesnění v1

- `init`: jediné `Prng(seed)`, losuje se jen pro `i ≥ introBeats` v pořadí úderů; ve stavu je
  konečný uint32 stav generátoru.
- `hit`: `input` musí být 0 nebo 1 a `errMs` celé číslo (jinak `IllegalAction`). Minutí (špatný
  vstup nebo `|errMs| > okMs`) nedá body, jen `misses`, `trips` += 1 a `combo = 0`.
- Násobič se počítá z komba **po** přičtení tohoto úderu. Konec (`next = beats` nebo
  `trips = maxTrips`) se vyhodnotí po každém `hit` i `miss`; `timeout` mění jen `over`.
- `pct = floor(score × 100 ÷ maxScore)`.
- UI (W): čas vstupu = okamžik dotyku (pointerdown) na hodinách hry. Tah nahoru (≥ 40 px do
  300 ms od dotyku) se pošle jako `input 1`, jakmile ho prst urazí; jinak `input 0` při puštění
  nebo po 300 ms držení. Dokud nerozhodnutý dotyk patří k úderu `next`, `miss` se neposílá.
  `errMs = floor(čas vstupu − čas úderu)`.

# Stickball

**version: 1** · engine `sport` · P0 · vektory `vectors/stickball.json` · kontrakt
`specs/minigames/README.md` · plán: `plans/M2_NYC.md` bod 9 (místní hry) · parita F-067 ·
jen New York

## Účel

Pouliční baseball z East Harlemu: násada od koštěte, gumový míček, mety jsou kanálové poklopy.
Soupeř nadhazuje, hráč odpaluje: klepne do jednoho ze tří pásem (nízko, středně, vysoko) ve chvíli,
kdy míček doletí. Přesnost načasování a pásma rozhoduje mezi homerunem, dvoumetovým a jednometovým
odpalem, faulem a minutím. Skóre = doběhy, hraje se do `maxOuts` autů. Engine `sport` (jako Nohejbal):
souboj se soupeřem, kde se rozhoduje po jednotlivých akcích, ne simulací v tikách.

## Config

`content/tuning.yaml` → `minigames.stickball`; ve vektoru
`{level, maxOuts, strikesOut, ballsWalk, zonePct, flightMin, flightVar, perfectMs, goodMs, okMs,
foulMs, catchPct, starRuns}`.

| klíč | význam | default |
|---|---|---|
| `max_outs` | počet autů do konce hry | 6 |
| `strikes_out`, `balls_walk` | strike-out, metou zdarma | 3, 4 |
| `zone_pct` | % nadhozů do zóny podle obtížnosti 1–5 | [85, 80, 75, 70, 65] |
| `flight_min`, `flight_var` | let míčku `min + 0…var` ms podle obtížnosti | [900, 800, 700, 600, 520], [200, 250, 300, 350, 400] |
| `perfect_ms`, `good_ms`, `ok_ms`, `foul_ms` | okna načasování odpalu (\|err\|) | 40, 80, 130, 200 |
| `catch_pct` | % chycených jednometových odpalů podle obtížnosti | [10, 15, 20, 25, 30] |
| `star_runs` | doběhy pro 3★, 2★, 1★ | [8, 5, 2] |
| `time_cap_s` | jen UI | 300 |

## Stav

```
{ phase: "pitch" | "bat" | "over", outs, strikes, balls, bases, runs, hits, homers,
  pitch: {zone, lane, flightMs}, last, rng }
```

- `bases` = bitová maska obsazených met (bit 0 první, bit 1 druhá, bit 2 třetí).
- `pitch` = poslední nadhoz (`zone` bool, `lane` 0 nízko / 1 středně / 2 vysoko, `flightMs`);
  po `init` `{zone: false, lane: 0, flightMs: 0}`.
- `last` = výsledek poslední akce: `""`, `ball`, `strike`, `foul`, `single`, `double`, `homer`,
  `catch`, `walk`, `strikeout`.
- `init`: `rng = Prng(seed).state`, `phase = "pitch"`, čísla 0, `last = ""`.

## Akce

- `{"by": "ai", "op": "pitch", "zone": bool, "lane": 0–2, "flightMs": int ≥ 1}` – jen v `pitch`,
  pak `phase = "bat"`, `pitch` = akce, `last = ""`.
- `{"by": "player", "op": "swing", "lane": 0–2, "errMs": int}` – jen v `bat`; `errMs` = čas
  odpalu − čas doletu (může být záporné).
- `{"by": "player", "op": "take"}` – jen v `bat`, hráč nechá míček projít.
- `{"by": "timeout"}` – kdykoli před koncem.

## Pravidla

### Odpal (`swing`)

`e = |errMs|`; stupeň `g` = 3 při `e ≤ perfectMs`, 2 při `≤ goodMs`, 1 při `≤ okMs`, 0 při
`≤ foulMs`, jinak −1. Při `g ≥ 0`: `g = g − |lane − pitch.lane|`, a když `pitch.zone` je `false`,
ještě `g = g − 1`. Pak:

- `g = 3` → **homerun** (4 mety), `g = 2` → **dvoumetový** (2), `g = 1` → `r = rng.nextInt(100)`;
  `r < catchPct[level − 1]` → **chycený** (aut, `last = "catch"`), jinak **jednometový** (1).
- `g = 0` → **faul**: `strikes += 1`, jen když `strikes < strikesOut − 1`; `last = "foul"`.
- `g < 0` → **strike** (minutí).

### Nechaný míček (`take`)

`pitch.zone` → **strike**, jinak **ball**: `balls += 1`; při `balls = ballsWalk` **meta zdarma**.

### Strike

`strikes += 1`; při `strikes = strikesOut` **aut** (`last = "strikeout"`), jinak `last = "strike"`.

### Mety

Pozice: domácí 0, první 1, druhá 2, třetí 3, doběh 4.

- **Odpal o `k` met** (`hits += 1`, u homerunu i `homers += 1`): každý běžec na metě `p` postoupí
  na `p + k`, pálkař na `k`; kdo dosáhne ≥ 4, `runs += 1`. `last` = `single` / `double` / `homer`.
- **Meta zdarma:** pálkař na první; běžec na první postoupí jen, když je první obsazená; na druhé
  jen, když jsou obsazené první i druhá; na třetí (doběh) jen, když jsou obsazené všechny tři.
  `last = "walk"`.
- **Aut** (strike-out nebo chycený): `outs += 1`, mety beze změny.

Po odpalu, autu i metě zdarma `strikes = balls = 0`. Při `outs = maxOuts` `phase = "over"`,
jinak `phase = "pitch"`. Po `ball`, `strike` a `foul` bez konce pálkaře `phase = "pitch"`.

### timeout

`phase = "over"`.

### Ostatní

- `legalActions`: `pitch` → `[]` (nadhazuje AI); `bat` → `[{take}, {swing, lane: 0, errMs: 0},
  {swing, lane: 1, errMs: 0}, {swing, lane: 2, errMs: 0}]`; `over` → `[]`.
- Akce mimo fázi, jiné `by`, chybná pole → `IllegalAction`.

## AI (nadhazovač)

`aiAction(state, level, ai)` jen v `pitch`; volá jen `ai`, v tomto pořadí:
`zone = ai.nextInt(100) < zonePct[level − 1]`, `lane = ai.nextInt(3)`,
`flightMs = flightMin[level − 1] + ai.nextInt(flightVar[level − 1] + 1)`.
Vrací `{by: "ai", op: "pitch", zone, lane, flightMs}`.

## Výsledek a hvězdy

`{winner, stars, score, hits, homers}`: `score = runs`; `stars` = 3 při `runs ≥ starRuns[0]`,
2 při `≥ starRuns[1]`, 1 při `≥ starRuns[2]`, jinak 0; `winner = "player"` při ≥ 1★, jinak `"ai"`.

## UI

- Na výšku: nadhazovač nahoře v ulici (perspektiva), pálkař dole, tři pásma odpalu jako vodorovné
  pruhy u pálkaře (`color.stickball.zone*`). Míček letí `flightMs` od nadhozu; pásmo `lane` určuje
  výšku dopadu, nadhoz mimo zónu letí viditelně stranou.
- Klepnutí do pásma = `swing` s `errMs` = čas klepnutí − čas doletu (celé ms, `floor`). Bez
  klepnutí do doletu + `foul_ms` → `take`. Klepnutí dřív než `foul_ms × 2` před doletem se ignoruje.
- Nahoře stav: doběhy (`stickballRuns`), počet (`stickballCount`: balls, strikes, outs), mety jako
  tři poklopy. Po akci krátký nápis `last` (`stickballLast_<last>`).
- Pauza a vzdání podle kontraktu.

## Hraniční případy

- Faul při dvou strikech nemění počet.
- Odpal mimo zónu ve správném pásmu s perfektním časem = dvoumetový (3 − 1).
- Chycený odpal nepohne běžci.
- Meta zdarma s plnými metami = doběh.
- Homerun s plnými metami = 4 doběhy.

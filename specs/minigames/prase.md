# Prase

**version: 1** · engine `dice` · P0 · vektory `vectors/prase.json` · kontrakt `specs/minigames/README.md`

## Účel

Kostka a nervy (pig; M2 bod 9, dávka B; METROPOLE_PLAN 9.5 č. 22) proti NPC, o body (R11).
Házíš, dokud chceš, a body si zapíšeš; padne-li jednička, zisk tahu propadne. Kdo první
zapíše `target`, vyhrál.

## Config

`content/tuning.yaml` → `minigames.prase`; ve vektoru
`{target, maxRounds, aiHoldAt, aiErrorPct, starMargins}`.

| klíč | význam | default |
|---|---|---|
| `target` | kdo zapíše celkem aspoň tolik, vyhrál | 100 |
| `max_rounds` | nejvýš kol (kolo = tah hráče + tah AI) | 15 |
| `ai_hold_at` | AI zapisuje od tohoto zisku v tahu, úroveň 1–5 | [10, 15, 18, 20, 20] |
| `ai_error_pct` | šance náhodné akce AI | [35, 20, 10, 5, 0] |
| `star_margins` | náskok pro 3★ a 2★ | [40, 15] |
| `time_cap_s` | časový strop (UI) | 300 |
| `ai_think_s` | pauza před akcí AI (jen UI) | 0.6 |

## Stav

```
{ player, ai, turn, turnScore, die, bust, round, over, rng }
```

`player`, `ai` zapsané body; `turnScore` zisk v rozehraném tahu; `die` poslední hozená hodnota
(0 = v partii ještě nehozeno); `bust` poslední tah skončil jedničkou; `round` od 1.

## Akce

`{"by": strana, "op": "roll"}`, `{"by": strana, "op": "hold"}`, `{"by": "timeout"}`.
`legalActions`: `turnScore = 0` → `[roll]`; jinak `[roll, hold]`; po konci prázdné.

## Pravidla

- `init`: 0 : 0, `turn = "player"`, `turnScore = 0`, `die = 0`, `bust = false`, `round = 1`,
  `rng = Prng(seed).state`.
- `roll`: `die = rng.nextInt(6) + 1`. `die = 1` → `turnScore = 0`, `bust = true`, konec tahu.
  Jinak `turnScore += die`, `bust = false`.
- `hold`: straně na tahu se přičte `turnScore`. Dosáhne-li `target`, `over = true` a tah se už
  nepředává (`turnScore = 0`). Jinak konec tahu.
- **Konec tahu:** `turnScore = 0`, tah přejde (`die` zůstane pro UI). Když tah končí AI,
  `round += 1`; je-li pak `round > maxRounds`, `over = true`.
- `die` přes konec tahu zůstává (UI ukáže, co padlo); přepíše ho až první hod dalšího tahu.
- `timeout`: `over = true`.

## AI

`err = aiErrorPct[level−1]`, `holdAt = aiHoldAt[level−1]`. `r = ai.nextInt(100)` u **každé**
akce AI (i při jediné legální). `r < err` → `legal[ai.nextInt(len)]`. Jinak, s `t = turnScore`,
v tomto pořadí:

1. `t = 0` → `roll`.
2. `ai + t ≥ target` → `hold`.
3. Úroveň ≥ 3 a `round = maxRounds` (poslední tah AI): `ai + t > player` → `hold`, jinak `roll`.
4. Úroveň ≥ 4 a `player ≥ target − 20` → `roll`.
5. `t ≥ holdAt` → `hold`, jinak `roll`.

## Výsledek a hvězdy

`{winner, stars, score, player, ai}`; vyšší body vyhrávají, shoda `"draw"`. Hráč vyhrál
o `≥ starMargins[0]` → 3★, `≥ starMargins[1]` → 2★, jinak 1★; jinak 0★. `score = player`.

## UI

Velká kostka uprostřed, pod ní zisk tahu (`praseTurn`) a skóre obou stran s cílem; tlačítka
„Hodit“ (`praseRoll`) a „Zapsat“ (`praseHold`). Jednička = krátký toast `praseBust`.

## Hraniční případy

- Hráč začíná, takže může vyhrát dřív, než AI odehraje stejný počet tahů.
- `hold` při `turnScore = 0` je nelegální.
- Po `round > maxRounds` rozhoduje vyšší součet, shoda = remíza.

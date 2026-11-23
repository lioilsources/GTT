# Městský kvíz

**version: 1** · engine `puzzle` · P0 · vektory `vectors/kviz.json` · kontrakt `specs/minigames/README.md`

## Účel

Kvíz o městě pro jednoho hráče (M2 bod 9, dávka A): 10 otázek se čtyřmi možnostmi z banky
města, pořadí otázek i možností losuje seed. Soupeř není.

## Banka otázek

`content/quiz/<city>.yaml`: `questions: [{id, q: {en, cs}, options: {en: [4], cs: [4]}, answer}]`,
`answer` = index správné možnosti (0–3) v pořadí souboru. `metro sync` ho zkontroluje (unikátní
`id`, přesně 4 možnosti v obou jazycích, `answer` 0–3) a zapíše `content/quiz/<city>.json` pro oba
klienty. Město bez banky (nebo s méně než 4 otázkami) kvíz nenabízí.

## Config

`content/tuning.yaml` → `minigames.kviz`; ve vektoru `{bank, rounds, starCorrect}`, kde
`bank = [answer, …]` (správné indexy v pořadí banky; texty pravidla nepotřebují).

| klíč | význam | default |
|---|---|---|
| `rounds` | otázek ve hře | 10 |
| `star_correct` | správných odpovědí pro 3★, 2★, 1★ | [9, 7, 5] |
| `question_s` | čas na otázku (UI, pak odpověď −1) | 20 |
| `time_cap_s` | časový strop (UI) | 420 |

## Stav

```
{ order, perms, cur, correct, answers, over, rng }
```

`order` = indexy otázek banky, `perms[k]` = pořadí zobrazených možností k-té otázky (pole 4
indexů do původních možností), `cur` = index aktuální otázky, `answers` = zvolené zobrazené indexy
(−1 = nestihl).

## Losování (`init`)

`rng = Prng(seed)`, `n = len(bank)`, `R = min(rounds, n)`. `idx = [0..n)`; pro `i = 0..R−1`:
`j = i + rng.nextInt(n − i)`, prohodí `idx[i]` a `idx[j]`; `order = idx[0..R)`. Pak pro každou
otázku v pořadí `order`: `p = [0, 1, 2, 3]`, pro `i = 3, 2, 1`: `j = rng.nextInt(i + 1)`, prohodí
`p[i]` a `p[j]`; `perms` = tato pole.

## Akce

`{"by": "player", "answer": d}`, `d` ∈ −1…3 (zobrazený index, −1 = vypršel čas otázky).
`{"by": "timeout"}`. `legalActions`: `answer` 0, 1, 2, 3, −1 (za hry). `aiAction` neexistuje.

## Pravidla

Odpověď je správná, když `d ≥ 0` a `perms[cur][d] = bank[order[cur]]`; pak `correct += 1`.
`answers` += `d`, `cur += 1`; `cur = R` → `over`. `timeout` → `over` (zbylé otázky špatně).

## Výsledek a hvězdy

`{winner, stars, score, correct, rounds}`. Hvězdy podle `starCorrect` (≥ 1. prahu 3★ atd.,
při `R < rounds` se prahy přepočtou `práh × R ÷ rounds`). `winner = "player"` při ≥ 1★, jinak
`"ai"`. `score = correct × 100`.

## UI

Otázka nahoře, čtyři velká tlačítka pod sebou (palec), odpočet `question_s` jako pruh. Po
odpovědi na chvíli zelená/červená a správná možnost. Texty z banky podle jazyka UI.

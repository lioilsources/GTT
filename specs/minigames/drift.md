# Drift zóna

**version: 1** · engine `drive` · pravidla P0 (vektory `vectors/drift.json`), jízda P2 (skutečný
svět) · kontrakt `specs/minigames/README.md` · plán: `plans/M2_NYC.md` bod 9 (dávka D) · parita
F-065 · navazuje na `specs/minigames/taxi.md` (světová minihra), `specs/drive.md`,
`specs/garage.md`, `specs/loop.md`

## Účel

Světová minihra jako Taxi: na prázdném parkovišti nebo molu je vyznačená zóna (kruh kolem
parkovacího bodu spotu) a hráč v ní vlastním autem (s vylepšeními z garáže, `tunedSpec`) 90 s
driftuje. Body se sbírají v řetězu za úhel smyku a rychlost, řetěz roste násobičem, dokud drift
vydrží; náraz řetěz zahodí, konec driftu ho připíše. Fyzika auta je P1 (`specs/drive.md`), čistá
pravidla počítají jen body z celočíselných vzorků, které posílá svět.

## Config

`content/tuning.yaml` → `minigames.drift`. Pravidla dostanou
`{level, minSlipMrad, maxSlipMrad, minSpeedCms, maxSpeedCms, ptsDiv, maxDtMs, graceMs, multStepMs,
maxMult, starScores, levelPct}`.

| klíč | význam | default |
|---|---|---|
| `min_slip_mrad`, `max_slip_mrad` | smyk se počítá od / nejvýš do (mrad, \|β\|) | 250, 800 |
| `min_speed_cms`, `max_speed_cms` | rychlost se počítá od / nejvýš do (cm/s) | 800, 2500 |
| `pts_div` | dělitel bodů vzorku | 1000 |
| `max_dt_ms` | nejdelší započtený úsek mezi vzorky | 250 |
| `grace_ms` | jak dlouho smí drift vypadnout, než se řetěz připíše | 600 |
| `mult_step_ms` | každých tolik ms driftu v řetězu +1 k násobiči | 2000 |
| `max_mult` | strop násobiče | 5 |
| `star_scores` | skóre pro 3★, 2★, 1★ při obtížnosti 3 | [40000, 20000, 8000] |
| `level_pct` | prahy hvězd × % podle obtížnosti 1–5 | [60, 80, 100, 120, 140] |
| `session_s` | délka (jen UI, pak `timeout`) | 90 |
| `zone_m` | poloměr zóny kolem parkovacího bodu spotu | 45.0 |
| `sample_hz` | vzorky za sekundu času jízdy (jen UI) | 10 |
| `hit_min_mps` | náraz menší rychlostí se nepočítá (jen UI) | 2.0 |
| `low_s` | časovač zčervená pod (jen UI) | 15.0 |

## Stav

```
{ phase: "run" | "over", clockMs, lastDriftMs, score, chain, chainMs, mult, best, drifts, hits }
```

Po `init`: `phase = "run"`, všechna čísla 0 kromě `mult = 1`. Hra nemá náhodu (`rng` ve stavu
není, `seed` se nepoužije).

## Akce

- `{"by": "player", "op": "sample", "atMs": int, "slipMrad": int, "speedCms": int, "inZone": bool}`
  – vzorek auta v čase `atMs` od začátku (celé ms, ≥ `clockMs`); `slipMrad` = `floor(|β| × 1000)`,
  `speedCms` = `floor(|v| × 100)`, obojí ≥ 0; `inZone` = střed auta je v zóně a auto je ve vrstvě 0.
- `{"by": "player", "op": "hit", "atMs": int}` – náraz (`atMs ≥ clockMs`).
- `{"by": "timeout"}` – konec relace (UI po `session_s`).

## Pravidla

`÷` je celočíselné dělení nezáporných čísel (dolů).

### sample

1. `dt = min(atMs − clockMs, maxDtMs)`, `clockMs = atMs`.
2. **Drift** = `inZone` a `slipMrad ≥ minSlipMrad` a `speedCms ≥ minSpeedCms`.
3. Drift: `a = dt × min(slipMrad, maxSlipMrad) ÷ 1000`, `pts = a × min(speedCms, maxSpeedCms) ÷
   ptsDiv`; `chain += pts`, `chainMs += dt`, `mult = min(1 + chainMs ÷ multStepMs, maxMult)`,
   `lastDriftMs = atMs`.
4. Ne drift: je-li `chain > 0` a `atMs − lastDriftMs > graceMs`, řetěz se **připíše**.

**Připsání:** `bank = chain × mult`; `score += bank`, `best = max(best, bank)`, `drifts += 1`;
pak `chain = chainMs = 0`, `mult = 1`.

### hit

`clockMs = atMs`, `hits += 1`, řetěz propadne bez připsání (`chain = chainMs = 0`, `mult = 1`).

### timeout

Je-li `chain > 0`, řetěz se připíše; `phase = "over"`.

### Ostatní

- `legalActions`: `run` → `[{sample, atMs: clockMs, slipMrad: 0, speedCms: 0, inZone: false},
  {timeout}]`, `over` → `[]`.
- `aiAction`: hra nemá soupeře (volání je chyba).
- Jiné `by`, neznámé `op`, chybná pole, `atMs < clockMs`, záporné `slipMrad`/`speedCms`, akce ve
  `over` → `IllegalAction`.

## Hvězdy a výsledek

`result` je `null` mimo `over`. Pak `{winner, stars, score, best, drifts, hits}`: prahy
`t[i] = starScores[i] × levelPct[level − 1] ÷ 100`; `stars` = 3 při `score ≥ t[0]`, 2 při
`≥ t[1]`, 1 při `≥ t[2]`, jinak 0; `winner = "player"` při `stars ≥ 1`, jinak `"draw"`.

## Svět (P2, oba klienti stejně)

- **Start:** smyčka (`specs/loop.md`) u spotu s minihrou `drift` spustí relaci ve běžícím světě
  (engine `drive`, bez pauzy, telefon se zavře, navigace se zruší). Hráč jede **svým** autem,
  včetně vylepšení z garáže (drift slot prodlužuje smyk, `specs/garage.md`). Provoz a chodci jedou
  dál, policie taky.
- **Zóna:** kruh `zone_m` kolem parkovacího bodu spotu, kreslený na zemi barvou
  `color.drift.zone` (obrys) a `color.drift.zoneFill`; mimo zónu se drift nepočítá.
- **Vzorky:** po každých `1 / sample_hz` s času jízdy (stejné `dt` světa jako jízda) pošle UI
  `sample`; čas v akcích = celé ms od začátku relace (`floor`). `β` = úhel mezi natočením auta a
  směrem rychlosti (při `|v| < 0,5 m/s` je `β = 0`).
- **Náraz:** kolize s budovou, zábradlím nebo autem provozu rychlostí ≥ `hit_min_mps` → `hit`
  (nejvýš jednou za 500 ms).
- **HUD:** zbývající čas (`driftTime`), skóre (`driftScore`), živý řetěz s násobičem
  (`driftChain`), záblesk připsaného řetězu (`driftBank`), tlačítko ukončit (= vzdát). Barvy
  `color.drift.*`.
- **Konec:** `timeout` → výsledek → normální výsledek smyčky; vzdaná relace = `aborted`, 0★.
  Hráč, který sám přesedne nebo vyjede z garáže, relaci ukončí (`timeout`).
- „Hrát“ u jiných spotů a nákupní tlačítka smyčky během relace nespouští jiné minihry.

## Galerie a ladění

Jako Taxi: Galerie ukáže řádek s poznámkou „začíná ve městě“ (`driftGallery`) a tlačítkem
(`driftGalleryGo`); W `?mg=drift` otevře svět na spotu s minihrou `drift` a hned spustí relaci,
F přenese auto na spot a spustí ji.

## Hraniční případy

- První vzorek: `dt = atMs` (nejvýš `maxDtMs`).
- Výpadek vzorků (zpomalený telefon): delší úsek než `maxDtMs` se ořízne, body se nepřidají navíc.
- Vyjetí ze zóny během driftu = konec driftu, připíše se po `graceMs`.
- Náraz při nulovém řetězu jen zvýší `hits`.
- Město bez spotu `drift`: minihra se neobjeví ve Feedu (žádný spot).

## Upřesnění v1

- `sample` i `hit`: `atMs` celé číslo `≥ clockMs`; `slipMrad`, `speedCms` celá `≥ 0`, `inZone`
  bool. `dt` se počítá ze **starého** `clockMs`; `clockMs = atMs` se nastaví u každého vzorku
  (drift i ne-drift) i u `hit`.
- Řetěz s `chain = 0` se nepřipisuje ani nenuluje (ne-drift ani `timeout` s ním nic nedělá);
  `chainMs` a `mult` mu zůstanou, dokud je nevynuluje připsání nebo náraz. `lastDriftMs` nenuluje
  nic (ani připsání, ani náraz).
- `hit` nemění `lastDriftMs` ani `score`/`best`/`drifts`; `drifts` počítá jen připsané řetězy.
- **Svět (W):** nejvýš jeden vzorek za snímek: `acc += dt`; když `acc ≥ 1 / sample_hz`, pošle se
  vzorek a `acc = acc mod (1 / sample_hz)`. `atMs = floor(clock × 1000)` po přičtení `dt`
  snímku. Náraz snímku jde jako `hit` **před** vzorkem téhož snímku se stejným `atMs`. Snímek,
  ve kterém `clock ≥ session_s`, pošle jen `timeout` (bez vzorku a nárazu).
- `β = |atan2(boční, podélná rychlost)|` vůči natočení auta (při couvání až π); pod 0,5 m/s 0.
  `inZone` = vzdálenost středu auta od parkovacího bodu spotu `≤ zone_m` a vrstva 0.
- Náraz (stejně u Sprintu): začátek kontaktu s budovou (rychlost auta podél normály kontaktu),
  zábradlí mostu/tunelu (rychlost do zábradlí) nebo náraz auta provozu (jeho `impactMps`), vždy
  `≥ hit_min_mps`. Nárazy do 500 ms času relace od posledního nahlášeného se zahodí.
- Tlačítko ukončit = `aborted`, 0★ a skóre 0; přesednutí / garáž = `timeout` s normálním
  výsledkem. Relace jede vlastním autem hráče bez přesunu (začíná tam, kde hráč stiskl „Hrát“).

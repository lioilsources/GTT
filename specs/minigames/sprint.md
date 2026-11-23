# Sprint A→B

**version: 1** · engine `drive` · pravidla P0 (vektory `vectors/sprint.json`), jízda P2 (skutečný
svět) · kontrakt `specs/minigames/README.md` · plán: `plans/M2_NYC.md` bod 9 (dávka D) · parita
F-066 · navazuje na `specs/minigames/taxi.md` (cíle, světová minihra), `specs/route.md`,
`specs/garage.md`, `specs/loop.md`

## Účel

Světová minihra: ze startovního spotu závod proti času do skutečného cíle ve městě (hero landmark,
jako u Taxi). Trasu po grafu silnic rozdělí kontrolní body; hráč jimi musí projet popořadě, mezi
nimi smí zkracovat. Hvězdy podle času proti „času k překonání“ (par), který roste s délkou trasy a
klesá s obtížností. Hráč jede svým autem s vylepšeními z garáže (`tunedSpec`), takže lepší auto
= snazší hvězdy. Pravidla počítají výběr cíle, pořadí kontrol, čas a hvězdy; kde je auto, rozhoduje
svět.

## Config

`content/tuning.yaml` → `minigames.sprint`. Pravidla dostanou
`{dests, level, parBaseMs, parDmPerS, hitPenaltyMs, starPct}`; `dests` = id cílů v pořadí balíčku
(stejná definice jako u Taxi, viz Svět).

| klíč | význam | default |
|---|---|---|
| `par_base_ms` | základ času k překonání | 5000 |
| `par_dm_per_s` | průměrná rychlost paru (dm/s) podle obtížnosti 1–5 | [90, 110, 130, 150, 170] |
| `hit_penalty_ms` | trest za náraz | 2000 |
| `star_pct` | čas v % paru pro 3★, 2★, 1★ | [100, 120, 145] |
| `dest_min_m`, `dest_max_m` | povolené cíle (vzdušně od startu) | 800.0, 2500.0 |
| `dest_search_m` | cíl bez udržované silnice do této vzdálenosti se nepoužije | 120.0 |
| `cp_every_m` | rozestup kontrolních bodů po trase | 300.0 |
| `cp_radius_m` | projetí kontroly do této vzdálenosti (+ polovina šířky koridoru) | 15.0 |
| `countdown_s` | odpočet před startem (jen UI) | 3 |
| `time_cap_s` | nejdelší závod (jen UI, pak `timeout`) | 300 |
| `hit_min_mps` | náraz menší rychlostí se nepočítá (jen UI) | 2.0 |

## Stav

```
{
  rng: int,                          // uint32 PRNG (specs/prng.md)
  phase: "pick" | "ready" | "run" | "over",
  dest: string,                      // cíl ("" před pick)
  distDm: int, cps: int, parMs: int, // délka trasy, počet kontrol, čas k překonání
  goMs: int, clockMs: int,           // start a čas poslední akce
  passed: int,                       // projeté kontroly
  splits: [int],                     // čas od startu při každé kontrole (ms)
  hits: int,
  finished: bool, timeMs: int        // dojel do cíle, výsledný čas (vč. trestů)
}
```

Po `init`: `rng = Prng(seed).state`, `phase = "pick"`, `dest = ""`, `splits = []`,
`finished = false`, ostatní 0.

## Akce

- `{"by": "player", "op": "pick", "allow": [string]}` – svět je připraven vybrat cíl; `allow` =
  cíle v povoleném rozmezí od startu (podmnožina `dests`, prázdné = všechny).
- `{"by": "player", "op": "go", "atMs": int, "distDm": int, "cps": int}` – svět spočítal trasu ke
  `dest` (délka v dm, počet kontrol ≥ 0 bez cíle) a odpočet skončil; `atMs` = čas startu.
- `{"by": "player", "op": "cp", "atMs": int, "index": int}` – projetí kontroly `index`.
- `{"by": "player", "op": "hit", "atMs": int}` – náraz.
- `{"by": "player", "op": "finish", "atMs": int}` – projetí cíle.
- `{"by": "timeout"}` – vypršel `time_cap_s`, nebo hráč závod ukončil.

## Pravidla

`÷` je celočíselné dělení nezáporných čísel (dolů). Časy `atMs` jsou celé ms od začátku minihry,
nesmí klesat (`atMs ≥ clockMs`), každá akce s časem nastaví `clockMs = atMs`.

- **pick** (jen `pick`): `pool` = `dests` v pořadí configu, jen ty z `allow` (prázdné = všechny);
  prázdný `pool` (město bez cílů) → `phase = "over"`, `finished = false`. Jinak
  `dest = pool[rng.nextInt(len(pool))]`, `phase = "ready"`.
- **go** (jen `ready`, `distDm ≥ 0`, `cps ≥ 0`): `goMs = clockMs = atMs`, `distDm`, `cps`,
  `parMs = parBaseMs + distDm × 1000 ÷ parDmPerS[level − 1]`, `phase = "run"`.
- **cp** (jen `run`, `index = passed`, `passed < cps`): `passed += 1`, na konec `splits` přidá
  `atMs − goMs`.
- **hit** (jen `run`): `hits += 1`.
- **finish** (jen `run`, `passed = cps`): `timeMs = atMs − goMs + hits × hitPenaltyMs`,
  `finished = true`, `phase = "over"`.
- **timeout** (v `pick`, `ready`, `run`): `phase = "over"`, `finished` zůstává `false`.
- `legalActions`: `pick` → `[{pick, allow: []}, {timeout}]`; `ready` → `[{go, atMs: clockMs,
  distDm: 0, cps: 0}, {timeout}]`; `run` → `[{cp, atMs: clockMs, index: passed}` (jen když
  `passed < cps`), `{hit, atMs: clockMs}`, `{finish, atMs: clockMs}` (jen když `passed = cps`),
  `{timeout}]`; `over` → `[]`.
- `aiAction`: hra nemá soupeře (volání je chyba).
- Jiné `by`, neznámé `op`, chybná pole, akce mimo svou fázi, kontrola mimo pořadí, cíl před
  poslední kontrolou → `IllegalAction`.

## Hvězdy a výsledek

`result` je `null` mimo `over`. Pak `{winner, stars, score, timeMs, parMs, dest, hits}`:

- nedojel (`finished = false`): `stars = 0`, `score = 0`;
- dojel: `stars` = 3 při `timeMs × 100 ≤ parMs × starPct[0]`, 2 při `≤ parMs × starPct[1]`,
  1 při `≤ parMs × starPct[2]`, jinak 0; `score = max(0, 2 × parMs − timeMs) ÷ 100`.

`winner = "player"` při `stars ≥ 1`, jinak `"draw"`.

## Svět (P2, oba klienti stejně)

- **Cíle** = stejná definice jako Taxi (`specs/minigames/taxi.md`): hero landmarky v pořadí
  `landmarks.pb` s udržovanou silnicí do `dest_search_m`, bod cíle = průmět landmarku na hranu.
  `allow` = cíle vzdušně `dest_min_m … dest_max_m` od parkovacího bodu startovního spotu.
- **Start:** smyčka u spotu s minihrou `sprint` spustí závod ve běžícím světě (engine `drive`, bez
  pauzy, telefon se zavře, navigace se zruší); auto stojí na parkovacím bodu spotu. UI hned pošle
  `pick`, ukáže cíl (`sprintTo` se jménem landmarku) a odpočet `countdown_s`; během odpočtu auto
  stojí (vstupy plynu se ignorují). Po odpočtu `go`.
- **Trasa a kontroly:** trasa ze startu do bodu cíle podle `specs/route.md` (nejkratší po
  ponechaných silnicích s jednosměrkami), `distDm` = součet délek hran trasy. Kontroly: postupně
  po trase, kontrola `k` (od 1) v prvním uzlu trasy, kde uražená délka ≥ `k × cp_every_m`, dokud
  do cíle zbývá víc než `cp_every_m ÷ 2`; uzel použitý jednou se znovu nepoužije. `cps` = jejich
  počet. Navigace (pilulka) vede vždy na další kontrolu, pak na cíl; po projetí se přepočítá.
- **Projetí:** kontrola `passed` nebo cíl (po všech kontrolách) do `cp_radius_m` + poloviny šířky
  koridoru od bodu, ve vrstvě 0 → `cp` / `finish`. Kontroly se kreslí jako brána na silnici
  (`color.sprint.gate`, další `color.sprint.next`), cíl jako šachovnice (`color.sprint.finish`).
- **Náraz** do budovy, zábradlí nebo auta provozu rychlostí ≥ `hit_min_mps` → `hit` (nejvýš jednou
  za 500 ms).
- **HUD:** čas od startu (`sprintTime`), par (`sprintPar`), kontrola `n/celkem` (`sprintCp`),
  mezičas proti paru po každé kontrole (poměrně: `parMs × uražená délka ÷ distDm`), tlačítko
  ukončit (= `timeout`, výsledek 0★ jako vzdání).
- **Konec:** `finish` nebo `timeout` → výsledek → normální výsledek smyčky (`specs/loop.md`).

## Galerie a ladění

Jako Taxi: `sprintGallery` a `sprintGalleryGo`; W `?mg=sprint` otevře svět na spotu s minihrou
`sprint` a hned spustí závod.

## Hraniční případy

- `cps = 0` (krátká trasa): rovnou `finish`.
- Jediný cíl v `pool` → vždy ten.
- Bez trasy k cíli (izolovaný cíl): cíl se v `allow` nepošle; prázdné `allow` při žádném cíli
  v rozmezí = všechny cíle, a když ani k jednomu trasa nevede, UI pošle `timeout` (0★).
- Kontrola projetá mimo pořadí se ignoruje (UI posílá jen další v pořadí).
- Rychlé auto pod parem: 3★ a vyšší skóre; score nikdy záporné.

# Herní smyčka: příjezd → minihra → výsledek

**version: 1** · P2 (průběh, UI) + čisté pomocné funkce s unit testy · plán: METROPOLE_PLAN 4, 8, 9,
M1 body 6 a 11, akceptace „10 smyček za sebou bez pádu a bez zaseknutí“ · parita F-025 ·
navazuje na `specs/phone.md` (`arrived`), `specs/economy.md`, `specs/save.md`, `specs/passport.md`

## Účel

Lepidlo mezi jízdou a minihrou: na spotu s minihrou ji spustí, po jejím konci ukáže výsledek
smyčky (hvězdy, skóre, hotovost, razítko, bonus za poprvé), připíše hotovost, razítko a rekord,
uloží hru a vrátí hráče do jízdy s nabídkou Feedu.

## Spuštění

- **S trasou:** navigace ohlásí `arrived(spotId)` (`specs/phone.md`). Má-li spot `minigame`,
  smyčka ji hned spustí.
- **Bez trasy:** hráč zastaví u spotu s minihrou: rychlost ≤ `loop.stop_speed_mps`, vrstva 0 a
  parkovací bod spotu je do `loop.spot_radius_m`. HUD ukáže kontextové tlačítko „Hrát <název>“
  (`loopPlay`); stejně jako u aut (`specs/cars.md`) vydrží `loop.action_hold_s` od posledního
  splnění podmínek, dokud je spot pořád v dosahu. Z více spotů nejbližší. Během navigace a
  otevřeného telefonu se tlačítko neukazuje.
- **Engine `drive` (Taxi):** světová minihra (`specs/minigames/taxi.md`): smyčka ji spustí ve
  běžícím světě (bez pauzy a bez celoobrazovkové hry), po jejím konci ukáže normální výsledek smyčky.
  Klient bez světové minihry pro daný engine ukáže toast „<název> už brzy“ (`loopSoon`).
- Minihra, kterou klient nemá v registru, se chová stejně jako `drive`.

## Kontext minihry

- `cityId` = město, `locale` = jazyk UI.
- `difficulty` = obtížnost přijaté karty feedu (`difficulty`), když hráč dojel po trase karty na
  tenhle spot; jinak `min(feed.difficulty_max, feed.difficulty_base + plays[spot])`
  (`plays` ze `specs/save.md`). Vždy oříznuto do 1–5.
- `seed` = náhodné uint32 (klient), v testech pevné.
- `opponentId` = NPC postava podle spotu: `characters[fnv1a(spotId) mod počet postav]`, kde
  `characters` je pořadí postav v balíčku NPC (`content/npc/characters.yaml`) a `fnv1a` 32bitový
  FNV-1a nad UTF-8 bajty (jako u pohlednice, `specs/passport.md`). Bez postav bez soupeře.

## Pauza světa

Dokud běží minihra nebo výsledková obrazovka, svět se nekrokuje ani nekreslí (DUALSTACK 6.5):
W přeskočí celé tělo render smyčky, F `pauseEngine()` / `resumeEngine()` (Flame). Telefon se
zavře, navigace se zruší.

## Výsledek smyčky

Po `onFinish(MinigameResult)`:

1. `first` = minihra nemá v `best` záznam s `stars ≥ 1`.
2. Ekonomika: akce `reward` (`specs/economy.md`) s `engine` z katalogu, `stars`, `score`,
   `first`, `driveDm` přijaté karty (jen když vedla na tenhle spot, jinak 0) a `aborted`.
3. Pas: `minigame(id, stars)` (razítko při 3★, `specs/passport.md`).
4. `best[id]` = výsledek, když je lepší: `stars > best.stars`, nebo `stars = best.stars` a
   `score > best.score`, nebo záznam chybí (a hra nebyla vzdaná). Vzdaná hra rekord nemění.
5. `plays[spot] += 1` (i po 0★; vzdaná hra se nepočítá).
6. Přijatá karta se spotřebuje (další smyčka na stejném spotu už je bez trasy).
7. Uložení (`specs/save.md`).

Výsledková obrazovka (karta přes svět): nadpis `loopTitle` a jméno minihry, hvězdy, skóre,
hotovost celkem (`loopCash`) a rozpis (`loopBase`, `loopTrip`, `loopBand`, `loopFirst` – jen
nenulové části), razítko (`loopStamp` se jménem minihry; bez razítka při < 3★ nápověda
`loopStampHint`, když razítko ještě nemá), nový rekord (`loopBest`), u vzdané hry `loopAborted`.
Tlačítka „Jet dál“ (`loopDrive`) a „Feed“ (`loopFeed`, otevře telefon s Feedem; nový balíček
se rozdá, protože hráč dojel do cíle – `specs/feed.md`). Barvy `color.loop.*`.

## Ladění

W: `?play=<spotId>` spustí minihru spotu hned po načtení; `?debug` přidá tlačítko „Smazat uložení“.
F: „Smazat uložení“ v ladicím panelu (tuning).

## Pomocné funkce (čisté, oba klienti, unit testy)

- `loopDifficulty(cardDifficulty | null, plays, feedTuning)`
- `opponentIndex(spotId, count)` → `fnv1a(spotId) mod count` (count 0 → −1)
- `betterBest(old | null, stars, score)` → bool
- `spotInReach(spots, x, y, speed, layer, tuning)` → nejbližší spot s minihrou v dosahu, nebo nic

## Soak test (akceptace M1-A1)

Bezhlavý test v obou klientech (W Vitest, F `flutter test` v `app`): 10 smyček za sebou nad čistými
moduly. Každá smyčka: rozdat balíček feedu (`feed`), přijmout kartu, „teleport“ na spot, spustit
pravidla minihry spotu skriptovanými tahy (první legální tah, AI přes `aiAction`) až do výsledku,
použít výsledek smyčky (ekonomika, Pas, best, plays), uložit (serializace JSON) a znovu načíst
(`save` `load`). Test kontroluje, že hotovost = součet odměn, razítka = minihry s 3★, `best`
odpovídá a uložení přežije cestu tam a zpět beze změny.

## Hraniční případy

- `arrived` na spot bez minihry (garáž, jízdní výzva „challenge“) → nic, jen toast `arrived`.
- Hráč minihru vzdá → 0 hotovosti, výsledková obrazovka s `loopAborted`, uloží se.
- Druhá smyčka na stejném spotu → bez karty, `trip = 0`, `first = false`, obtížnost +1.

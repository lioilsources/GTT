# Uložení hry

**version: 2** · P0 (formát a migrace, vektory `vectors/save.json`) + P2 (úložiště, kdy se ukládá) ·
schéma `schema/save.schema.json` (verze uložení 3) · plán: METROPOLE_PLAN 4, M1 bod 11,
DUALSTACK 2 („formát uložení“ je P0) · parita F-025

## Účel

Lokální uložení postupu hráče, stejný JSON v obou klientech: hotovost, auta, Pas, nejlepší výsledky
miniher, stav feedu, NPC a nastavení. Bez cloudu a bez účtu (METROPOLE_PLAN 3). Jedno uložení na
město (`cityId`).

## Formát (verze 3)

Spec v2 (M2-S3): uložení verze 3 přidává `stations` (odemčené stanice metra, `specs/travel.md`).

```
{
  version: 3,
  cityId: "nyc",
  cash: int ≥ 0,
  cars: [carId],          // vlastní auta v pořadí, jak přibyla (stav cars.owned)
  car: carId,             // auto, se kterým hráč vyjede; vždy prvek cars
  stamps: ["kind:id"],    // razítka Pasu v pořadí získání (specs/passport.md)
  best: {minigameId: {stars, score}},
  plays: {spotId: int},   // dohrané smyčky na spotu (obtížnost, specs/loop.md)
  feed: {prefs: {engine: int}, visits: {spotId: int}, districts: [jméno čtvrti]},
  npc: {vibe: {characterId: int}, contacts: [characterId], recent: [skitId]},
  settings: {scheme: "a" | "b" | "c", night: bool},
  stations: [spotId]      // odemčené stanice metra v pořadí odemknutí (specs/travel.md)
}
```

- **Objevené památky a čtvrti** jsou razítka `landmark:*` a `district:*` ve `stamps` (zvláštní pole
  nemají, aby nebyly dva zdroje pravdy). Feed z nich bere `discovered` pro bonus za neobjevenou
  památku (`specs/feed.md`).
- Ukradené auto se neukládá: když hráč řídí cizí auto (`stolen`), uloží se `car = cars[0]`.
- `best` se mění jen zlepšením: víc hvězd, nebo stejně hvězd a vyšší skóre (`specs/loop.md`).

## Verze 1 (M1 kostra)

```
{version: 1, cityId, cash, stamps: [..], cars: [carId], best: {id: {stars, score}}}
```

## Modul `save` (P0)

Normalizace a migrace jsou pravidla, aby oba klienti ze stejného JSON načetli stejný stav.

### Config

`{cityId, startCash, startOwned: [carId], startCar, cars: [carId]}` – `start*` z `cars.*` v tuningu,
`cars` = id všech aut katalogu (`content/cars/`).

### Stav

Normalizované uložení verze 3 (tvar výše).

### init(config, seed)

Čerstvé uložení: `version 3`, `cityId`, `cash = startCash`, `cars = startOwned` (jen známá, bez
duplicit), `car = startCar`, je-li v `cars`, jinak `cars[0]`; ostatní prázdné (`{}`, `[]`),
`settings = {scheme: "a", night: false}`, `stations = []`. `seed` se nepoužívá.

### Akce `{by: "player", op: "load", save: <cokoli>}`

Výsledný stav = `normalize(save)`:

1. `save` není objekt, `version` není 1, 2 ani 3, nebo `cityId ≠ config.cityId` → čerstvé uložení.
2. Kontrola typů (podle verze): chybějící povinné pole nebo pole špatného typu (číslo místo
   řetězce, desetinné číslo místo celého, …) → čerstvé uložení. Povinná pole verze 1: `cash`,
   `stamps`, `cars`, `best`; verze 2 všechna pole formátu kromě `stations`; verze 3 všechna.
3. **Migrace 1 → 2:** `cash`, `stamps`, `best` se převezmou, `cars` z verze 1, `car = cars[0]`
   (po kroku 4), `plays`, `feed`, `npc` prázdné, `settings` výchozí.
   **Migrace 2 → 3:** vše se převezme, `stations = []`. Výsledek je vždy verze 3.
4. Normalizace (všechny verze):
   - `cash = max(0, cash)`;
   - `cars`: jen id z `config.cars`, bez duplicit (první výskyt); prázdné → jako v `init`;
     `car ∉ cars` → `cars[0]`;
   - `stamps`: bez duplicit (první výskyt) – neznámá razítka zahodí až Pas (`specs/passport.md`);
   - `best`: `stars` oříznuté do 0–3;
   - `plays`, `feed.visits`: záporné hodnoty → 0;
   - `settings.scheme` mimo `a`, `b`, `c` → `a`;
   - `stations`: bez duplicit (první výskyt); neznámé stanice zahodí až `travel` (`load`).
   - Klíče map se ve výstupu řadí (porovnání po kódových jednotkách), aby byl JSON stejný.

`legalActions` → `[]`, `aiAction` neexistuje, `result` → `null`.

## Úložiště (P2)

- **W:** IndexedDB, databáze `metropole`, store `save`, klíč `save:<cityId>`, hodnota = JSON
  řetězec. Když IndexedDB není (soukromé okno, chyba), `localStorage` pod stejným klíčem.
- **F:** soubor `save-<cityId>.json` v adresáři dokumentů aplikace (`path_provider`,
  `getApplicationDocumentsDirectory`). Zápis přes dočasný soubor a přejmenování (atomicky).
  SQLite z původního plánu odkládáme: jedno malé JSON uložení ho nepotřebuje.
- Nečitelný soubor / záznam = čerstvé uložení (normalizace výše), hra nespadne.

## Kdy se ukládá

- po každém výsledku smyčky (`specs/loop.md`),
- po koupi auta a po výběru auta v garáži,
- při pozastavení aplikace (F `AppLifecycleState.paused`/`inactive`, W `visibilitychange` → hidden
  a `pagehide`),
- načte se jednou při startu, před prvním snímkem (auto, razítka, hotovost, feed, NPC, nastavení).
- Ladicí panel (F tuning panel, W `?debug` tlačítko) má „Smazat uložení“: zapíše čerstvé uložení
  a znovu načte hru.

## Hraniční případy

- Uložení jiného města → čerstvé uložení tohoto města (to druhé zůstává pod svým klíčem).
- Auto z uložení, které už v katalogu není → zahozeno; žádné nezbude → start z tuningu.
- Verze vyšší než 2 (novější hra) → čerstvé uložení, v paměti; přepíše se až dalším uložením.

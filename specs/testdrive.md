# Zkušební jízda a ladicí hotovost

**version: 1** · P2 (jen UI klientů, bez vektorů a scénářů) · dogfooding Ol1na 2026-11-23
(„jak vyzkouším Roadster a jak Garáž? Furt tam mám jen jedno auto.“) · navazuje na
`specs/cars.md` v2 („Garáž“), `specs/garage.md` v2, `specs/economy.md` v1, `specs/save.md` v4 ·
parita F-075

## Účel
Hráč začíná s jedním autem a 0 hotovosti, Vega Roadster stojí 45 000 a minihra dá 100–300.
Aby šlo auto z nabídky vyzkoušet hned, má garáž **zkušební jízdu**: na chvíli si sedne do
kteréhokoli auta na prodej, zadarmo a bez vlastnictví. Pro ladění (garáž, tuning, vzhled)
přidává ladicí panel tlačítko, které přidá hotovost.

## Proč P2
Pravidla modulu `cars` (`specs/cars.md`) se nemění a o zkušební jízdě nevědí: stav aut
(`owned`, `driving`, `stolen`, `thefts`, `cash`) zůstává po celou jízdu takový, jaký byl po
vyjetí z garáže. Klient jen dočasně postaví těleso jiného auta (jako taxi směna,
`specs/minigames/taxi.md` „Start“) a po skončení vrátí těleso auta ze stavu. Proto žádná nová
akce, `version` modulu `cars` zůstává 2 a vektory `vectors/cars.json` se nemění. Totéž ladicí
hotovost: není to herní pravidlo, ekonomika (`specs/economy.md`) se nemění.

## Zkušební jízda (P2)
- **Nabídka:** v záložce **Auta** garáže (`specs/cars.md` „Garáž“) má každé auto na prodej
  vedle „Koupit“ tlačítko **Vyzkoušet** (`garageTestDrive`). Je aktivní vždy (i bez
  hotovosti); s kontejnerem vzduchu (Vega) taky.
- **Start:** stisk zavře garáž. Když hráč řídil cizí (ukradené) auto, klient nejdřív provede
  akci `select` prvního vlastního auta (`owned[0]`; ukradené odveze odtahovka jako při
  výběru v garáži). Řízené vlastní auto zůstane v garáži. Na parkovacím bodě garáže natočené
  podle `park_heading` vznikne těleso zkoušeného auta s parametry **z katalogu**: bez
  vylepšení (`specs/garage.md` „Účinek na jízdu“ jen pro vlastní auta) a s výchozím vzhledem
  (lak z katalogu, žádný polep, kola, podsvícení). Auto s `hop` má plný kontejner.
  Ohlásí se `carChanged` (běžící světová minihra skončí jako při přesednutí).
- **Odpočet:** `cars.test_drive_s` sekund **herního času** (krok jízdy; pod překryvy, v
  pauze a při minihře na celou obrazovku stojí). HUD ukazuje pilulku `testDriveLeft`
  (`{time}` = `m:ss`, zaokrouhleno nahoru, jako taxi) a v posledních
  `cars.test_drive_low_s` sekundách ji zvýrazní (`color.testDrive.low`, jinak
  `color.testDrive.pill`). Pilulka má křížek (`testDriveEnd`) pro předčasný konec.
  Název auta v HUD je jméno zkoušeného auta.
- **Konec:** vyprší čas, křížek, otevření garáže, přesednutí do zaparkovaného auta
  (`board`), výběr auta v garáži nebo start minihry (smyčka, `specs/loop.md`). Hráč sedí
  zase v autě ze stavu (`driving`, s jeho vylepšeními a vzhledem) **na místě a s natočením
  zkoušeného auta**, rychlost 0 (u přesednutí hned přesedne dál podle `specs/cars.md`:
  jeho vlastní auto zůstane zaparkované na tom místě). Zkoušené auto zmizí (nezaparkuje se,
  neodtáhne se). Toast `testDriveOver` (jen při vypršení času). Ohlásí se `carChanged`.
- **Uložení:** zkušební jízda se neukládá. Uložení (`specs/save.md`) během ní zapíše
  `cars`/`car` ze stavu aut (auto, ve kterém hráč vyjel), takže po znovunačtení hráč sedí ve
  svém autě. Přepnutí města nebo znovunačtení stránky jízdu ukončí.
- **Během jízdy jako obvykle:** hledanost a pokuty (`specs/police.md`), odtah po potopení,
  respawn (těleso zůstane zkoušené), přejezd metrem/taxi (`specs/travel.md`), skok Vegy
  (`specs/hop.md`), minihry na spotech (start minihry jízdu ukončí, viz Konec).
- **Taxi směna nejde:** dokud zkušební jízda běží, start minihry `taxi` (stanoviště taxi,
  `?mg=taxi`) se nespustí a smyčka ukáže toast `testDriveNoTaxi`; jízda pokračuje. (Taxi směna
  sama přesedá do taxíku a vrací předchozí těleso, se zkoušeným autem by vrátila cizí auto.)
- **Pořadí:** zkušební jízda nejde spustit během světové minihry (garáž se při ní otevřít dá,
  ale tlačítko je šedé).

## Ladicí hotovost (P2, jen ladění)
- Jen v ladicím režimu: W s `?debug` (nebo vývojový server), F v ladicím panelu (tuning
  panel). Bez něj tlačítko nikde není.
- Tlačítko `debugCash` („+{amount}“, `amount` = `economy.debug_grant`, 10 000) přidá hotovost
  stejnou cestou jako ekonomika: klient vezme `cash` ze stavu aut, přičte `debug_grant`,
  zapíše zpět (`cars.cash`, jako `setCash` po akci ekonomiky) a uloží (`specs/save.md`).
  `earned` ekonomiky se nemění. HUD hotovosti a otevřená garáž ukážou novou částku.

## Čísla, texty, barvy
- `content/tuning.yaml`: `cars.test_drive_s` (180.0), `cars.test_drive_low_s` (15.0),
  `economy.debug_grant` (10000).
- `i18n/`: `garageTestDrive`, `testDriveLeft` (`{time}`), `testDriveEnd`, `testDriveOver`,
  `testDriveNoTaxi`, `debugCash` (`{amount}`).
- `design/tokens.json`: `color.testDrive.pill`, `color.testDrive.low`.

## Hraniční případy
- Garáž bez spotu `garage` ve městě: tlačítko Garáž není, zkušební jízda taky ne.
- Zkoušené auto, které hráč mezitím koupí: koupit jde jen v garáži, a ta jízdu ukončí dřív.
- Vypršení času ve vzduchu (skok) nebo na mostě: auto se vymění na místě, jako respawn
  (`spawn`, na zemi pod autem).
- Hledanost při konci: zůstává (policie hledá hráče, ne auto).

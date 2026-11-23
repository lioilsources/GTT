# První spuštění: postup stahování a úvodní karta

**version: 1** · P2 (jen W; F až po vystřelení) · plán: `Prompts/05-METROPOLE_LAUNCH_PLAN.md` L-S7 ·
parita F-076 · texty `loadingProgress`, `introTitle`, `introLine1`…`introLine3`, `introCity`, `introGo`

## Účel

Lidé přijdou z odkazu na telefonu, často na mobilních datech. Musí vidět, že se něco stahuje
a kolik zbývá, a po načtení během pár vteřin pochopit, jak se jezdí a že můžou jet jinam.

## Postup stahování

- Během načítání města (od `current.json` po první snímek) ukazuje `#loading` text
  `loadingProgress` s `{city}` (jméno města) a `{pct}` (celé procento 0–99).
- Počítají se bajty čtení z balíčku před prvním snímkem: `manifest.pb`, `graph.pb`,
  `landmarks.pb`, `spots.pb`, `trams.pb` a chunky prvního přednačtení (vlastní chunk a okolí, 9).
- Celek: součet `Content-Length` odpovědí, které už dorazily; u chunků přednačtení se jejich
  `ChunkRef.bytes` z manifestu přičte hned, jakmile je známý (bez čekání na odpověď). Odpověď bez
  `Content-Length` přispěje jen do staženého, ne do celku.
- `pct = floor(99 · staženo / celek)`; nikdy neklesá (zobrazuje se maximum dosud), dokud
  není celek znám, platí `pct = 0`. 100 % se nezobrazuje: po načtení `#loading` zmizí.
- Chyba načtení se hlásí jako dosud (chybová obrazovka), procenta zmizí.

## Úvodní karta

- Po načtení prvního města, jednou na zařízení: karta přes hru s nadpisem `introTitle`, třemi
  řádky ovládání `introLine1`…`introLine3` (schéma A a klávesnice, `specs/controls.md`), nadpisem
  `introCity` a tlačítkem pro každé město z `CityId` (jméno z `cityIdNames`; aktuální město je
  zvýrazněné) a tlačítkem `introGo`.
- `introGo` nebo aktuální město kartu zavře a hra pokračuje. Jiné město kartu zavře a přepne město
  stejně jako aplikace Cesty (`specs/cities.md`).
- Zavření se pamatuje v `localStorage` pod klíčem `metropole:intro` (hodnota `1`). Čtení i zápis
  jsou v try/catch: když úložiště nejde, karta se ukáže při každém spuštění a hra jede dál.
- Karta se neukáže s parametry `?bench`, `?demo`, `?gallery`, `?mg`, `?skits`, `?cars`
  ani `?nointro` (automatické testy a odkazy na konkrétní věc).
- Karta hru pozastaví stejně jako překryvy ze `specs/pause.md` (pevný krok stojí, vstup se zahazuje).

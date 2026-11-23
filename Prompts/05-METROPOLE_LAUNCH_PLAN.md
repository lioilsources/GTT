# 05 – METROPOLE_LAUNCH_PLAN (přírůstek k 00–04)

Zadání Ol1na 2026-11-23. Ulož tento text beze změny jako `Prompts/05-METROPOLE_LAUNCH_PLAN.md`
a doplň ho do seznamu v `CLAUDE.md` (00 < 01 < 02 < 03 < 04 < 05). Plány 00–04 a hotové pod-plány
neměň. Založ `plans/L_LAUNCH.md` a milník **L** v `plans/progress.yaml` (položky níže, velikost
v závorce). Nejdřív dokonči rozdělanou feature, pak jeď L v uvedeném pořadí.

**Cíl:** repo a webový klient snesou veřejný odkaz. Ol1n zveřejní post se dvěma odkazy
(„Forkni to“ = repo, „Zahraj si“ = GitHub Pages), jakmile potvrdí Prahu s kopci. Lidé kliknou
z telefonu.

## Výchozí volby (dokud Ol1n neřekne jinak)

| # | Otázka | Default |
|---|---|---|
| L1 | Licence | kód a herní data (`content/` mimo `content/npc/`) MIT; `assets/` a `content/npc/` CC BY-NC 4.0; balíčky měst ODbL; držitel práv „Ol1n“ |
| L2 | Výšky Prahy | AWS Terrain Tiles; DMR 5G až po vystřelení |
| L3 | Terén, voda a les ve F (F-070–F-073) | až po vystřelení, post odkazuje na web; v `parity.yaml` zůstane F `todo` |
| L4 | M4 Tokio (styl D, vozidla, minihry, skity) | až po L |
| L5 | Nástroje | žádný shell: Go v `tools/metro`, Node v `web/scripts` |

## A – Praha s kopci (brána vystřelení, jen W)

- **L-S1 (M) T3 ladění kopců Prahy** (= M5-S10 bez miniher z reliéfu). Tři ověřovací trasy:
  Petřín, Letná, Hradčany; ulice vyber ze `steepest.json` náhledu a z grafu balíčku, nic
  nevymýšlej. Trasy ve formátu `content/bench/` (`specs/bench.md`, případně vyšší verze).
  Každá má odkaz `?city=prague&route=<id>` (start na trase, navigace zapnutá).
  `docs/prague-hills.md`: trasa → odkaz → na co se dívat (ztráta rychlosti do kopce, skok,
  stínování, HUD sklon a výška) → klíče `tuning.yaml`, které jdou ladit v panelu.
  Akceptace: všechny tři trasy projede autopilot bez vyproštění; M5-A5 čeká na Ol1na.

## B – Repo snese „Forkni to“

- **L-S2 (S) README podle skutečnosti.** Dnes tvrdí „Stav: M0 – Hračka … bez provozu, chodců,
  policie, feedu, miniher a ukládání“ a u webu „fáze D0: prázdná scéna“. Nahoru: jedna věta, co
  to je, odkaz na Pages, obrázek, parametry URL (`?city=`, `?gallery`, `?mg=`, `?spot=`), R7 a R10
  jednou větou, „Jak přidat město“ v pěti krocích, licence a zdroje dat. Blok stavu mezi značkami
  `<!-- metro:status -->` generuje `metro progress` (města, minihry W/F, auta, památky, skity,
  testy, parita obou / jen W / jen F, datum). `metro progress --check` v CI spadne, když je blok
  starý.
- **L-S3 (S) Počítadla v `metro progress`.** Skity ukazují 0 / 392, v `content/npc/skits/` je 50
  souborů. Minihry ukazují 34, `content/minigames/catalog.yaml` má 33. Oprav zdroj obou čísel
  a přidej test v `tools/metro/internal/progress`.
- **L-S4 (S) Tracker dorovnat.** (a) U rozdělaných položek (M2-S9D, M2-S9E, M5-S6, M5-S7, M5-S8)
  zapiš do důkazu, co je hotové ve W a co chybí ve F. (b) `plans/progress.log` končí
  22. 11. 16:31; doplň session od té doby z historie gitu (pravidlo 5). (c) Počítadlo testů je
  1038 / 1039 z 23. 11. 04:23: najdi padající test, oprav ho nebo napiš, proč padá, pak
  `metro progress --tests`.
- **L-S5 (S) Licence a zdroje.** `LICENSE` podle L1. `NOTICE` se zdroji dat a jejich podmínkami
  (OpenStreetMap ODbL, Overture, AWS Terrain Tiles, Street Tree Census, modely z
  `assets/LICENSES.md`). Pole `license` ve `web/package.json` a `pubspec.yaml`. Audit R10: projdi
  `i18n/`, `content/`, názvy assetů a texty pro story v `docs/release.md` na reálné značky a jména
  lidí; nálezy vypiš do PR, oprav jen to, co vidí hráč.

## C – První dojem na telefonu (jen W)

- **L-S6 (M) Kouřový test mobilního webu v CI.** Headless Chromium se dvěma mobilními profily
  (rozměry Pixel 8a a iPhone 12 mini, dotyk); nástroj vyber a přidej do devDependencies. Kroky:
  kořenová URL se načte, první snímek do rozpočtu, 5 s jízdy dotykem pohne autem, telefon se
  otevře a feed jde přejet nahoru i dolů, přepnutí NYC → Praha → Tokio, konzole bez chyb.
  Rozpočty navrhni ve `specs/bench.md` a změř je, čísla do `tuning.yaml`.
- **L-S7 (S) První spuštění.** Při stahování balíčku ukazatel postupu v procentech (lidé jsou na
  mobilních datech). Po načtení jednorázová karta: ovládání ve třech řádcích a výběr města. Texty
  v `i18n/`, zavření se pamatuje v `localStorage` v try/catch.
- **L-S8 (S) Náhled odkazu.** `web/index.html` nemá žádná `og:` metadata. Doplň `og:title`,
  `og:description`, `og:image`, `og:url` a `twitter:card`; obrázek je `web/public/og.png` z L-S9.
- **L-S9 (M) Demo záběr.** `?demo=roadster`: Praha, Vega Roadster, autopilot jede do kopce, před
  ním kolona za tramvají, skok s přemetem, dopad, dojezd. Bez ladicího HUD, na výšku 1080×1920,
  20–30 s. `web/scripts/demo.ts` nahraje `run/media/demo_roadster.webm` (do gitu ne) a zvlášť
  uloží snímek na šířku 1200×630 do `web/public/og.png` (použij ho i v README).
  Akceptace: dvě nahrání dají stejnou polohu auta v 10. sekundě.

## D – Nálezy z dogfoodingu (Ol1n, 21.–23. 11.)

Každý nález nejdřív zopakuj jako scénář ve `scenarios/` nebo unit test. Když zopakovat nejde,
dej položku do „čeká na Ol1na“ s otázkou (město, místo, auto) a nehádej. Oprava = vyšší verze
specifikace → W → F → parita.

- **L-S10 (M) Tramvaje zatáčejí v ostrém úhlu.** Směr tramvaje má plynule sledovat kolej
  (`specs/trams.md`). Akceptace: na celé síti Prahy je změna směru na metr dráhy pod limitem
  z `tuning.yaml`; test přes všechny hrany kolejí.
- **L-S11 (M) Auto jede pod mostem a přes řeku.** Očekávané chování: do vody = pád a odtah
  (`specs/nature.md`), na most jen z nájezdu, pod mostem se dá projet po nábřeží. Test přes
  všechny mosty všech tří balíčků: trasa z břehu na břeh drží auto ve vrstvě mostovky, nájezd do
  vody kdekoli na břehu spustí pád.
- **L-S12 (M) Policie zablokuje hru.** Hlídky ani zátaras nesmí hráče uvěznit. Po kartě „Dopaden“
  hlídky uvolní cestu; vyproštění ze `specs/flow.md` platí i pro sevření vozidly. Scénář
  `police_box` (tři hlídky kolem stojícího auta) a soak 20 dopadení po sobě bez zaseknutí.
- **L-S13 (S) Regresní testy na už opravené:** průjezd zaparkovanými auty (PR #54–#56) a swipe
  feedu (PR #205–#211). Ověř, že je hlídá scénář nebo test; kde ne, doplň.

## E – Ol1nův ověřovací průchod a čísla

- **L-S14 (M) `docs/verify.md` z `metro progress`.** Položky „čeká na Ol1na“ (dnes 55) seskup do
  průchodů po 30 minutách na telefonu: město → odkaz na W s parametry → co má nastat →
  zaškrtávátko. Co jde ověřit jen ve F, dej zvlášť. „Ověřeno“ zapisuj jen po Ol1nově výslovném
  potvrzení.
- **L-S15 (S) `metro stats` → `plans/STATS.md`.** Čísla pro post: od prvního commitu po poslední,
  hodiny s commitem, commity, smergované PR, špička PR za hodinu, řádky podle jazyka (ruční /
  generované / testy), testy, obsah, čas od prvního commitu města po uzavření jeho milníku.
  Pravidlo 6 v PROGRESS.md platí dál; STATS je mimo měření postupu.

## Akceptace L

`docs/launch.md` se seznamem toho, co zbývá jen Ol1novi, v pořadí: tři pražské trasy na telefonu,
M5-A5, licence (L1), schválení demo záběru, post. `metro progress --check` a kouřový test jsou
zelené na `main`, Pages nasazené.

## Po vystřelení (pořadí, položky už existují)

F-070–F-073 ve F, pak F-065–F-068 ve F, DMR 5G pro Prahu (M5-S4), M4 Tokio.

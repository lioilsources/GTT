# METROPOLE_DUALSTACK_PLAN.md

**Stav:** dodatek k `METROPOLE_PLAN.md`. Při rozporu platí tento dokument.
**Datum:** 2026-11-21
**Pro:** kódovací model (Opus, střední effort). **OVĚŘ** = ověř v dokumentaci, než na tom postavíš kód. Kapitola 12 = rozhoduje Ol1n, do té doby platí default.

**Co mění v hlavním plánu:** R2 (jeden codebase → dva klienti), kap. 6.2 (výška budov ve webu), 7.2 (fyzika na obou stranách), 9.1 (kontrakt miniher i v TypeScriptu), 13 (monorepo se dvěma klienty), M0 bod 5 (web build → webový klient).

---

## 1. Záměr

Hra vzniká ve dvou klientech:

- **F** – Flutter + Flame → App Store, Google Play.
- **W** – TypeScript + Babylon.js → GitHub Pages. Hráč otevře odkaz a hraje, bez instalace.

Dva klienty jde udržet jen tehdy, když se zdvojuje pouze prezentace. Všechno ostatní (obsah, pravidla, čísla, texty, testy) existuje jednou ve sdílené vrstvě a oba klienti to čtou nebo proti tomu skládají zkoušku.

## 2. Utáhne to Babylon.js?

Ano. Rozsah M1 je pár set viditelných budov a desítky tisíc trojúhelníků, to je pro WebGL2 malá zátěž. Babylon.js je v řadě 9.x, vychází průběžně a podporuje WebGL2 i WebGPU.

Limity leží jinde než v enginu:

- **Paměť mobilního prohlížeče** – textury a geometrie chunků se musí uvolňovat.
- **Počet draw calls** – statická geometrie sloučená po chunku, opakované věci instancovaně.
- **Velikost stahování** – první snímek do pár MB, město se dotahuje po chunkách.
- **Zvláštnosti iOS Safari** – odemčení zvuku, ztráta WebGL kontextu, celá obrazovka.

Výchozí backend je **WebGL2**. WebGPU je na iOS zapnuté až od verze 26 a na Androidu jen na části zařízení, navíc jsou z praxe hlášené chyby na iOS. Proto jen jako volitelný přepínač `?gpu=webgpu`, nikdy jako podmínka.

Jestli to utáhne i v mobilním prohlížeči na Ol1nových referenčních telefonech, se neodhaduje, ale změří ve fázi D1 (kap. 10).

## 3. Dva klienti, jedno monorepo

| | F | W |
|---|---|---|
| Stack | Flutter, Flame, Forge2D | TypeScript, Babylon.js, planck.js, Svelte |
| Distribuce | story | GitHub Pages, odkaz |
| Rozsah | plná hra | bezplatná část: první město a jeho minihry |
| Platby | IAP | žádné |
| Svět | 2,5D vytažení | pravé 3D se stejným obrazem (kap. 6.2) |
| Navíc | haptika, notifikace, instalace | deep linky, sdílení, PWA |

Všechno je v jednom repozitáři `metropole/`, který už založil hlavní plán. **Nic existujícího se nestěhuje ani nepřejmenovává**, druhý stack se jen přidává:

```
metropole/
  app/  packages/            klient F (beze změny)
  web/                       klient W (nové)
  content/  tools/  plans/   sdílené (beze změny, tools se rozšíří)
  specs/  vectors/  scenarios/  schema/  i18n/  design/  assets/  parity.yaml   sdílené (nové)
```

Vlastnictví cest:

| Session | Smí měnit |
|---|---|
| FLUTTER | `app/**`, `packages/**` |
| WEB | `web/**` |
| SHARED | všechno ostatní |

Aby mohly session běžet souběžně v jednom repu, pracuje každá ve vlastním git worktree na vlastní větvi s prefixem (`flutter/…`, `web/…`, `shared/…`) a do `main` jde přes PR. `metro guard` v CI shodí PR, který sahá mimo cesty své větve. Cizí cesty mění jen session, které patří.

## 4. Úrovně parity

| Úroveň | Význam | Co sem patří | Jak se hlídá |
|---|---|---|---|
| **P0** | shodné do posledního stavu | obsah, texty, pravidla diskrétních miniher (`cards`, `board`, `dice`, `tiles`, `puzzle`), AI soupeři, výběr karet feedu, GPS trasa, hvězdy a odměny, výběr dialogů, formát uložení | zlaté vektory |
| **P1** | stejné v toleranci ±5 % | fyzika jízdy, provoz a chodci, policie, spojité minihry (`flick`, `arcade`, `sport`, `service`, pocit v `rhythm`; beatmapy jsou data = P0) | scénáře s metrikami |
| **P2** | volné | technika vykreslení, světla, efekty, UI toolkit, funkce platformy | — |

Hranice P2: výchozí kamera, ovládání a čitelnost jsou v obou klientech stejné. Co umí jen jeden klient (náklon kamery ve W), smí být jen volitelný přepínač, ne výchozí stav.

## 5. Sdílená vrstva (kořen monorepa)

### 5.1 Struktura

```
metropole/      (jen sdílené cesty)
  content/      cities/, cars/, dialogues/, minigames/, tuning.yaml   (existuje)
  i18n/         <locale>.json – jediný zdroj textů
  design/       tokens.json – barvy, písmo, rozestupy, poloměry
  assets/       sprity, portréty, zvuky (nad ~200 MB přejít na manifest + úložiště)
  schema/       JSON Schema: obsah, uložení, meta minihry
  specs/        chování modulů, jeden soubor na modul
  vectors/      zlaté vektory P0
  scenarios/    scénáře P1
  parity.yaml   matice parity
  tools/        citypack (existuje; proto zůstává v tools/citypack/proto), metro (nové), dialoggen, artgen
  plans/        METROPOLE_PLAN.md, tento dokument, pod-plány   (existuje)
```

`metro` je nový Go CLI vedle `citypack`, s podpříkazy `gen`, `sync`, `validate`, `vectors`, `parity`, `guard`. `citypack` zůstává, jak ho staví hlavní plán, a dostane navíc `publish` a `pull`.

Hotové citypacky nejsou v gitu (`build/packs/` je v `.gitignore`). `citypack publish` je nahraje jako přílohy GitHub Release, `citypack pull` je stáhne podle `packs.lock`, takže je CI nemusí stavět. F si první město přibalí do instalace. W si je při buildu zkopíruje do webu, protože prohlížeč za běhu z Releases stahovat nemůže (CORS – **OVĚŘ**).

### 5.2 Žádná herní konstanta v klientovi

Čísla, identifikátory, texty a barvy žijí jen ve sdílené vrstvě. `metro gen dart` a `metro gen ts` z nich vygenerují typované konstanty a přístupy:

- `tuning.yaml` → `Tuning`
- identifikátory miniher, enginů, aut, měst → výčty
- `i18n/*.json` → ARB pro Flutter, JSON pro web
- `design/tokens.json` → konstanty tématu pro Flutter, CSS proměnné pro web
- `tools/citypack/proto/` → kód Protobuf pro oba jazyky
- `schema/` → typy uložení a meta miniher

Výstup jde do `packages/shared_gen/` (F) a `web/src/gen/` (W) a commituje se. CI spouští `metro gen --check` a spadne, když vygenerovaný kód neodpovídá sdíleným souborům.

Soubory, které klient potřebuje za běhu (obsah, assety, ARB), kopíruje `metro sync` do `app/assets/shared/` a `web/public/shared/`. Obě složky jsou v `.gitignore` a `metro sync` běží před každým buildem.

### 5.3 Specifikace

Každý modul s chováním má `specs/<modul>.md` se stejnou osnovou: účel, stav, akce, pravidla, AI, mapování na hvězdy, hraniční případy, celé číslo `version`. Změna chování = zvýšení verze = nové vektory. Kód bez specifikace se do žádného klienta nepíše.

### 5.4 Vektory (P0)

Pravidlový modul má v obou jazycích stejný tvar:

```
init(config, seed)            -> State
legalActions(state)           -> Action[]
apply(state, action)          -> State      // čistá funkce
aiAction(state, level, rng)   -> Action
result(state)                 -> null | Result
```

Vektor je záznam partie: konfigurace, seed, posloupnost akcí a stav po každé z nich. Vektory nahrává session SHARED příkazem `metro vectors record --client <vedoucí> --module <id>`, který spustí pravidla vedoucího klienta. Člověk je zkontroluje, pak jsou zmrazené. Druhý klient je musí přehrát se shodou na každém kroku.

```json
{
  "module": "sirky",
  "specVersion": 1,
  "cases": [{
    "name": "hrac-vezme-2-z-15",
    "config": {"start": 15, "maxTake": 3},
    "seed": 42,
    "steps": [
      {"action": {"by": "player", "take": 2}, "state": {"left": 13, "turn": "ai"}},
      {"action": {"by": "ai", "level": 5},    "state": {"left": 12, "turn": "player"}}
    ],
    "result": null
  }]
}
```

(Ukázka formátu, ne závazná data.)

Pravidla determinismu pro kód P0:

- jen celá čísla, řetězce, booleany, pole a objekty; žádná desetinná čísla, žádný čas, žádné řazení závislé na jazyce
- klíče se při porovnání řadí abecedně; nespoléhat na pořadí hashovacích map
- rozpočet AI v hloubce nebo počtu iterací, nikdy v milisekundách
- při shodě hodnocení vyhrává první tah v kanonickém pořadí z `legalActions`

**Společný generátor náhodných čísel** (`specs/prng.md`):

```
stav x: uint32, nenulový (seed 0 se nahradí 0x9E3779B9)
nextU32():  x ^= x << 13;  x ^= x >>> 17;  x ^= x << 5;  vrať x     // vše na 32 bitech
nextInt(n): limit = floor(2^32 / n) * n;  opakuj r = nextU32() dokud r >= limit;  vrať r mod n
shuffle(a): pro i od délka-1 dolů do 1:  j = nextInt(i + 1);  prohoď a[i], a[j]
```

V Dartu po každém posunu doleva maskuj `& 0xFFFFFFFF`, v TypeScriptu `>>> 0`. Referenční hodnoty (jdou do `vectors/prng.json`):

- seed 1, pět volání `nextU32()`: 270369, 67634689, 2647435461, 307599695, 2398689233
- seed 1, `shuffle([0..9])`: [3, 1, 0, 2, 6, 7, 8, 5, 4, 9]
- seed 42, osm hodů kostkou `nextInt(6) + 1`: [1, 5, 4, 3, 1, 1, 1, 5]

### 5.5 Scénáře (P1)

Scénář = záznam vstupů v čase + očekávané metriky s tolerancí. Hodnoty nahraje vedoucí klient.

```json
{
  "module": "drive",
  "car": "sedan_01",
  "name": "rozjezd-a-brzdeni",
  "inputs": [{"t": 0, "throttle": 1, "steer": 0}, {"t": 8, "brake": 1}],
  "expect": {
    "cas_na_25_mps_s":   {"value": 0, "tol": 0.05},
    "brzdna_draha_m":    {"value": 0, "tol": 0.05}
  }
}
```

(Ukázka formátu; nuly nahradí hodnoty nahrané z vedoucího klienta.)

Povinná sada pro jízdu: rozjezd na cestovní rychlost, maximální rychlost, brzdná dráha, poloměr ustáleného zatáčení při 15 m/s, úhel driftu po ruční brzdě při 20 m/s, čas kola na testovací dráze z nahraných vstupů.

### 5.6 Matice parity

```yaml
# parity.yaml
- id: F-012
  name: Sirky (duel)
  level: P0
  spec: specs/minigames/sirky.md@1
  lead: web
  web: done          # todo | wip | done
  flutter: wip
  checks: {web: pass, flutter: fail}
```

`metro parity report` z ní a z výstupů testů obou klientů vyrobí `PARITY.md` a skončí chybou, když má vydávaná verze červený řádek.

Testy klienta přehrávají vektory jen u řádků, kde má klient stav `done`. Stavy `todo` a `wip` se hlásí jako čekající, takže vedoucí klient může být napřed a `main` zůstane zelený. Když změna specifikace rozbije už hotového druhého klienta, tentýž PR mu vrátí stav `wip`.

## 6. Klient W (`web/`)

### 6.1 Stack

TypeScript (strict), Vite, Babylon.js 9.x (`@babylonjs/core`, importovat jen použité moduly), planck.js, Svelte pro telefon, feed, menu a UI minihry, Vitest pro unit testy a přehrávání vektorů. Runtime pro Protobuf v TypeScriptu **OVĚŘ** a vyber jeden. Žádný backend.

Názvy API Babylon.js uvedené níž **OVĚŘ** v dokumentaci řady 9.x.

### 6.2 Pravé 3D se stejným obrazem jako F

F posouvá body střechy podle `s(h)` z `tuning.yaml` (hlavní plán 6.2). W dostane totožný obraz takto:

- Kamera je kolmo nad hráčovým autem ve výšce `H = 1 / k` (při `k = 0.004` je to 250 m) a dívá se přímo dolů.
- Budova se nestaví do skutečné výšky, ale do zobrazené výšky `z = H · (1 − 1 / s(h))`. Perspektivní zvětšení ve výšce `z` je `H / (H − z) = s(h)`, tedy stejné jako v F. Příklad: 20 m → 18,5 m; strop `max_scale = 2.2` → 136 m.
- Přiblížení se dělá změnou zorného úhlu: `fovX = 2 · atan(view_width / (2H))`, tedy asi 11° až 19° pro záběr 50–85 m.
- Auto je na `car_anchor` díky posunuté (off-axis) projekci, ne posunem kamery.
- Mosty a estakády leží ve výšce `deck_lift_m` × vrstva (default 6 m). F je kreslí bez posunu; rozdíl je pod 3 % a spadá do P2.

Náklon kamery je volitelný přepínač (P2), výchozí je pohled shora.

### 6.3 Výkon

Rozpočty (ladí se v D1): 60 fps na obou referenčních telefonech v Chrome na Androidu a v Safari na iOS; nejvýš 150 draw calls; nejvýš 300 tisíc viditelných trojúhelníků; první snímek po stažení do 5 MB; halda JS do 300 MB.

Postupy:

- geometrie chunku se staví přímo z předtriangulovaných dat citypacku do jedné sítě na materiál; světové matice a materiály zmrazit
- rekvizity jako thin instances; auta a chodci jako sprity z atlasu na ploškách (stejné sprity jako F)
- textury v atlasech, komprimované (KTX2/Basis)
- při uvolnění chunku `dispose` sítí i textur
- žádné alokace v herní smyčce
- obsluha ztráty a obnovy WebGL kontextu

Úrovně kvality se volí automaticky podle měření prvních sekund: **nízká** (bez stínů a záře, snížené rozlišení vykreslování), **vysoká** (záře oken v noci, vyhlazování).

### 6.4 Jízda

Fyzika v planck.js, vykreslení v Babylonu. Stejně jako F: pevný krok 1/60 s, 8 rychlostních a 3 poziční iterace (nastav výslovně v obou knihovnách, jejich výchozí hodnoty se mohou lišit – **OVĚŘ**), stejný model pneumatik z hlavního plánu 7.2, stejné kolizní polygony z citypacku, stejné parametry aut. Poloha z 2D fyziky se jen přepisuje do 3D transformace. Havok ani jiná 3D fyzika se nepoužívá.

### 6.5 UI a minihry

Kontrakt je zrcadlo Dartového `mg_api`, typy generované ze `schema/`:

```ts
export interface Minigame {
  meta: MinigameMeta;
  mount(host: HTMLElement, ctx: MinigameContext,
        onFinish: (r: MinigameResult) => void): () => void;   // vrací unmount
}
```

Diskrétní hry = Svelte + SVG/DOM. Arkády = Canvas 2D. Během minihry se vykreslování světa pozastaví.

### 6.6 Specifika webu

- **Vstup:** Pointer Events, `touch-action: none`, stejná tři schémata ovládání; na desktopu navíc klávesnice.
- **Zvuk:** odemknout prvním dotykem.
- **Ukládání:** IndexedDB, stejné schéma jako F. Přenos mezi klienty později exportním kódem.
- **Deep linky:** `?mg=sirky&seed=42&level=3` otevře minihru, `?city=nyc&spot=<id>` postaví hráče na místo. Slouží dogfoodingu, hlášení chyb i promu.
- **Galerie miniher:** `/gallery`.
- **PWA:** service worker cachuje aplikaci a stažené chunky; možnosti celé obrazovky na iOS **OVĚŘ**.

### 6.7 Nasazení na GitHub Pages

Workflow `web.yml` se spouští při změně ve `web/**` nebo ve sdílených cestách na `main`: `metro gen --check`, `metro sync`, `npm ci`, testy a vektory, `vite build`, `citypack pull` do `web/dist/packs/`, nasazení `web/dist` na Pages. Hráč žádný build nevidí.

- Aplikace bez cache (`index.html`), ostatní soubory s hashem v názvu.
- Balíčky pod `packs/<city>/<verze>/`.
- Základ adres pro balíčky a assety je konfigurační `ASSET_BASE_URL`, aby šly těžké soubory přesunout jinam beze změny kódu.

Limity Pages: publikovaný web do 1 GB, měkký limit přenosu 100 GB měsíčně, nasazení do 10 minut. Při balíčku města 30 MB je to řádově 3 300 stažení města měsíčně; nad to přesunout `packs/` a `assets/` na jiný statický hosting. Pages nejsou určené pro obchod a platební transakce: na webu žádný prodej, jen odkazy do storů.

## 7. Klient F (`app/` + `packages/`)

Platí hlavní plán i jeho struktura adresářů, s těmito změnami:

- Nový balíček `packages/shared_gen/` s generovaným kódem; herní čísla se čtou jen přes něj.
- `flutter test` přehrává vektory a scénáře z kořene repa.
- Pravidla miniher jsou čisté moduly tvaru z 5.4, bez závislosti na UI.
- Workflow `flutter.yml` se spouští při změně v `app/**`, `packages/**` nebo ve sdílených cestách.
- Fyzika: Forge2D s parametry z kap. 6.4.
- M0 bod 5 (web build z Flutteru) odpadá, nahrazuje ho klient W.

## 8. Postup: jedna feature, dva klienti

Session: SHARED, WEB, FLUTTER, koordinuje Director. Každá feature má id `F-###`, které se objeví v názvech větví a v `parity.yaml`. Každý krok je samostatný PR do `main`.

1. **SHARED:** specifikace (nová nebo vyšší verze), změny obsahu a schémat, `metro gen`, řádek v `parity.yaml`.
2. **Vedoucí klient:** implementace ve svých cestách, dogfooding.
3. **SHARED:** nahraje vektory nebo scénáře z vedoucího klienta, kontrola, vedoucímu nastaví `done`.
4. **Druhý klient:** implementace, dokud vektory neprojdou.
5. **SHARED:** druhému klientovi nastaví `done`; `metro parity report` zelený → feature hotová.

**Kdo vede:** nový kód vede W (nejrychlejší smyčka: push, odkaz, zkusit na telefonu). Převzetí existující Flutter hry vede F. Výjimka: M0 už ve Flutteru vzniká, takže pro M0 vede F a W dohání. Vedoucí je zapsaný v `parity.yaml`.

**Limit rozpracovanosti:** v jednom modulu smí být druhý klient pozadu nejvýš o jednu feature. Dokud nedožene, vedoucí v tom modulu nezačíná další.

**Chyba nalezená v jednom klientovi:** nejdřív rozhodni, jestli je chybná specifikace, nebo implementace. V obou případech přidej vektor, který chybu zachytí; projít ho musí oba klienti.

**Hotovo znamená:** specifikace sloučená, vektory nebo scénáře zmrazené, oba klienti prošli, řádek v matici zelený, vyzkoušeno na telefonu v aplikaci i přes odkaz.

**Vydání:** build pro story se dělá z commitu na `main`, kde jsou všechny obsažené feature v matici zelené. Web se nasazuje průběžně a smí být napřed o feature, které vede.

## 9. Přepis existující hry

Pro převzetí hotové Flutter hry (kandidáti z hlavního plánu 9.4) i pro opačný směr:

1. Sepiš, co hra dělá: stav, akce, pravidla, AI, vstupy, assety.
2. Pokud jsou pravidla v původním kódu promíchaná s UI, nejdřív je tam odděl do čistého modulu tvaru z 5.4.
3. Napiš `specs/minigames/<id>.md` podle kódu.
4. Nahraj z původního kódu vektory (P0) nebo scénáře (P1).
5. Přesuň grafiku a zvuk do `assets/` v kořeni repa.
6. Implementuj v druhém klientovi, dokud vektory neprojdou.
7. Obal kontraktem miniher, přidej do Galerie, zapiš do `parity.yaml`.

Kód se nepřekládá řádek po řádku. Přepisuje se podle specifikace a správnost hlídají vektory.

## 10. Fáze

| Fáze | Obsah | Vztah k hlavnímu plánu |
|---|---|---|
| **D0 – Sdílený základ** | nové sdílené složky; `tools/metro` (`gen`, `sync`, `guard`, kostra `vectors` a `parity`); `packages/shared_gen/`; schémata; PRNG se spec a vektory; workflow `web.yml`, `flutter.yml`, `shared.yml`; složka `web/` s prázdnou scénou Babylonu nasazenou na Pages | vloží se do běžícího M0 |
| **D1 – Souboj M0** | hračka M0 v obou klientech ze stejného citypacku a `tuning.yaml`; měření; zpráva; brána G1 | = M0 |
| **D2 – První minihry** | kontrakt a Galerie v obou; Sirky jako první; pak Oko, Dáma, Desetitisíc; pak Šipky, Koulená, Střelnice; Taxi | část M1 |
| **D3 – M1 v obou** | celá smyčka v obou klientech, matice pro rozsah M1 zelená; W veřejně na odkazu, F v TestFlightu a Play internal | = M1 |

### Napojení na běžící práci

Hlavní plán už běží. D0 spouští jedna session sama, ve chvíli, kdy session pracující na M0 dokončí rozdělaný bod a má čistý strom. D0 nic nestěhuje. Do existujícího kódu zasáhne jen dvěma způsoby: herní čísla zapsaná natvrdo přepojí na `shared_gen`, a pokud už existují texty v ARB, přesune je do `i18n/` (ARB se pak generuje). Po D0 pokračuje M0 ve Flutteru a souběžně vzniká M0 ve `web/`.

### D1: měření

Na obou referenčních telefonech, F jako aplikace, W v prohlížeči:

- fps (průměr a 1 % nejhorších snímků) při přehrání nahraných vstupů: průjezd Times Square a 42nd St od řeky k řece
- čas od otevření do prvního hratelného snímku (Wi-Fi a mobilní data)
- paměť po 10 minutách jízdy
- teplota a úbytek baterie po 10 minutách
- Ol1nův dojem z ovládání po týdnu

Výstup: `plans/BAKEOFF_REPORT.md`.

### Brána G1 (rozhoduje Ol1n)

| Výsledek | Co následuje |
|---|---|
| Oba klienti drží 60 fps a hrají se stejně | oba stacky podle tohoto plánu (default) |
| W drží, F ne | jeden stack W + obal pro story; hlavní plán se přepíše pro W |
| F drží, W na telefonech ne | jeden stack F; W zůstane jako ukázka M0 pro desktop |

## 11. Náklady, rizika, pojistka

- **Cena:** obsah, pipeline, specifikace a testy se nenásobí. Klientský kód ano. Odhad: druhý klient přidá 60–80 % práce u prezentačně těžkých částí (svět, jízda, spojité minihry) a 20–30 % u diskrétních pravidel. Je to odhad, upřesní ho D1 a D2.
- **Rozcházení klientů:** hlídá matice a limit rozpracovanosti.
- **Dvojí povrch pro chyby:** každá chyba končí vektorem.
- **Placená verze nesmí vypadat hůř než web zdarma:** proto stejný obraz (6.2) a hranice P2 (kap. 4).
- **Pojistka:** když je druhý klient pozadu o víc než jeden milník, nebo má matice přes 5 červených řádků déle než 14 dní, druhý klient se zmrazí na posledním zeleném milníku a zůstane jako ukázka, dokud Ol1n nerozhodne.

## 12. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| W1 | Rozsah webu: bezplatná část (první město), nebo plná hra? | bezplatná část |
| W2 | Kdo vede nový kód? | W |
| W3 | Souběžné session v monorepu (worktree + vlastnictví cest), nebo vždy jen jedna session najednou? | souběžně |
| W4 | Svelte pro UI ve webu? | ano |
| W5 | Doména webu a kam s těžkými soubory po překročení limitů Pages? | github.io, řešit až při růstu |
| W6 | Web úplně bez build kroku (čisté ES moduly, bez TypeScriptu a Svelte)? | ne, build běží v Actions |
| W7 | Prahy pojistky z kap. 11 | 1 milník / 5 řádků / 14 dní |

## 13. Zdroje

- Babylon.js – vydání: https://github.com/BabylonJS/Babylon.js/releases
- WebGPU – stav implementací: https://github.com/gpuweb/gpuweb/wiki/Implementation-Status
- WebGPU v hlavních prohlížečích: https://web.dev/blog/webgpu-supported-major-browsers
- WebGPU na iOS, hlášená chyba: https://bugs.webkit.org/show_bug.cgi?id=301627
- GitHub Pages – limity: https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits
- planck.js: https://github.com/piqnt/planck.js

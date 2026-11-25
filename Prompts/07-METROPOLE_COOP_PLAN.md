# METROPOLE_COOP_PLAN.md

**Stav:** inkrement. Starší plány se nemění, tento dokument je doplňuje. Rozhodnutí R12 a kapitolu 3 plánu 00 mění jen v rozsahu kap. 3 níže.
**Datum:** 2026-11-25
**Pro:** kódovací model (Opus, střední effort). **OVĚŘ** = ověř v dokumentaci, v kódu nebo měřením, než na tom postavíš kód. Kapitola 12 = rozhoduje Ol1n, do té doby platí default. Server nasazuj a zásady ochrany soukromí zveřejňuj až na Ol1nův pokyn.

---

## 1. Cíl

Ve městě jezdí další lidé a hráč s nimi může něco podnikat. Ve hře se tomu říká **Spolu**.

- hráč vidí ostatní řidiče a na první pohled je odliší od provozu
- domluví se s nimi bez psaní, hotovými signály, které zvou ke hře
- má důvod za nimi dojet a důvod se k nim vracet
- zahraje si s nimi minihru, proti sobě i v týmu
- hráči z webu a z appek (iOS, Android) jsou ve stejném městě spolu
- když zrovna nikdo online není, město nese stopy lidí, kteří tu byli

Hra dál jede bez sítě stejně jako dnes. Spolu je vrstva navíc, kterou jde vypnout.

**Největší potíž je málo lidí.** Po vystřelení bude online naráz spíš 0–10 lidí než stovky, a to ve čtyřech městech. Návrh proto stojí na třech věcech: soustředit lidi na jedno místo (město dne, sraz v celou hodinu), dát jim věci, které fungují s odstupem času (výzvy, cedulky, stopy), a usnadnit pozvání vlastních známých odkazem. Živé setkání cizích lidí je třešnička, ne základ.

## 2. Co do hry nejde

| Věc | Do hry? | Důvod |
|---|---|---|
| Volný chat, hlas, vlastní jména a obrázky | **ne** | Moderování, rating ve storech, R10 (značky a jména lidí), jazyky. Zadání: žádný chat. |
| Účty a přihlášení (e-mail, Apple, Google) | **ne** | Není potřeba. Stačí anonymní ID v zařízení (C3). |
| Skutečná poloha hráče | **ne** | Posílá se jen poloha auta ve hře. |
| Srážky a strkání mezi lidmi | **ne** | Zpoždění na mobilních datech dělá z nárazů teleporty, zve to ke škodění a míjí se s R7. |
| Sdílený provoz, chodci, tramvaje a policie | **ne** | Každý klient si je simuluje sám. Sdílet je by znamenalo simulovat město na serveru. |
| Společná fyzika jízdy krok za krokem | **ne** | W a F mají různé fyzikální enginy se shodou jen v toleranci scénářů. Posílají se polohy, ne vstupy. |
| Posílání peněz, aut a předmětů mezi hráči | **ne** | R11 a riziko obchodu s herní měnou. |
| Hry v reálném čase proti sobě (hokej, nohejbal, stickball) | později | Citlivé na zpoždění. Samostatný plán, až bude Spolu běžet. |
| Karty a kostky proti sobě u jednoho stolu | později | Skrytá informace a hody dnes žijí v klientech. Chtělo by to rozhodčího na serveru. |
| Žebříčky celého světa | ne | Bez rozhodčího na serveru se nedají uhlídat. Jen rekord spotu se jménem. |
| Boti vydávaní za lidi | **ne** | Poctivost. Záznam jízdy je vždy označený jako stopa s časem. |

## 3. Rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| C1 | Spolu je první funkce s backendem. R12 („bez backendu ve v1“) a „Co v1 není: multiplayer“ z plánu 00 se mění jen o tento plán. Zásada 5 (jede offline) platí dál: bez sítě, s vypnutým Spolu i s nedostupným serverem je hra stejná jako dnes. | Zadání Ol1na 2026-11-25. |
| C2 | Nejdřív věci s odstupem času a soustředění lidí, živé společné hraní až potom. | Kap. 1: málo lidí. |
| C3 | Žádné účty. Zařízení si vylosuje ID a tajný klíč, server si pamatuje jen otisk klíče. Jméno je složené ze seznamu slov („Rychlý Jezevec 42“) a posílá se jako indexy, takže ho každý vidí ve svém jazyce. | Žádné osobní údaje, žádné moderování jmen. |
| C4 | Jediná komunikace jsou šablony: signály, pozvánky, cedulky. V protokolu není žádné textové pole od hráče. | Zadání. Hlídá test (kap. 10, S0). |
| C5 | Cizí auta jsou duchové: s hráčem se nesrážejí. Místní provoz je bere jako překážku a chodci před nimi uskakují. | Kap. 2. Bez toho by lidé projížděli skrz auta provozu. |
| C6 | Posílají se polohy (8× za sekundu), klient je vykresluje se zpožděním a prokládá. Vlastní auto řídí jen vlastní klient. | Dva enginy, mobilní data. |
| C7 | Server je přepojovač zpráv s malou databází. Pravidla miniher zůstávají v klientech a hlídají je vektory. | Třetí implementace pravidel by se rozešla s prvními dvěma. |
| C8 | Server je jeden program v Go (`server/coop`), SQLite, docker compose. Dá se pustit kdekoli, i ve forku. | Ol1nův stack, repo je veřejné a má jít forknout. |
| C9 | Společné minihry ve třech krocích: stejné zadání pro oba (všechny hry, beze změny pravidel), u jednoho stolu (hry s úplnou informací), jízda ve dvou. | Největší užitek za nejmenší zásah do pravidel. |
| C10 | Odměny za Spolu se počítají v klientovi přes `specs/economy.md` a mají denní stropy. | R11, farmení ve dvou oknech. |
| C11 | W vede, F přijde ve fázi S6. Do té doby má F v paritě `todo`. | Plán 05 (L3), web je to, co se sdílí odkazem. |
| C12 | Adresa serveru je konfigurace buildu, ne `tuning.yaml`. Build bez adresy má Spolu vypnuté. V repu je jen `.env.example`. | Veřejné repo, forky. |
| C13 | Zásady ochrany soukromí a obrazovka O hře se změní dřív, než se server zveřejní. | Slib v dnešních zásadách. |

## 4. Co hráč uvidí

### 4.1 Jak poznat člověka

- **Kroužek na zemi** pod autem v barvě hráče (osm barev v `design/tokens.json`). Člen party má kroužek zlatý.
- **Jmenovka** nad autem: jméno a stav. Stavy: jede, stojí, „v telefonu“ (má pauzu podle `specs/pause.md`), „hraje Bowling“.
- Lidé jezdí auty z garáže s polepy a koly. Provoz je nemá.
- **Šipky na okraji obrazovky** k nejbližším lidem se vzdáleností, parta má přednost. Počet a dosah v `tuning.yaml`.
- **Tečky na mapě** v telefonu, se jménem.
- V šikmém pohledu **světelný sloup** nad autem člena party, když je daleko.
- Klakson a bliknutí světel člověka je slyšet a vidět.

### 4.2 Jak lidi svést dohromady

1. **Jedna místnost na město pro celý svět**, žádné dělení podle regionů. Druhá instance vznikne, až je první plná.
2. **Město dne.** Střídá se po dnech podle data (UTC), stejně pro všechny. Úvodní karta a aplikace Cesty ukazují u každého města, kolik lidí tam právě jezdí, a město dne zvýrazní.
3. **Sraz v celou hodinu.** Každou hodinu je deset minut sraz u jedné památky. Vybírá ji PRNG z data a hodiny, takže ji každý klient spočítá sám. Pět minut předem přijde upozornění s tlačítkem „Jedu“ a navigací. Na srazu jde udělat skupinovou fotku (kap. 4.7).
4. **Vidět, kde lidé jsou:** šipky, mapa a karta ve feedu „Jezevec jezdí 400 m od tebe“.
5. **Setkání se vyplatí:**
   - plácnutí: projetí těsně kolem člověka dá oběma malou odměnu
   - konvoj: jízda blízko sebe déle než pár vteřin sype drobné
   - nová stránka Pasu „Lidé“: razítko za každého nového řidiče, odznaky za 1, 5 a 25
   - bonus za první společnou minihru dne
6. **Pozvánka odkazem a QR kódem** (kap. 4.3). Nejspolehlivější zdroj spoluhráčů jsou lidé, které hráč zná.

### 4.3 Jak se potkávat opakovaně

- **Parta.** Vznikne jedním klepnutím a má trvalý odkaz. Kdo odkaz otevře, je v partě: stejná místnost, zlaté kroužky, šipky napořád. Odkaz se sdílí systémovým sdílením nebo QR kódem na obrazovce. Na webu to znamená hrát spolu do deseti vteřin bez instalace.
- **Kontakty.** Po společné hře nebo vzájemném pozdravu nabídne hra „Přidat do kontaktů“. Platí, až když souhlasí oba. Aplikace Kontakty v telefonu (dnes postavy NPC) ukáže u člověka, jestli je online, ve kterém městě a čtvrti, a tlačítko „Jedu za ním“: navigace, v jiném městě přes Cesty.
- **Pravidelný rytmus:** sraz v celou hodinu a město dne. Parta se tak umí domluvit i mimo hru („v osm u Orloje“).
- **Vzkazy výsledků:** „Jezevec překonal tvůj rekord v Bowlingu“ čeká při příštím spuštění, s tlačítkem „Odveta“.
- **Cíl party na týden:** společné kilometry v konvoji, odměna je pohlednice.
- **Oznámení v appkách** (pozvánka, výsledek výzvy), jen se souhlasem. Fáze S6.

### 4.4 Signály místo chatu

Dlouhý stisk klaksonu otevře kolo signálů, krátký troubí. Klepnutí na jmenovku pošle signál jen tomu člověku. Signál je číslo šablony a případně id věci ze hry. Příjemce ho vidí ve svém jazyce.

| Druh | Šablony |
|---|---|
| Stálé | Ahoj · Dík · Promiň · Paráda · Jeď za mnou · Počkej · Jedu za tebou · Musím jet |
| Pozvánky (s tlačítky Jedu / Teď ne) | Dáme *minihru* v *podniku*? · Závod k *památce*? · Sraz u *památky* · Foto u *fotomísta*? · Konvoj do *čtvrti*? |
| Po hře | Dobrá hra · Odveta? · Ještě jednu? |

- Pozvánka se skládá z dat hry (spot, památka, čtvrť poblíž). „Jedu“ zapne oběma navigaci na to místo.
- Limit jeden signál za dvě vteřiny. Každého jde ztlumit a zablokovat; zablokovaný hráč zmizí i z mapy.

### 4.5 Město žije i o samotě

- **Rekordy a výzvy.** Server drží u každého spotu nejlepší výsledek dne a celkově, se jménem. Do feedu chodí karta „Jezevec tu dal Bowling za 187. Překonáš ho?“. Kontakty hostují karty feedu stejně jako dnes postavy NPC.
- **Cedulky.** Hráč nechá na místě vzkaz složený ze šablony a věci ze hry: „Hezký výhled“, „Tady to skáče“, „Pozor, tramvaj“, „Sraz bývá tady“. Ostatní ji vidí u silnice a zatroubením poděkují. Dík dá drobné oběma. Nejvýš tři cedulky na hráče, platí týden.
- **Stopy.** Posledních pár minut jízdy skutečných lidí se přehrává jako průsvitné auto se jménem a časem („před 3 h“). Vždy označené jako stopa.

### 4.6 Společné minihry

**Krok 1 – stejné zadání (všechny hry z katalogu).** Oba dostanou stejný `seed` a obtížnost a hrají každý svou partii proti AI. Pravidla se nemění, výsledek je díky P0 v obou klientech stejný.
- *Proti sobě:* vyhrává víc hvězd, pak skóre, pak kratší čas.
- *V týmu:* hvězdy se sčítají, při splnění cíle mají bonus oba.
- *Živě:* oba dojedou na spot (kdo je první, čeká se stavem „čeká na tebe“), během hry vidí průběh toho druhého.
- *S odstupem:* výzva zůstane na spotu týden, viz 4.5.

**Krok 2 – u jednoho stolu.** Jedna partie, dva lidé, tahy přes server. Jen hry s úplnou informací: piškvorky, čtyři v řadě, reversi, dáma, mlýn, šachy.
- Kontrakt miniher v2: hostitel sedí na místě `player`, host na místě `ai`. UI umí kreslit a brát tahy z druhé strany stolu. `aiAction` se nevolá.
- Oba klienti po každém tahu pošlou otisk stavu. Když se liší, partie se ruší bez odměn.
- Časový strop na tah, při odpojení čekání a pak kontumace. Čísla v `tuning.yaml`.

**Krok 3 – jízda ve dvou.** Sprint A→B se společným startem podle času serveru, soupeř je vidět jako duch, porovná se čas. Konvoj do čtvrti jako společná trasa s odměnou za dojetí pohromadě.

### 4.7 Sraz

Na srazu (4.2) funguje fotomísto pro všechny naráz: fotka se všemi auty v záběru se uloží do Pasu jako pohlednice s datem a počtem aut. Odměna roste s počtem lidí, se stropem.

## 5. Síť a protokol

Nová sdílená specifikace `specs/coop.md` v1 a schéma zpráv v protobufu (**OVĚŘ**, kde dnes leží `citypack.proto` a jak z něj `metro gen` dělá kód; přidej stejnou cestou TypeScript, Dart a Go).

- **Spojení:** jeden WebSocket s binárními zprávami. Naváže se až po prvním snímku, nikdy dřív. Při výpadku se obnovuje s rostoucí prodlevou a hra mezitím jede dál.
- **Totožnost (C3):** ID 128 bitů a tajný klíč v místním úložišti (W `localStorage` v try/catch, F soubor v dokumentech aplikace), mimo uložení města. Jméno = index přídavného jména, podstatného jména a číslo. V češtině jen podstatná jména mužského životného rodu, ať přídavné jméno sedí bez skloňování.
- **Místnosti:** město → instance s nejvýš `coop.room_max` lidmi. Parta drží pohromadě.
- **Poloha:** klient posílá `coop.send_hz`× za sekundu polohu v decimetrech, směr, rychlost, vrstvu, příznaky (skok, klakson, světla, stav) a při změně vzhled auta. Server ji rozešle lidem v okruhu `coop.aoi_m`; ostatním ve městě jen řídce pro mapu.
- **Vykreslení:** klient drží krátkou frontu poloh, kreslí se zpožděním `coop.interp_ms` a prokládá. Krátký výpadek dopočítá ze směru a rychlosti, delší auto zprůhlední. Čistá funkce se scénářem v toleranci (P1).
- **Co je P0 s vektory:** kódování zpráv, výběr města dne a památky srazu, porovnání výsledků dua, otisk stavu.
- **Meze na serveru:** poloha uvnitř hranic města, rychlost pod stropem, indexy jmen a šablon v rozsahu, počet zpráv za sekundu, velikost zprávy, počet spojení z jedné adresy. Co neprojde, se zahodí.
- Verze protokolu je v první zprávě. Starší klient dostane „aktualizuj“ a Spolu se mu vypne, hra jede dál.

## 6. Server

`server/coop`, samostatný Go modul. Patří sdílené vrstvě (větve `shared/…`). **OVĚŘ** v `metro.yaml`, že `metro guard` bere neuvedené cesty jako sdílené, a přidej modul do CI vedle `tools/`.

- Go, `slog`, chyby s `%w`, SQLite přes `modernc.org/sqlite` (`CGO_ENABLED=0`), testy bez sítě a bez `time.Now` (hodiny a spojení se podstrkují).
- Knihovna pro WebSocket: **OVĚŘ** udržovanou čistě v Go.
- Koncové body: `/v1/ws`, `/v1/cities` (počty lidí po městech pro úvodní kartu, bez spojení), `/healthz`, `/metrics` jen místně.
- V paměti: místnosti a polohy. V SQLite: hráči (ID, otisk klíče, jméno, vzhled, naposledy viděn), kontakty, party, rekordy a výzvy, cedulky, stopy.
- Hranice měst a seznam spotů čte ze souboru, který vyrobí `metro gen`. Balíčky měst nepotřebuje.
- Nasazení: `server/coop/deploy/` s `compose.yaml`, `.env.example` a návodem v `docs/coop.md`. Adresy, tunely a tokeny do repa nepatří.
- `server/coop/cmd/coopbots`: N botů jezdí po trasách a posílá signály. Slouží testům i měření kapacity.

## 7. Klienti a spojení webu s appkami

**W (vede)**
- Síťová vrstva a prokládání jako čisté moduly s testy (`web/src/coop`), kreslení cizích aut stejnou cestou jako provoz (sprity, stíny).
- `specs/traffic.md` a chodci: cizí auta jsou překážka (C5). **OVĚŘ**, jak dnes provoz zastavuje za tramvají a co bere `peds.update` jako seznam aut.
- Úvodní karta (`specs/firstrun.md`): věta o Spolu a počty lidí u měst. Nastavení v telefonu: vypínač Spolu, vypínač stop, nové jméno.
- `?solo` Spolu vypne. `?bench`, `?demo` a kouřový test běží bez Spolu, pokud o něj test výslovně nestojí.
- Kouřový test: dva prohlížeče a místní server se navzájem vidí; druhý běh s nedostupným serverem projde bez chyb v konzoli.

**F (fáze S6)**
- Čistý Dart balíček `packages/coop_core` (protokol, prokládání, pravidla dua), UI v `app/`.
- Totéž co W. Rozsah určuje parita.

**Jak se web potká s appkami**
1. **Jeden protokol a jeden server.** Hráč z webu a z appky jsou ve stejné místnosti. Shodu hlídají sdílené specifikace a vektory, u miniher P0 pravidla.
2. **Jeden odkaz pro pozvánku** (K4): `https://<doména>/m/<kód>`. Kdo má appku, tomu ji odkaz otevře (Universal Links na iOS, App Links na Androidu). Ostatním otevře webovou hru s `?join=<kód>`. Potřebuje soubory `/.well-known/apple-app-site-association` a `assetlinks.json` v kořeni domény, schopnost Associated Domains u App ID a filtr záměru v Androidu. **OVĚŘ** postup v dokumentaci (kap. 13); ruční kroky v účtech sepiš do `docs/release.md`.
3. **Propojení zařízení bez účtu:** v jednom zařízení „Propojit“ ukáže šestimístný kód na deset minut, druhé ho zadá a převezme totožnost: jméno, kontakty, partu, rekordy. Uložené hry zůstávají v zařízení.
4. **Oznámení** jen v appkách (FCM, APNs). Web dostane vzkazy při otevření.
5. Až bude appka ve storech, web ji nabídne nenápadným pruhem. Nic nenutí.

## 8. Soukromí, bezpečí a story

- **Co server zpracuje:** anonymní ID, indexy jména, vzhled auta, polohu auta ve hře, signály (čísla šablon), rekordy, kontakty, party, cedulky, stopy. IP adresu vidí Cloudflare a server; do databáze se neukládá.
- **Jak dlouho:** polohy se neukládají vůbec. Stopy 72 hodin, cedulky týden, výzvy týden, profil do roka od posledního spuštění. „Smazat moje údaje“ v Nastavení smaže profil na serveru i v zařízení.
- **Zásady ochrany soukromí** (`web/public/privacy.html`, obě řeči) dnes říkají „nesbírá žádné údaje“ a „appka se nepřipojuje k internetu“. Přepiš je poctivě podle toho, co server opravdu dělá, a zveřejni před prvním nasazením (C13). Co nevíš (kde server stojí), se zeptej.
- **Bezpečí:** žádný volný text ani hlas, jména ze seznamu, ztlumení a blokování, pozvánky jen odkazem, který hráč sám někomu pošle.
- **Story:** dotazníky hodnocení (interakce mezi uživateli), Data safety v Google Play, štítky soukromí v App Store. **OVĚŘ** aktuální znění pravidel obou storů pro hry, kde se potkávají uživatelé; blokování a nahlášení měj hotové i tak. Ruční kroky do `docs/release.md`.

## 9. Rozpočty, cena a rizika

| Co | Limit | Poznámka |
|---|---|---|
| Data hráče | nejvýš 8 MB za hodinu | Odhad 3–7 MB. Změř v kouřovém testu a zapiš. Lidé jsou na mobilních datech. |
| Cizí auto | skok přes 3 m nejvýš jednou za minutu | V simulaci se 150 ms kolísání a 5 % ztrát. |
| W: čas snímku p99 | nejvýš +5 % s osmi cizími auty | Scéna v `bench`. |
| První snímek | beze změny | Spojení se navazuje až po něm. |
| Server | do 150 MB paměti a půl jádra při 200 botech | Měří `coopbots`. |
| Místnost | 24 lidí | `coop.room_max`. |

**Cena provozu za měsíc** (ceny ověřené 2026-11-25, **OVĚŘ** před nasazením)

| Kde | Cena | Kdy |
|---|---|---|
| Domácí server za Cloudflare Tunnelem (default K2) | 0 Kč navíc | Start. Při 200 lidech naráz odhadem 2–3 Mbit/s odchozích. |
| Malý VPS v EU (2 jádra, 4 GB) | asi 6 € (150 Kč) | Když domácí linka nestačí nebo vypadává. Stačí na tisíce lidí. |
| Cloudflare Workers a Durable Objects | nejmíň 5 $, odhadem 5–15 $ | Jen kdyby měl server běžet blízko hráčům po celém světě. Znamená server v TypeScriptu, proto není default. |
| Doména, účty Apple a Google, oznámení | 0 Kč navíc | Už existují, oznámení jsou zdarma. |

Počty k Durable Objects, kdyby na ně došlo: příchozí zprávy se účtují v poměru 20 : 1, hodina jednoho hráče při 8 zprávách za sekundu je 1 440 účtovaných požadavků. V ceně je milion požadavků (asi 690 hodin hraní), další milion stojí 0,15 $. Hodina běžící místnosti je 461 GB-s, v ceně je 400 000 GB-s.

**Rizika**

- **Prázdné město:** největší. Řeší kap. 4.2 a 4.5 a pořadí fází (C2). Brána K1 po S1.
- **Cizí auta projíždějí místním provozem:** každý má svůj provoz. Zmírňuje C5. Zbytek je přiznaná mez.
- **Farmení odměn ve dvou oknech:** denní stropy na dvojici a na den (C10).
- **Podvádění s polohou a výsledky:** jde, server je jen přepojovač. Nejsou tu žebříčky ani převody, takže škoda je malá.
- **Výpadek domácí linky:** Spolu zmizí, hra jede dál. Přestěhování na VPS je změna jedné adresy.
- **Safari na iOS uspává spojení na pozadí:** obnova spojení a stav „v telefonu“. **OVĚŘ** na iPhonu.
- **Cizí forky a roboti na serveru:** meze z kap. 5, Cloudflare před serverem.

## 10. Fáze

| Fáze | Obsah | Kdy | Akceptace |
|---|---|---|---|
| **S0 – Specifikace a server** | `specs/coop.md`, schéma zpráv, blok `coop` v `tuning.yaml`, barvy, texty, seznam slov pro jména. Server podle kap. 6 a `coopbots`. | hned, session SHARED, klienty nemění | Testy serveru zelené v CI. 200 botů deset minut v rozpočtu, čísla v `plans/M8_SPOLU.md`. Test, že schéma nemá textové pole od hráče (C4). Nic nasazeno. |
| **S1 – Vidím lidi (W)** | Spojení, cizí auta jako duchové, kroužek, jmenovka, šipky, mapa, počty u měst, město dne, vypínač, texty o soukromí připravené. | po S0 a po bráně L (plán 05) | Kouřový test se dvěma prohlížeči i s nedostupným serverem. Skoky v rozpočtu. **Brána K1:** Ol1n se dvěma telefony. |
| **S2 – Signály a parta (W)** | Kolo signálů, pozvánky s navigací, ztlumení a blokování, parta s odkazem a QR, kontakty, „Jedu za ním“, plácnutí, konvoj, Pas „Lidé“. | po K1 | Dva prohlížeče: pozvánka na minihru dovede oba na stejný spot. Stropy odměn mají test. |
| **S3 – Město žije i o samotě (W)** | Rekordy a výzvy ve feedu, cedulky, stopy. | po S2 | Hráč sám ve městě vidí aspoň jednu výzvu, cedulku a stopu z dat, která nechal bot. Všechno po lhůtě zmizí (test s podstrčenými hodinami). |
| **S4 – Společné minihry (W)** | Stejné zadání pro všechny hry z katalogu, u jednoho stolu pro šest her (kontrakt v2), Sprint ve dvou. | po S3 | Stejné zadání: vektory výsledků shodné. U jednoho stolu: partie dámy dvou prohlížečů skončí se stejným otiskem stavu; odpojení a návrat mají test. |
| **S5 – Srazy (W)** | Sraz v celou hodinu, skupinová fotka, cíl party na týden. | po S4 | Dva klienti spočítají stejnou památku srazu pro stejnou hodinu (vektor). Fotka se třemi boty je v Pasu. |
| **S6 – Appky** | F klient pro S1–S5, odkaz pozvánky do appky, propojení zařízení, oznámení, dotazníky storů. | po S5 a podle plánu 05 | Web a appka v jedné místnosti, partie dámy mezi nimi se shodným otiskem. Odkaz otevře appku, bez ní web. |

Založ milník **M8** v `plans/progress.yaml` (**OVĚŘ** první volné číslo, M7 patří plánu 06) s položkami S0–S6, pod-plán `plans/M8_SPOLU.md` a záznamy v `plans/verify.yaml` pro S1, S2 a S4. Nová id parity ber od prvního volného. Doplň plán do seznamu v `CLAUDE.md`. Postup v každé fázi: sdílená vrstva → W → parita, jako u M5.

## 11. Parita

- Sdílené: `specs/coop.md`, schéma zpráv, texty, barvy, čísla, seznam slov.
- **P0 s vektory v obou klientech:** kódování zpráv, město dne a památka srazu, porovnání výsledků stejného zadání, otisk stavu, kontrakt miniher v2 (místo u stolu).
- **P1 se scénářem:** prokládání polohy cizího auta.
- **P2:** kroužek, jmenovka, šipky, kolo signálů, cedulky, stopy.
- Změny hotových specifikací znamenají vyšší verzi a nové vektory: `traffic.md` (cizí auta jako překážka), chodci, `economy.md` (odměny), `feed` a `phone.md` (karty a kontakty lidí), `passport.md` (stránka Lidé), `photo.md` (skupinová fotka), `firstrun.md`, kontrakt miniher.
- F má všechny nové řádky `todo` do S6. Další věc, kterou má zatím jen W.

## 12. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| K1 | Pokračovat po S1 dál? | Rozhodne se po večeru se dvěma telefony. |
| K2 | Kde server poběží? | Domácí server za Cloudflare Tunnelem. VPS až při potížích s linkou nebo nad 200 lidí naráz. |
| K3 | Spolu zapnuté od prvního spuštění? | Ano, s větou v úvodní kartě a vypínačem v Nastavení. Druhá možnost: zeptat se při prvním spuštění. |
| K4 | Doména serveru a pozvánek | Poddoména a cesta `/m/` na `olin.now`. Hra zůstává na GitHub Pages. |
| K5 | Stopy jízd | Nahrávají se všem, kdo mají Spolu zapnuté, 72 hodin, s vypínačem. |
| K6 | Jméno | Vylosované, hráč si smí nechat vylosovat jiné jednou denně. |
| K7 | Věk hráčů | Hra není v kategorii pro děti a Spolu na tom nic nemění. Potvrdit při dotaznících storů. |
| K8 | Kdy začít | S0 hned, klienty nemění. S1 a dál až po bráně L. |
| K9 | Karty, kostky a hry v reálném čase proti sobě | Mimo tento plán. |
| K10 | Oznámení v appkách | Až v S6, jen pozvánky a výsledky výzev, po souhlasu. |

## 13. Zdroje

- Cloudflare Durable Objects, ceník: https://developers.cloudflare.com/durable-objects/platform/pricing/
- Cloudflare, WebSockety na všech plánech: https://developers.cloudflare.com/network/websockets/
- Cloudflare Tunnel, otázky a odpovědi: https://developers.cloudflare.com/cloudflare-one/faq/cloudflare-tunnels-faq/
- Hetzner Cloud, levné plány: https://www.hetzner.com/cloud/cost-optimized
- Hetzner, úprava cen 2026: https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/
- Apple, Associated Domains (Universal Links): https://developer.apple.com/documentation/xcode/supporting-associated-domains
- Android App Links: https://developer.android.com/training/app-links
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

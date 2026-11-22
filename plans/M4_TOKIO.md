# M4 – Tokio (pod-plán)

Třetí město, rozhodnutí Ol1na 2026-11-23 („třetí město je Tokio, styl nechám na tobě, ať je jiný
než dvě předešlá“). Navazuje na M2 (New York naplno) a M3 (Praha); M2 se dokončuje souběžně.

**Cíl:** jezdit po centru Tokia vlevo, ve vlastním stylu, se všemi M2 funkcemi (budky, metro,
taxi, fotomísta, obchody a bary, počasí, garáž) a pasem s 25 pohlednicemi.

Platí oba plány a jejich uzavřená rozhodnutí: R7, R8, R10 (fiktivní auta a podniky, žádné
značky, žádné postavy cizí IP), DUALSTACK (sdílená vrstva, pak W a F, matice parity).

## Rozsah (každý bod samostatná feature, v tomto pořadí)

1. **Balíček Tokio** (`content/cities/tokyo/`): oblast T1, 25 hero památek s pohlednicí, spoty
   pro 7 obecných miniher z M1, garáž, 2 budky, 11 vstupů do metra, 10 fotomíst, 4 občerstvení,
   3 suvenýry, bar. `citypack validate tokyo` projde, balíček je v `packs.lock`.
2. **Tokio v klientech** (`specs/cities.md` v2, parita F-046): levostranný provoz podle
   `manifest.driveSide` (provoz už zrcadlí, nově zaparkovaná auta a zákazník Taxi směny),
   F bundluje balíček (`app/pubspec.yaml`: `assets/shared/packs/tokyo/`, `…/tokyo/chunks/`,
   `assets/shared/assets/postcards/tokyo/` až s grafikou), W ho stahuje jako ostatní. Paleta
   `color.city.tokyo` a přepínače stylu po městech platí bez kódu (klíč města v tuningu); kde
   klient města vyjmenovává natvrdo (testy, `switch`), musí brát seznam z `CityId`.
3. **Styl D – anime cel** (`specs/style.md`): ploché cel stínování bez kontur ve světě. Paleta
   podle schváleného style checku L40S (2026-11-23): papírová zem, světle tyrkysový asfalt, bílé
   značení i osa (v Japonsku bílá), ocelově šedomodré fasády, rumělkové památky, hluboké
   modroindigové vržené stíny; vržené stíny, střechy s okrajem a zebry jako ve stylu A. Sakurový
   akcent (#DBB6BD) až s klientskou funkcí, která ho použije (stromy v parcích).
4. **Grafika (L40S-MacBook):** style check D (křižovatka, pohlednice), 25 pohlednic
   `assets/postcards/tokyo/<id>.png`, textury `assets/cities/tokyo/` (asfalt, dlaždice chodníku
   s hmatovým pásem, střecha), suvenýry Tokia. Bez čitelného textu a log.
5. **Místní vozidla** (`content/cars/`): kei auto, tokijské taxi, rozvážková dodávka, skútr;
   fiktivní jména. Do té doby v Tokiu parkuje 12 obecných aut z NYC (`tags` obsahuje `tokyo`).
6. **Tři místní minihry** (nápady, každá se specifikací, vektory a spotem): Daruma otoši
   (flick, vyrazit špalky), Kendama (rhythm/flick), Shōgi zjednodušené (board). Výběr potvrdí
   Ol1n.
7. **Tokijské skity a pas:** 20 skitů s místní příchutí, pas Tokia (pohlednice 25 památek).
8. **Noc a neon** (volitelné): noční paleta Tokia s neonovými akcenty (azurová, purpurová).

## Akceptace

- `citypack validate tokyo` projde a balíček má nejvýš 40 MB.
- 60 fps v Tokiu na obou referenčních telefonech při průjezdu Ginzou a kolem nádraží.
- Provoz, zaparkovaná auta a taxi jsou vlevo; přepnutí NYC → Praha → Tokio → NYC 10× bez pádu.
- 25 pohlednic Tokia v pasu, žádná bez obrázku.
- Matice parity pro rozsah M4 zelená.

## Výchozí volby (dokud Ol1n neřekne jinak)

| # | Otázka | Default |
|---|---|---|
| T1 | Rozsah mapy | Chiyoda, Chūō, sever Minata (Roppongi, Shiba, Tokyo Tower) + Kanda, Akihabara, Ueno, Asakusa, Ryōgoku, Oshiage (Skytree), ~50 km². Shibuya a Shinjuku (Meiji Jingū, Takeshita, radnice, Golden Gai, Shinjuku Gyoen) a Rainbow Bridge až v rozšíření na západ a k zálivu |
| T2 | Start | Gyōkō-dōri před nádražím Tokio, směr k císařskému paláci |
| T3 | Styl | D – anime cel (jiný než A v NYC a C v Praze) |
| T4 | Výšky budov | Overture, default 18 m |
| T5 | Jména podniků | fiktivní (R10); komerční stavby místem (Roppongi Hills, hodinová věž v Ginze), bez jmen firem |
| T6 | Přepis jmen | Hepburn s makrony v datech (`Ryōgoku`), čeština v `i18n/cs.json` počeštěně (`Rjógoku`) |
| T7 | Dálnice Shuto | ponechané jako `motorway`, nadzemní úseky jako vrstva +1 |

## Stav (2026-11-23)

Bod 1 hotový (balíček v `packs.lock`), body 2–8 čekají; grafika zadaná L40S.

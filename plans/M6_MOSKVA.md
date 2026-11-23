# M6 – Moskva (pod-plán)

Čtvrté město, rozhodnutí Ol1na 2026-11-23 („Další město bude Moskva“). Pořadí podle plánu 05:
nejdřív milník L (vystřelení), pak M4 Tokio. Moskva jde **po L, souběžně s M4**: sdílená vrstva
(balíček, plán, paleta) hned, klienti a grafika až po L, pokud Ol1n neřekne jinak.

**Cíl:** jezdit po centru Moskvy uvnitř Sadového okruhu, ve vlastním stylu, se všemi M2 funkcemi
(budky, metro, taxi, fotomísta, obchody a bary, počasí, garáž), s terénem, vodou a zelení (M5)
a pasem s 25 pohlednicemi.

Platí plány 00–05 a jejich uzavřená rozhodnutí: R7, R8, R10 (fiktivní auta a podniky, žádné
značky, žádné postavy cizí IP), DUALSTACK (sdílená vrstva, pak W a F, matice parity).

## Rozsah (každý bod samostatná feature, v tomto pořadí)

1. **Balíček Moskva** (`content/cities/moscow/`): oblast X1, 25 hero památek s pohlednicí, spoty
   pro obecné minihry (13 her z katalogu bez městských omezení a bez kvízu, který nemá moskevskou
   banku), garáž, 2 budky, 12 vstupů do metra, 8 fotomíst, 4 občerstvení, 3 suvenýry, bar.
   Celá pipeline M5 (výšky, voda, zeleň, stromy, štěrbiny). `citypack validate moscow` projde,
   balíček je v `packs.lock`.
2. **Moskva v klientech** (parita F-078): registrace města (`CityId` z `content/cities`),
   F bundluje balíček (`app/pubspec.yaml`: `assets/shared/packs/moscow/`, `…/moscow/chunks/`),
   W ho stahuje jako ostatní; pravostranný provoz beze změny. Paleta `color.city.moscow`
   a přepínače stylu po městech platí bez kódu.
3. **Styl E – konstruktivistický plakát** (`specs/style.md`): krémový papír, černá a červená,
   okrová, plné ploché výplně, výrazné úhlopříčky, žádné přechody; vlastní dílo v duchu doby,
   žádné kopie konkrétních plakátů. V1 = paleta + vržené stíny, černé okraje střech, zebry; vlastní
   efekt (diagonální šrafy stínů, ofsetový posun) až se specifikací v3 podle style checku L40S.
4. **Grafika (L40S-MacBook):** style check E (křižovatka, pohlednice), 25 pohlednic
   `assets/postcards/moscow/<id>.png`, textury `assets/cities/moscow/` (asfalt, dlažba, střecha),
   suvenýry. Bez čitelného textu (azbuka ani latinka), bez log a bez politických symbolů.
5. **Místní vozidla** (`content/cars/`): fiktivní sedan, trolejbus jako kulisa, taxi. Do té doby
   v Moskvě parkuje 12 obecných aut (`tags` obsahuje `moscow`).
6. **Místní minihry** (nápady, výběr potvrdí Ol1n): šachy na bulváru (board), gorodki (flick),
   durak (cards).
7. **Moskevské skity a pas.**

## Akceptace

- `citypack validate moscow` projde a balíček má nejvýš 40 MB (cíl pod 4 MB).
- 60 fps v Moskvě na obou referenčních telefonech na Tverské a u Kremlu.
- Přepnutí NYC → Praha → Tokio → Moskva → NYC 10× bez pádu.
- 25 pohlednic Moskvy v pasu, žádná bez obrázku.
- Matice parity pro rozsah M6 zelená.

## Výchozí volby (dokud Ol1n neřekne jinak)

| # | Otázka | Default |
|---|---|---|
| X1 | Rozsah mapy | uvnitř Sadového okruhu i s okruhem samotným + Zamoskvorečje, Gorkého park a Krymský most, Komsomolské náměstí (tři nádraží), předmostí u Kutuzovského; Vorobjovy gory, Moskva-City a Novoděvičí až v rozšíření |
| X2 | Start | Ochotnyj rjad u Maněže, směr k Velkému divadlu |
| X3 | Styl | E – konstruktivistický plakát (jiný než A, C, D) |
| X4 | Výšky budov | Overture, default 18 m; terén AWS Terrain Tiles (povrchový model, krok `clean`) |
| X5 | Jména podniků | fiktivní (R10); historické stavby jménem místa (Horní obchodní řady), bez obchodních značek |
| X6 | Přepis jmen | data v angličtině / latinkou (`name_langs: [en, ru-Latn]`), azbuka v klientech není; titulky pohlednic = jméno z `landmarks.yaml`, čeština jen v textech |
| X7 | Citlivá místa | jen historické a kulturní stavby, žádné vládní symboly na pohlednicích |

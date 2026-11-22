# M2 – New York naplno (pod-plán)

Pod-plán milníku M2 z METROPOLE_PLAN kap. 15 („Dál“). M2 bylo přeskočené kvůli Praze (rozhodnutí
Ol1na 2026-11-22) a podle `plans/M3_PRAHA.md` se vrací po M3. Rozsah je z tabulky v kap. 15:
30 miniher, 40 aut, tuning a kosmetika, hledanost 3, obchody, bary, taxi, metro, budky, fotomísta,
rádio, počasí; soft launch.

**Cíl:** New York, ve kterém je pořád co dělat. Svět reaguje (hledanost 3, počasí, budky),
cestou se dá zastavit (obchody, bary, fotomísta), za hotovost je co koupit (auta, tuning,
kosmetika) a feed má z čeho míchat (30 miniher v NYC).

Platí oba plány a jejich uzavřená rozhodnutí: R7 (bez zbraní a srážení chodců), R8 (bez volné
chůze, vystoupení = kontextová akce na zastávce), R10 (fiktivní auta a podniky), R11 (kasinové a
kostkové hry o body), R12 (bez backendu), DUALSTACK (každá feature ve sdílené vrstvě, pak W a F,
matice parity). Praha nic z M2 nedostává povinně; co je obecné (počasí, budky, obchody), se
zapíná po městech v `city.yaml`.

## Rozsah (každý bod samostatná feature, v tomto pořadí)

1. **Hledanost 3** (`specs/police.md` v2 + vektory): strop 3, na úrovni 3 víc hlídek a zátaras
   (dvě stojící hlídky napříč hranou grafu před hráčem), vyšší pokuta. Únik dál po jedné úrovni.
2. **Zvonící budky** (`specs/booths.md`): budky z balíčku (spoty typu `booth`), občas zvoní (P0:
   PRNG v sekundách hry), zastavení u zvonící budky = náhodný motiv s bonusovou odměnou.
3. **Rychlý přesun: metro a taxi** (`specs/travel.md`): stanice metra z balíčku (Overture
   `subway_station`, výběr ~25 stanic v oblasti M1), odemknou se návštěvou; přesun mezi
   odemčenými za jízdné. Taxi z telefonu kamkoli za cenu podle vzdálenosti. Animace = střih
   s kartou linky, žádná jízda metra.
4. **Fotomísta a Foťák** (`specs/photo.md`): 20 fotomíst (výhledy, ne památky), aplikace Foťák:
   zastavit na místě, zarámovat výřez tahem, razítko do Pasu. Procento Pasu počítá fotomísta.
5. **Obchody a bary** (`specs/shops.md`): fiktivní podniky (R10) jako zastávky: občerstvení
   (dočasný bonus k odměně), suvenýry (sbírka na polici v garáži), bar = skit + výběr z
   barových miniher; po pivu hráč neřídí, hra nabídne taxi (bod 3).
6. **Počasí** (`specs/weather.md`): jasno / déšť / mlha, střídání podle času hry (P0 PRNG),
   déšť snižuje `grip` (tuning), vizuál v rendereru (kapky, odlesky, mlha), HUD ikona.
7. **Tuning a kosmetika** (`specs/garage.md`): sloty z `cars.md` (motor, pneumatiky, brzdy,
   odlehčení, drift), kosmetika lak, polepy, kola, podsvícení, barva kouře. Ceny a efekty
   v `tuning.yaml`, nákup jako P0 operace v `economy.md` (nová verze + vektory).
8. **40 aut v NYC** (`content/cars/`): ze 6 newyorských na 40 napříč třídami z kap. 10
   (mini až autobus a speciální). Fiktivní značky; kresba procedurálně podle třídy jako dnes,
   malba přes ComfyUI až po rozhodnutí Ol1na.
9. **30 miniher v NYC:** z 8 na 30. Dávky podle enginu, každá hra se specifikací, vektory,
   spotem a parita:
   - A (board, puzzle): Piškvorky, Čtyři v řadě, Mlýn, Reversi, Lodě, Posuvné puzzle, Městský kvíz
   - B (cards, dice): Prší, Srdce, Kostkový poker, Prase
   - C (flick, arcade, sport): Kulečník 8-ball, Bowling, Minigolf, Had, Cihly, Bouchni krtka,
     Vzdušný hokej
   - D (drive): Drift zóna, Sprint A→B
   - místní: Stickball (sport), Double Dutch (rhythm, nový engine)
10. **Rádio** (`specs/radio.md`): stanice podle města, přepínání v HUD. Bez licencované hudby
    (kap. 3); obsah stanic rozhoduje Ol1n (viz N4), do té doby jen kostra a ticho.
11. **Soft launch:** build do TestFlightu a Play (navazuje na M1-A4, D3-4); rozhoduje Ol1n.

## Akceptace

- 30 miniher v NYC projde unit testy a vektory v obou klientech a jde spustit z Galerie.
- 40 aut v NYC, všechna jde koupit nebo najít zaparkovaná; tuning mění jízdu měřitelně
  (test v `drive_core` a ve webu).
- Hledanost 3 se zátarasem, budky, metro, taxi, fotomísta, obchody, bary a počasí hratelné
  v obou klientech, soak 10 smyček s nimi bez pádu.
- 60 fps v dešti na Times Square na obou referenčních telefonech.
- Matice parity pro rozsah M2 zelená.
- Soft launch: Ol1n pustí build testerům.

## Výchozí volby (dokud Ol1n neřekne jinak)

| # | Otázka | Default |
|---|---|---|
| N1 | Oblast | beze změny: Manhattan po 110th St + 4 mosty (M1) |
| N2 | Výběr 22 nových miniher | dávky A–D výše (levné enginy napřed, rhythm jen pro Double Dutch) |
| N3 | Grafika 40 aut | procedurální kresba podle třídy a rozměrů, lak tónovaný za běhu |
| N4 | Rádio | kostra se stanicemi a ticho; zdroj hudby (vlastní / volná licence) určí Ol1n |
| N5 | Ceny tuningu a aut | v `tuning.yaml`, první návrh: auto 5 000–60 000, díl tuningu 1 000–8 000 |
| N6 | Bar a pivo | rozhodl Ol1n 2026-11-22: pár piv se řídit smí, po víc než `shops.beer_limit` musí hráč vyhrát minihru (`specs/shops.md`) |

## Stav (2026-11-22)

Pod-plán napsaný, rozsah 1–11 čeká na zahájení. Postup v `plans/progress.yaml` (položky M2-*).

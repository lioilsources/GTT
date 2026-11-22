# M3 – Praha (pod-plán)

Pod-plán milníku M3 z METROPOLE_PLAN kap. 15 („Dál“). **M2 se přeskakuje** (rozhodnutí Ol1na
2026-11-22): Prahu zná Ol1n osobně, ověří na ní památky a body zájmu a naladí fyziku. M2 (New York
naplno) se vrátí po M3; nic z M3 na něm nezávisí.

**Cíl:** jezdit po Praze stejně dobře jako po Manhattanu a přepínat mezi oběma městy; v Praze
tramvaje, pěší zóny projeté koloběžkou a tři místní minihry.

Platí oba plány a jejich uzavřená rozhodnutí: R7 (bez srážení chodců), R8 (bez volné chůze,
pěší zóny mikrovozidly), R10 (žádné reálné značky: „škodovka“ je fiktivní vůz s fiktivním jménem),
DUALSTACK (každá feature ve sdílené vrstvě, pak W a F, matice parity).

## Rozsah (každý bod samostatná feature, v tomto pořadí)

1. **Balíček Praha** (`content/cities/prague/`): oblast od Letné a Holešovic po Vyšehrad, od Smíchova
   a Hradčan po Žižkov a Vinohrady, s mosty přes Vltavu. Čtvrti jako prstence, 20 památek s
   pohlednicí, spoty pro 7 miniher z M1 (Koulená je jen pro New York) a garáž. `citypack validate
   prague` projde, balíček je publikovaný v `packs.lock`.
2. **Zobecnění pro druhé město:** metrické jednotky v HUD a navigaci, čtvrti a razítka s diakritikou
   (`districtId` přepisuje diakritiku: „Žižkov“ → `zizkov`; `specs/passport.md` v2 + vektory),
   dialogy NPC s pražskou příchutí (hlas skitů po městech), statistiky balíčku v `docs/citypack.md`.
3. **Přepínání měst:** výběr města v obou klientech, každé město má vlastní uložení
   (`specs/save.md`), web přes `?city=`. Nová spec `specs/cities.md`.
4. **Pěší zóny a mikrovozidla:** z Overture se ponechají pěší ulice (`pedestrian`, `footway` v
   jádru), auta do nich nesmí (sloupky), koloběžka a kolo ano. Mikrovozidlo = auto třídy `micro`
   s vlastní fyzikou v `tuning.yaml`. Nová spec `specs/micro.md`.
5. **Tramvaje:** koleje z Overture `rail` (class `tram`) jako vlastní vrstva, tramvaje jezdí po
   linkách, staví na zastávkách, mají přednost; do tramvaje jde narazit, ale neodtlačí se. Nová spec
   `specs/trams.md`.
6. **Místní vozidla:** fiktivní „lidovka“ (malý sedan), koloběžka, kolo; parkují v Praze místo
   newyorských aut (`cars.md`: auta mají seznam měst).
7. **Tři místní minihry:** Kuličky (flick, do důlku), Čára (flick, mince co nejblíž čáře),
   Nohejbal (sport, nový engine). Každá se specifikací, vektory a spotem v Praze.
8. **Pražské skity a pas:** 20 skitů s místní příchutí (`content/npc/`), pohlednice 20 památek
   (`i18n/`), pas Prahy s vlastním procentem dokončení.

## Akceptace

- `citypack validate prague` projde a balíček má nejvýš 40 MB.
- 60 fps v Praze na obou referenčních telefonech při průjezdu Staroměstským náměstím a po nábřeží.
- Ol1n ověří věrnost osobně: památky, čtvrti, spoty a mosty jsou na místě (seznam v `docs/m3-test.md`).
- Přepnutí New York ↔ Praha 10× za sebou bez pádu; každé město si drží vlastní uložení.
- Tři místní minihry projdou unit testy a vektory v obou klientech a jdou spustit z Galerie.
- Matice parity pro rozsah M3 zelená.

## Výchozí volby (dokud Ol1n neřekne jinak)

| # | Otázka | Default |
|---|---|---|
| P1 | Rozsah mapy | Praha 1 a 2 + Letná, Holešovice, Karlín, Žižkov, Vinohrady, Smíchov, Vyšehrad (~25 km²) |
| P2 | Start | Masarykovo nábřeží u Národního divadla, směr na sever (výhled na Hrad) |
| P3 | Karlův most a Staroměstské náměstí | pěší zóna: jen mikrovozidla |
| P4 | Výšky budov | Overture (`height`, `num_floors`), default 18 m; data IPR až když nestačí |
| P5 | Jména podniků | fiktivní (R10), náměstí, parky, instituce a památky skutečné |

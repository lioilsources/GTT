# Skok přes kolonu (Vega Roadster)

**version: 2** · P1 (skok, kontejner vzduchu, testy v obou klientech) / P2 (přemet, kreslení) ·
dogfooding Ol1na 2026-11-22, v2 (skok na mostě) 2026-11-23 · parita F-035

## Účel

Supersport **Vega Roadster** (fiktivní vůz, R10) má kontejner stlačeného vzduchu. Tlačítkem
**Skok** vyskočí obloukem s přemetem a přeletí kolonu: ve vzduchu ho nezastaví auta, tramvaje
ani sloupky. Kontejner vystačí na `charges` skoků, v garáži se zdarma doplní.

## Data

- Auto `content/cars/vega_roadster.json` (`schema/car.schema.json`): třída `supersport`, nepovinný
  objekt `hop: {charges: int}` = počet skoků na plný kontejner. Jen auta s `hop` umí skákat.
- Čísla v `content/tuning.yaml` → `hop`: `air_s` (doba letu), `height_m` (vrchol oblouku, jen
  kreslení), `min_speed_mps`, `flips` (počet otoček kolem podélné osy, kreslení).

## Stav (za session, neukládá se)

`charges` (zbývá skoků; při načtení hry a po přesednutí do auta s `hop` plný kontejner),
`air` (zbývající čas letu, 0 = na zemi), `t` (uplynulý čas letu).

## Pravidla (P1)

- **Skok jde spustit**, když řízené auto má `hop`, `charges > 0`, `air = 0` a rychlost ≥
  `hop.min_speed_mps`, v **kterékoli vrstvě** (−1 tunel, 0, +1 most; v1 jen ve vrstvě 0). Pak
  `charges −= 1`, `air = hop.air_s`, `t = 0`.
- **Ve vzduchu** (`air > 0`): auto neřídí ani nezrychluje (vstup se ignoruje), pneumatiky
  nepůsobí (krok 5 `specs/drive.md` se vynechá), úhlová rychlost je 0, lineární rychlost se drží
  (jen odpor vzduchu, krok 4). Provoz, zaparkovaná auta, tramvaje a sloupky se ignorují; náraz do
  provozu / tramvaje ani policie se nehlásí. Maska kolizí ve vrstvě 0 = jen budovy
  (`CAT_BUILDINGS`); ve vrstvě ≠ 0 prázdná (budovy kolidují jen ve vrstvě 0).
- **Vrstva se během letu nemění.** Sledování hrany (`specs/drive.md` krok 6) běží dál, aby auto
  vědělo, nad kterým místem hrany letí, ale vrstva auta zůstává ta ze vzletu. Ve vrstvě ≠ 0 drží
  auto na mostovce / v tunelu zábradlí (`specs/flow.md`) i ve vzduchu – z mostu se skokem
  nespadne do řeky.
- **Přistání:** když `air` klesne na 0, vrstva se nastaví podle sledované hrany (most, nájezd,
  zem) a maska se vrátí podle té vrstvy a zón (`specs/zones.md`): na mostě zábradlí a provoz na
  mostovce, na zemi budovy, sloupky a provoz; překryv s autem provozu / tramvají po dopadu řeší
  odstrčení (`specs/traffic.md` krok 7).
- **Reliéf** (`specs/terrain.md`): oblouk `hopArc` se přičítá k výšce povrchu, po kterém auto jede
  (`groundZ(poloha, surface)`; na mostě mostovka, jinak terén). Model skoku přes hranu
  (`specs/terrain.md` „Skok“) je během letu pozastaven: každý krok `z = g`, `vz = 0`,
  `airborne = false`, `g_prev = g` (jako po přesunu); svahová síla se nepočítá. Po přistání běží
  model dál od `z = g` (žádný falešný `dopad`). Balíček bez výšek: `g = 0`.
- **Doplnění:** v garáži (`specs/cars.md`) tlačítko „Doplnit vzduch“, když řízené auto má `hop` a
  `charges < hop.charges`; doplní na plno, zdarma.
- Čistá funkce `canHop(spec, charges, air, layer, speed, t) → bool` a `hopArc(t, airS, heightM)
  = 4 · heightM · (t / airS) · (1 − t / airS)`; testy v obou klientech.

## Ovládání

HUD tlačítko **Skok** s ukazatelem kontejneru (`charges` / plno) se ukáže jen v autě s `hop`;
když skok nejde (nízká rychlost, prázdný kontejner), je šedé. Web: klávesa **J**.

## Kreslení (P2)

Auto se ve vzduchu kreslí zvednuté o `hopArc` nad povrchem jízdy (mostovka, terén; větší měřítko
podle výšky jako budovy), stín zůstává na povrchu (na mostě na mostovce) a zmenšuje se; s přemetem: šířka karoserie × `cos(2π · flips · t / air_s)`, v polovině otočky je vidět spodek (`color.car.tyre`).

## Texty

`i18n/`: `hopButton`, `hopRefill`, `hopEmpty`.

## Změny
- **v2:** skok jde spustit v kterékoli vrstvě (most, tunel); vrstva se ve vzduchu drží, zábradlí
  drží auto na mostovce, maska ve vrstvě ≠ 0 je ve vzduchu prázdná; přistání vrací masku vrstvy;
  na reliéfu oblouk nad povrchem jízdy a model skoku přes hranu stojí. `canHop` už vrstvu
  nekontroluje (parametr `layer` zůstává kvůli podpisu).

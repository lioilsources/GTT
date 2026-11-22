# Skok přes kolonu (Vega Roadster)

**version: 1** · P1 (skok, kontejner vzduchu, testy v obou klientech) / P2 (přemet, kreslení) ·
dogfooding Ol1na 2026-11-22 · parita F-035

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

- **Skok jde spustit**, když řízené auto má `hop`, `charges > 0`, `air = 0`, auto je ve vrstvě 0 a
  rychlost ≥ `hop.min_speed_mps`. Pak `charges −= 1`, `air = hop.air_s`, `t = 0`.
- **Ve vzduchu** (`air > 0`): auto neřídí ani nezrychluje (vstup se ignoruje), pneumatiky
  nepůsobí (krok 5 `specs/drive.md` se vynechá), úhlová rychlost je 0, lineární rychlost se drží
  (jen odpor vzduchu, krok 4). Maska kolizí = jen budovy (`CAT_BUILDINGS`); provoz, zaparkovaná
  auta, tramvaje a sloupky se ignorují; náraz do provozu / tramvaje ani policie se nehlásí.
  Vrstva se během letu nemění.
- **Přistání:** když `air` klesne na 0, maska se vrátí podle vrstvy a zón (`specs/zones.md`);
  překryv s autem provozu po dopadu řeší odstrčení (`specs/traffic.md` krok 7).
- **Doplnění:** v garáži (`specs/cars.md`) tlačítko „Doplnit vzduch“, když řízené auto má `hop` a
  `charges < hop.charges`; doplní na plno, zdarma.
- Čistá funkce `canHop(spec, charges, air, layer, speed, t) → bool` a `hopArc(t, airS, heightM)
  = 4 · heightM · (t / airS) · (1 − t / airS)`; testy v obou klientech.

## Ovládání

HUD tlačítko **Skok** s ukazatelem kontejneru (`charges` / plno) se ukáže jen v autě s `hop`;
když skok nejde (nízká rychlost, prázdný kontejner), je šedé. Web: klávesa **J**.

## Kreslení (P2)

Auto se ve vzduchu kreslí zvednuté o `hopArc` (větší měřítko podle výšky jako budovy, stín
zůstává na zemi a zmenšuje se), s přemetem: šířka karoserie × `cos(2π · flips · t / air_s)`,
v polovině otočky je vidět spodek (`color.car.tyre`).

## Texty

`i18n/`: `hopButton`, `hopRefill`, `hopEmpty`.

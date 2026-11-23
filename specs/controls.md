# Ovládání A/B/C

**version: 2** · P1 · čísla v `content/tuning.yaml` (`controls`)

## Účel
Tři schémata pro jeden palec na výšku; výchozí je A. Vstup = dotyky v logických pixelech, výstup
`steer ∈ [−1, 1]` (+ = doprava), `brake ∈ [0, 1]`, `handbrake`, `boost`.

## A (výchozí)
- První prst: steer = (x − x0) / (`a_full_steer_width` · šířka), oříznuto na ±1.
- Tah dolů o víc než `a_dead_zone_height` · výška: brake = (dy − dead) / `a_full_brake_height`.
- Tah nahoru o víc než dead zone: boost.
- Každý další prst: handbrake. Když první prst zvedne, převezme řízení další.

## B
Držení levé / pravé poloviny: steer −1 / +1. Obě poloviny: brake 1.
- v2: tlačítko **Boost** dole uprostřed (`left = 0,38 w`, `top = h − 0,28 w`, `0,24 w × 0,2 w`,
  dotyk s přesahem 8 px): prst, který na něm začne, je až do zvednutí boost a do polovin se nepočítá
  (druhým palcem se dál zatáčí). Prst, který začal v polovině, zůstává řízením i nad tlačítkem.

## C
Volant dole uprostřed (střed x = w/2, y = h − 0,26 w, poloměr 0,2 w; chycení do 1,6 r):
steer = úhel / `c_max_wheel_rad`; pedál brzdy vpravo dole, ruční brzda vlevo dole.
- v2: tlačítko **Boost** vpravo nad pedálem brzdy (`left = 0,8 w`, `top = h − 0,64 w`,
  `0,17 w × 0,17 w`, přesah 8 px), drženo = boost. Pořadí zásahu: pedál, Boost, ruční brzda, volant.
Rozvržení v násobcích šířky obrazovky je prezentace (P2), mapování na vstup je P1.

## Klávesnice (desktop)
Šipky/WASD: doleva/doprava steer ∓1, dolů brake 1, nahoru boost; mezerník handbrake.

## Nápověda boostu (v2)
Městské tempo je jen `speed_mps.cruise` (`specs/drive.md` v2), rychleji jede jen boost, a ten
hráč sám nenajde. Nápověda je krátký toast (stejný jako toast trasy, `nav.toast_s`) s textem
podle aktivního ovládání: `boostHintA`, `boostHintB`, `boostHintC`; na zařízení s klávesnicí
(W: primární ukazatel je jemný, `(pointer: fine)`; F: desktopová platforma) `boostHintKeys`.

Čistý modul `BoostHint(tuning, shown)` (`shown` = kolikrát už se ukázala na tomto zařízení),
`step(dt, speed, boost)` jednou za snímek s herním časem (pauza a minihra = 0) vrací
`show` | `used` | nic:
- `boost` → když `shown < boost_hint_max`: `shown = boost_hint_max`, vrátí `used` (hráč boost zná,
  nápověda už nikdy). Jinak nic.
- `shown ≥ boost_hint_max` nebo `dt = 0` → nic.
- `shown = 0` (první jízda) → `show` hned v prvním kroku s `dt > 0`.
- Jinak se sčítá čas jízdy s `|speed| ≥ boost_hint_min_speed_mps`; když součet od posledního
  zobrazení (nebo od startu) dosáhne `boost_hint_after_s` → `show`.
- `show`: `shown += 1`, součet = 0.

Po `show` i `used` klient uloží `shown` mimo uložení hry (nastavení zařízení, ne postup; formát
`specs/save.md` se nemění): W `localStorage` klíč `metropole:boostHint` (celé číslo jako text,
čtení i zápis v try/catch, bez úložiště se počítá od 0), F soubor `boost_hint.json`
(`{"shown": n}`) v dokumentech aplikace. Bez nápovědy jede autopilot (`?bench`, `?demo`).

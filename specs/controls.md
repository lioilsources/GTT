# Ovládání A/B/C

**version: 1** · P1 · čísla v `content/tuning.yaml` (`controls`)

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

## C
Volant dole uprostřed (střed x = w/2, y = h − 0,26 w, poloměr 0,2 w; chycení do 1,6 r):
steer = úhel / `c_max_wheel_rad`; pedál brzdy vpravo dole, ruční brzda vlevo dole.
Rozvržení v násobcích šířky obrazovky je prezentace (P2), mapování na vstup je P1.

## Klávesnice (desktop)
Šipky/WASD: doleva/doprava steer ∓1, dolů brake 1, nahoru boost; mezerník handbrake.

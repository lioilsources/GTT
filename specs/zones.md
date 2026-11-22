# Pěší zóny a mikrovozidla

**version: 1** · P1 (kdo smí do zóny, testy v obou klientech) / P2 (kreslení sloupků a dlažby) ·
plán: METROPOLE_PLAN R8, 5.6 (Praha: „organická síť, pěší zóny, mikrovozidla“), `plans/M3_PRAHA.md`
bod 4 · parita F-029

## Účel

Staroměstské náměstí, Karlův most nebo náplavky jsou pěší zóny. Autem se do nich nedá vjet, na
okrajích stojí sloupky. Koloběžkou nebo kolem (auto třídy `micro`) se jimi projet dá. Je to
jediný způsob, jak se v jádru Prahy dostat pěšími uličkami (R8: bez volné chůze).

## Data (citypack, `specs/citypack.md` v2)

- **Zóna** = pásy kolem segmentů Overture `class: pedestrian` (šířka `zones.street_width_m`)
  a pěší náměstí (Overture `land_use` `subtype: pedestrian`), kterými takový segment prochází,
  sjednocené, bez koridorů všech silnic grafu (ponechaných i uliček) rozšířených o
  `zones.gap_margin_m`, oříznuté oblastí a mřížkou chunků. Silnice tak zůstanou průjezdné celou
  šířkou. V chunku je zóna `Mesh` s druhem `GroundKind.PEDESTRIAN` (dlažba, kreslí se nad parkem,
  náměstím, kolejištěm i vodou, aby byl vidět Karlův most, a pod silnicemi).
- **Zábrana** = hranice zóny bez hranice oblasti, rozdělená do chunků; kusy kratší než
  `zones.min_barrier_m` se zahodí. Vede po obrubníku mezi zónou a silnicí a po okrajích zóny
  (u budov se zdvojí s jejich kolizí, to nevadí). V chunku je to `Barrier` (lomená čára v dm).
- Pipeline: krok `zones` po `ground` (potřebuje `road_buffers.csv` z kroku `widen`) a před
  `pack`. `validate` navíc hlídá, že žádná zábrana nekříží osu silnice grafu.

## Kdo smí do zóny (P1)

- Zábrany jsou statická tělesa ve vrstvě 0, kategorie `CAT_ZONE = 32`, maska `CAT_CAR`.
- Auto hráče třídy ≠ `micro` má v masce `CAT_ZONE` (narazí do sloupků jako do zdi, odraz jako u
  budov). Auto třídy `micro` `CAT_ZONE` v masce nemá a projede.
- **Výjimka uvnitř zóny:** když je střed auta hráče uvnitř nějaké zóny (bod v polygonu, ve vrstvě
  0), `CAT_ZONE` se z masky odebere, dokud střed zónu neopustí. Auto, které se do zóny dostalo
  jinak (přesednutí z koloběžky, start), tak vždycky vyjede ven. Čistá funkce
  `zoneMask(class, insideZone)` → bity masky; testy v obou klientech.
- Provoz, zaparkovaná auta a policie zábrany ignorují (jezdí jen po grafu, zóny se ho netýkají).
- GPS (`specs/route.md`) vede jen po ponechaných silnicích, zóny nemění.

## Mikrovozidla

- Auto s `class: micro` v `content/cars/<id>.json` (`schema/car.schema.json`): stejný model jízdy
  (`specs/drive.md`) s vlastními čísly v JSON (malé, lehké, nízká `top_speed`). Ruční brzda u
  mikrovozidla nedává úhlový impuls (`handbrake_yaw` × 0), jen zpomalí.
- Přesedání (`specs/cars.md`) funguje beze změny. Zaparkovaná mikrovozidla stojí u vjezdů do zón
  (`specs/cars.md` v2, generování podle města, M3-S6).

## Kreslení (P2)

- Dlažba zóny: `color.world.<den|noc>.pedestrian` (`design/tokens.json`).
- Sloupky po zábraně každých `zones.bollard_spacing_m`, kruh poloměru `zones.bollard_radius_m`,
  barva `color.props.bollard`; ve 2,5D malá válcová extruze `zones.bollard_height_m`.

## Ladění

`content/tuning.yaml` → `zones`: `street_width_m`, `gap_margin_m`, `min_barrier_m` (citypack),
`bollard_spacing_m`, `bollard_radius_m`, `bollard_height_m` (klienti).

## Hraniční případy

- Silnice vede zónou (Václavské náměstí má ponechanou silnici uprostřed): koridor silnice je ze
  zóny vyříznutý, sloupky stojí podél něj; auto projede po silnici, mimo ni do zóny ne.
- Zóna bez zábrany (celá uvnitř budov nebo celá protnutá silnicemi): jen dlažba.
- Město bez pěších segmentů (New York v M1 rozsahu): žádné zóny ani zábrany, nic se nemění.

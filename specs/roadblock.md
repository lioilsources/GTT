# Zátaras (M2-S1)

**version: 1** · P1 · METROPOLE_PLAN 7.4, M2 bod 1 · parita F-036 · navazuje na `specs/police.md`

## Účel
Na hledanosti aspoň `police.roadblock.level` postaví policie před hráčem zátaras: dvě stojící
hlídky napříč silnicí. Čísla v `content/tuning.yaml` → `police.roadblock`, text
`policeRoadblock`, barvy hlídky z `color.police`.

## Pravidla (P1)
- **Kdy:** v tiku, kdy `level ≥ roadblock.level`, žádný zátaras nestojí a od zrušení minulého
  uplynulo aspoň `cooldown_s` (na začátku hned). Pokus nejvýš jednou za `pick_interval_s`.
- **Kde:** hrana pod hráčem = nejbližší ponechaná hrana ve vrstvě hráče (`graph.near`, do
  `layers.search_m`); směr jízdy = znaménko `dot(směr hrany, směr auta)`. Od průmětu hráče se jde
  po směru jízdy; na konci hrany se další hrana volí `chooseToward(graph, uzel, předchozí, gx, gy)`
  s cílem `g = hráč + roadblock.probe_m · (cos heading, sin heading)`. Kde ujitá vzdálenost dosáhne `ahead_m`, stojí zátaras.
  Hraniční uzel (−1), hrana v jiné vrstvě než 0 nebo hrana pěší zóny = pokus se vzdá.
- **Jak:** dvě auta provozu (`addCar`, příznak `police` a `blocking`) v bodě `p` na hraně,
  posunutá o `±lateral_m` po normále hrany, natočená napříč (`heading` hrany + π/2). Blokující
  hlídka stojí (`speed = 0`), nejede, neotáčí se, nehoní, nezmizí s provozem (`despawn_m`) a
  nepočítá se do `police.patrols[level]`. Je kinematická jako ostatní auta, takže do ní hráč
  narazí. Vidí a dopadá jako ostatní hlídky (Dohled, Dopadení). Nedaří-li se `addCar` (strop aut),
  pokus se vzdá a zkusí se za `pick_interval_s`.
- **Zrušení** (obě auta zmizí a začne `cooldown_s`): `level < roadblock.level` (únik, dopadení),
  hráč je od zátarasu dál než `clear_m`, nebo zátaras stojí déle než `ttl_s`. Respawn hráče a
  reset provozu ho zahodí také.
- **HUD:** při postavení toast `policeRoadblock` (`toast_s`).
- **Kreslení:** jako hlídka; majáky blikají vždy (stejné barvy, `light_blink_s`).

## Hraniční případy
- Ujitá vzdálenost přesáhne konec slepé ulice (hraniční uzel): pokus se vzdá, další za
  `pick_interval_s`.
- Hráč projede zátarasem skokem (`specs/hop.md`): auto ve vzduchu hlídky ignoruje, zátaras
  zůstane stát, dokud ho nezruší pravidla výše.
- `police.enabled = false` nebo `police.max_level < roadblock.level`: zátaras se nestaví.

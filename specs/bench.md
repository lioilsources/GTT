# Benchmark D1 – autopilot a měření

**version: 2** · P1 (trasa a autopilot), P2 (čísla měření) · trasa `content/bench/<city>.json`,
další trasy `content/bench/<city>-<id>.json` (v2)
(`schema/bench.schema.json`), výsledek `schema/bench_result.schema.json`, čísla `bench` v `content/tuning.yaml`

## Účel
Oba klienti projedou stejnou trasu bez lidského vstupu a změří výkon (DUALSTACK 10, D1). Plán mluví
o nahraných vstupech; autopilot po trase je stejný test, ale nezávisí na tom, že fyzika obou klientů
dá po minutách jízdy přesně stejnou polohu. Trasa: 42nd St od řeky k řece se smyčkou přes Times Square.

## Trasa
1. Křižovatka `{a, b}` = uzel grafu, ze kterého vede hrana pojmenovaná `a` i hrana pojmenovaná `b`.
   Víc takových uzlů → ten s nejmenším indexem. Žádný → chyba trasy.
2. Úsek `{via, to}` = nejkratší cesta (Dijkstra, délka hran) z konce předchozího úseku do `to`
   jen po hranách, jejichž jméno je ve `via`. Jednosměrky se ignorují (M0 nemá provoz), leda trasa
   má `oneway: true` (v2): pak se hrana s `oneway` 1 bere jen from → to, s −1 jen to → from.
   Při shodě délek vyhrává cesta přes uzel s menším indexem.
3. Lomená čára trasy = body hran v pořadí jízdy, bez opakování společných uzlů.

## Autopilot (každý pevný krok fyziky)
- Postup `s` = průmět auta na lomenou čáru, hledaný jen v [s − `search_back_m`, s + `search_ahead_m`].
- Cíl = bod trasy ve vzdálenosti s + `lookahead_m` + `lookahead_per_mps` · v.
- Chyba e = úhel k cíli − natočení auta (−π..π); steer = clamp(−`steer_gain` · e, −1, 1).
- Zatáčka: největší změna směru trasy mezi s a s + `corner_lookahead_m`; je-li > `corner_turn_rad`,
  chtěná rychlost = `corner_speed_mps`, jinak `speed_mps.cruise`.
- brake = clamp((v − chtěná) · `brake_per_mps`, 0, 1); bez boostu a ruční brzdy.
- Pomaleji než `stuck_mps` po dobu `stuck_s` → auto se postaví na trasu v s + `respawn_ahead_m`
  ve směru trasy a `respawns` se zvýší o 1.
- Konec: s ≥ délka − `arrive_m`.

## Měření
- Snímky prvních `warmup_s` se nepočítají.
- `fps_avg` = snímky / čas; `frame_ms_p50`, `frame_ms_p99` z délek snímků; `fps_1low` = 1000 / p99.
- `first_frame_ms`: web od `performance.timeOrigin`, aplikace od startu procesu (Dart `main`) do prvního
  snímku s načteným okolím auta.
- `memory_mb`: web `performance.memory.usedJSHeapSize` (jen Chrome), aplikace RSS procesu; jinak chybí.
- Teplotu a úbytek baterie měří Ol1n ručně (10 minut, opakované jízdy).

## Další trasy (v2)
Soubor `content/bench/<city>-<id>.json` (stejné schéma, `id` = `<id>`, `city` = `<city>`) je ověřovací
trasa, ne benchmark: `<city>.json` zůstává jediným D1 měřením města. Kopce Prahy (L-S1, M5-S10):
`prague-petrin`, `prague-letna`, `prague-hradcany` s `oneway: true`, ulice jen ponechané
pozemní hrany (`kept`, ne schody ani tunel); popis a co sledovat v `docs/prague-hills.md`.
- W `?city=<city>&route=<id>`: auto stojí na začátku trasy ve směru trasy a navigace (`specs/phone.md`)
  vede po lomené čáře trasy (ne GPS hledáním) k jejímu konci; cíl v HUD = ulice `b` posledního
  `to`; dojezd ukáže jen hlášku „Na místě“. Sjetí z trasy přepočítá navigaci GPS k témuž konci.
- `?city=<city>&route=<id>&bench`: tutéž trasu jede autopilot a na konci ukáže měření.

### Ladění kopců (W, jen s `?debug`)
Tlačítko „Ladění“ v řadě kulatých tlačítek otevře panel s posuvníky klíčů `content/tuning.yaml`,
které klient čte každý krok nebo snímek, takže změna platí hned: `slope_physics.gravity`,
`slope_physics.slope_force_scale`, `slope_physics.suspension_travel`, `slope_physics.hard_landing`,
`speed_mps.cruise`, `camera.topdown.height_m`, `camera.chase.distance_m`, `camera.chase.height_m`,
`camera.chase.look_ahead_m`, `camera.chase.fov_deg`, `camera.heading_follow_rate`, `view_width_m.slow`,
`view_width_m.fast`. Popisky jsou klíče YAML (jako panel F); „Kopírovat tuning.yaml“ zkopíruje řádky
`klíč: hodnota` (desetinná čísla vždy s tečkou). Změna se neukládá. Čísla balíčku
(`terrain.exaggeration`, `terrain.max_grade`, `terrain.pipeline.shade_strength`) panel nemá: platí až
po novém `citypack build`.

## Spuštění
- W: `?bench` (volitelně `&scheme=…`); výsledek se ukáže na konci s tlačítkem Kopírovat.
- F: ladicí panel → Benchmark.
Výsledky se vkládají do `plans/BAKEOFF_REPORT.md`.

## Testy
Oba klienti: trasa NYC se sestaví (5 úseků, délka 3–5 km) a autopilot ji v simulaci bez vykreslování
dojede s `respawns` ≤ 2.
W (v2, `web/test/pragueHills.test.ts`, balíček Prahy): každá pražská trasa vede jen po ponechaných
pozemních hranách, autopilot ji dojede s 0 vyproštěními (`specs/flow.md`), 0 `respawns` a 0 pády do
vody a vystoupá aspoň 20 m (skutečných); test hlásí čas, rychlost min/max, největší sklon pod autem
(herní i skutečný) a počet skoků (`HILLS_REPORT=<soubor>` je zapíše jako JSON).

## Verze
- 2 – další trasy `<city>-<id>.json`, `oneway`, `?route=<id>` s navigací po trase, panel „Ladění kopců“, test pražských kopců.
- 1 – trasa NYC, autopilot, měření.

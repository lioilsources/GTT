# Benchmark D1 – autopilot a měření

**version: 1** · P1 (trasa a autopilot), P2 (čísla měření) · trasa `content/bench/<city>.json`
(`schema/bench.schema.json`), výsledek `schema/bench_result.schema.json`, čísla `bench` v `content/tuning.yaml`

## Účel
Oba klienti projedou stejnou trasu bez lidského vstupu a změří výkon (DUALSTACK 10, D1). Plán mluví
o nahraných vstupech; autopilot po trase je stejný test, ale nezávisí na tom, že fyzika obou klientů
dá po minutách jízdy přesně stejnou polohu. Trasa: 42nd St od řeky k řece se smyčkou přes Times Square.

## Trasa
1. Křižovatka `{a, b}` = uzel grafu, ze kterého vede hrana pojmenovaná `a` i hrana pojmenovaná `b`.
   Víc takových uzlů → ten s nejmenším indexem. Žádný → chyba trasy.
2. Úsek `{via, to}` = nejkratší cesta (Dijkstra, délka hran) z konce předchozího úseku do `to`
   jen po hranách, jejichž jméno je ve `via`. Jednosměrky se ignorují (M0 nemá provoz).
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

## Spuštění
- W: `?bench` (volitelně `&scheme=…`); výsledek se ukáže na konci s tlačítkem Kopírovat.
- F: ladicí panel → Benchmark.
Výsledky se vkládají do `plans/BAKEOFF_REPORT.md`.

## Testy
Oba klienti: trasa NYC se sestaví (5 úseků, délka 3–5 km) a autopilot ji v simulaci bez vykreslování
dojede s `respawns` ≤ 2.

## Kouřový test mobilního webu (CI)

Plán `Prompts/05-METROPOLE_LAUNCH_PLAN.md` L-S6, jen W. `web/scripts/smoke.ts` (`npm run smoke`)
spustí headless Chromium (Playwright) proti `vite preview` buildu a projde kroky ve dvou mobilních
profilech: **Pixel 8a** 412 × 915, DPR 2,625 a **iPhone 12 mini** 375 × 812, DPR 3, oba
s dotykem. Čísla jsou `smoke` v `content/tuning.yaml`; chování klienta se nemění.

1. Kořenová URL s `?debug` se načte a `#loading` zmizí do `smoke.first_frame_ms`
   (`metro.timing().firstFrameMs` od `performance.timeOrigin`).
2. Úvodní karta (`specs/firstrun.md`), pokud je vidět, se zavře tlačítkem `introGo`.
3. Dotyk: jeden prst tažený o `smoke.drag_px` nahoru a držený `smoke.drive_s`; auto ujede aspoň
   `smoke.min_drive_m` (vzdálenost `metro.drive.car`).
4. Tlačítko telefonu otevře feed; tah nahoru o `smoke.swipe_px` přepne kartu (jiné jméno
   uprostřed feedu) a tah dolů vrátí původní kartu.
5. Přepnutí měst New York → Praha → Tokio (`?city=<id>&debug&nointro`): každé se načte do
   `smoke.first_frame_ms`.
6. Konzole bez chyb (`console.error`, nezachycené výjimky) v celém průchodu; varování nevadí.

Rozpočet `first_frame_ms` je změřený na CI runneru (softwarové WebGL) se zálohou; na telefonu
platí cíle z D1 a M0-A1.

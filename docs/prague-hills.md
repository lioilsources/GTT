# Kopce Prahy – tři ověřovací trasy (L-S1, M5-S10)

Účel: Ol1n na telefonu projede tři trasy a potvrdí, že kopce Prahy fungují (M5-A5). Trasy jsou
v `content/bench/prague-<id>.json` (`specs/bench.md` v2, `oneway: true`), vedou jen po ponechaných
pozemních ulicích balíčku (žádná ulička, schody ani tunel) a po směru jednosměrek.

**Výběr ulic.** Náhled balíčku (`run/bin/citypack preview prague` → `run/citypack/prague/preview/steepest.json`)
hlásí nejprudší pojmenované ulice: Zámecká 16,1 %, Thunovská 12,8 % (Hradčany), Nad Štolou 12,5 %
(Letná), Holečkovu v něm nemá, ale graf jí dává 14 % na krátkém úseku. Zámecká, Thunovská a
Nad Štolou jsou v grafu uličky nebo pěší (ne `kept`), proto trasy vedou po nejbližších ponechaných
ulicích do stejných kopců. Sklon níže = skutečný (herní / `exaggeration` 2), nejprudších 30 m úseku
podle výšek hran grafu; HUD ukazuje herní sklon (dvojnásobný).

| Trasa | Ulice (pořadí jízdy) | Délka | Výška m n. m. | Nejprudší úsek |
|---|---|---|---|---|
| `hradcany` | Malostranské náměstí → Nerudova → Úvoz → Pohořelec | 860 m | 227 → 285 | 9,0 % (Úvoz) |
| `petrin` | náměstí Kinských → Holečkova → Zapova → Švédská → Na Hřebenkách → Pod Stadiony | 2,4 km | 206 → 308 | 9,4 % (Zapova) |
| `letna` | Klárov → Pod Bruskou → Chotkova (serpentiny) → Badeniho → Milady Horákové → Veverkova | 2,7 km | 212 → 235, pak dolů | 10,0 % (Milady Horákové u tunelu), Chotkova 6,3 % |

## Odkazy

Hraješ sám, navigace vede po trase (modrá čára a pilulka s cílem a vzdáleností); na konci
„Na místě“. `&debug` přidá tlačítko „Ladění“ (panel níže). `&bench` místo tebe jede autopilot
a na konci ukáže měření.

| Trasa | Jízda | S panelem ladění | Autopilot |
|---|---|---|---|
| Hradčany | https://lioilsources.github.io/GTT/?city=prague&route=hradcany | [`&debug`](https://lioilsources.github.io/GTT/?city=prague&route=hradcany&debug) | [`&bench`](https://lioilsources.github.io/GTT/?city=prague&route=hradcany&bench) |
| Petřín | https://lioilsources.github.io/GTT/?city=prague&route=petrin | [`&debug`](https://lioilsources.github.io/GTT/?city=prague&route=petrin&debug) | [`&bench`](https://lioilsources.github.io/GTT/?city=prague&route=petrin&bench) |
| Letná | https://lioilsources.github.io/GTT/?city=prague&route=letna | [`&debug`](https://lioilsources.github.io/GTT/?city=prague&route=letna&debug) | [`&bench`](https://lioilsources.github.io/GTT/?city=prague&route=letna&bench) |

Porovnání naplocho: přidej `&flat` (balíček bez výšek, `specs/terrain.md`).

## Na co se dívat

Všude:
- **Ztráta rychlosti do kopce** – s plným plynem tachometr do kopce klesá, z kopce auto
  nabírá a drží cestovní rychlost (`speed_mps.cruise`).
- **HUD vlevo dole** – sklon v % (herní, zobrazí se nad 2 %) a nadmořská výška; do kopce musí
  výška růst plynule, bez skoků o metry.
- **Stínování** – svahy k jihovýchodu tmavší, k severozápadu světlejší (slunce z SZ); silnice
  stínování přebírá, takže je vidět, kde ulice láme do kopce.
- **Šipky na vozovce** – u úseků nad 8 % (herních) míří do kopce.
- **Skok** – na hraně kopce v plné rychlosti se stín auta oddělí a zmenší, kamera krátce oddálí;
  tvrdý dopad zatřese kamerou a ubere rychlost.
- **Kamera shora** – kopec se při projetí „nafukuje“ k autu (perspektiva podle výšky), budovy
  na svahu stojí na terénu, ne ve vzduchu ani pod ním.
- Šikmý pohled zatím na `main` není (F-074); až bude, stejné odkazy s `&camera=chase`.

Po trasách:
- **Hradčany** – Nerudova a Úvoz jsou úzké, horní Nerudova a dolní Úvoz jednosměrně do kopce; sleduj, jestli auto do kopce
  nezpomalí pod rychlost, která je ještě zábavná, a jestli na hřebeni u Pohořelce nevyskočí.
- **Petřín** – nejdelší stoupání (přes 100 m výšky): Holečkova mírně, Zapova ve vracečce prudce,
  Švédská a Na Hřebenkách pod Strahovem. Tady je nejlépe vidět ztráta rychlosti a stínování
  svahu Petřína. Autopilot měl na trase jeden skok.
- **Letná** – Chotkovy serpentiny z Klárova (vracečky v kopci, šipky na vozovce), pak rovina
  Letné po Milady Horákové a sjezd k Veverkově: z kopce auto nesmí ujet nad cestovní rychlost.

## Ladění za jízdy (`&debug` → „Ladění“)

Posuvníky mění klíče `content/tuning.yaml` hned (klient je čte každý krok nebo snímek);
„Kopírovat tuning.yaml“ zkopíruje řádky `klíč: hodnota` k vložení do repa. Změny se neukládají.

| Klíč | Co dělá na kopci |
|---|---|
| `slope_physics.gravity` | síla svahu i pád po skoku (vyšší = víc ztrácí do kopce, kratší skoky) |
| `slope_physics.slope_force_scale` | jen síla svahu (0 = kopce nebrzdí), skok nemění |
| `slope_physics.suspension_travel` | kolik metrů kola sledují terén, než auto vyletí (vyšší = méně skoků) |
| `slope_physics.hard_landing` | od jaké rychlosti dopadu je dopad tvrdý (ztráta rychlosti, otřes) |
| `speed_mps.cruise` | cestovní rychlost s automatickým plynem (do kopce a z kopce) |
| `camera.topdown.height_m` | výška kamery = síla perspektivy kopců shora (nižší = výraznější reliéf) |
| `camera.heading_follow_rate` | jak rychle se mapa natáčí za autem v serpentinách |
| `view_width_m.slow`, `view_width_m.fast` | přiblížení podle rychlosti |

Nejdou ladit za jízdy (jsou v balíčku, změna = `citypack build prague` a nový `packs.lock`):
`terrain.exaggeration` (převýšení, dnes 2,0), `terrain.max_grade` (strop sklonu podle třídy
silnice), `terrain.pipeline.shade_strength` (síla stínování) a `terrain.pipeline.sun`.
Kamera šikmého pohledu `camera.chase.*` platí až s F-074. Ve F jsou stejné klíče svahů zatím
mimo ladicí panel (F-070 ve F po vystřelení, L3).

## Automatická kontrola

`web/test/pragueHills.test.ts` pustí autopilota (`specs/bench.md`) po všech třech trasách na
skutečném balíčku bez vykreslování a hlídá 0 vyproštění (`specs/flow.md`), 0 přeskoků autopilota
a 0 pádů do vody; čísla vypíše s `HILLS_REPORT=<soubor> npx vitest run test/pragueHills.test.ts`.
Ověření kopců na telefonu (M5-A5) zůstává na Ol1novi.

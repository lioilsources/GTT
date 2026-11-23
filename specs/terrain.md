# Terén – výšky, svahy a skoky

**version: 2** · data P0 (citypack, shodná v obou klientech) · fyzika P1 (±5 %, scénáře
`scenarios/terrain/`) · pohled shora s reliéfem P2 · plán `Prompts/02-METROPOLE_TERRAIN_PLAN.md`,
pod-plán `plans/M5_TEREN_PRIRODA.md` · parita F-070 (svahy a skoky), F-071 (reliéf shora),
F-074 (šikmý pohled, jen W)

## Účel
Město má skutečný reliéf: do kopce auto ztrácí, z kopce nabírá, přes hranu skočí, a hráč to
vidí. Výšky jsou data v citypacku (krok `elevation`, `specs/citypack.md`), fyzika je tato
specifikace, klient se liší jen tím, kolik reliéfu ukáže. Čísla jsou v `content/tuning.yaml` →
`terrain`, `slope_physics`, `camera.topdown`, `camera.chase`. Všechno je přídavné: balíček bez
`manifest.terrain_version` se jezdí naplocho jako dosud (z = 0 všude, žádná síla svahu, žádný
skok).

## Data v balíčku (návrh polí, `.proto` přibude s T0)
Všechny výšky jsou **herní** (po převýšení a omezení sklonu), v decimetrech, relativně k `z0`.

| Zpráva | Pole | Popis |
|---|---|---|
| `Manifest` | `terrain_version` (uint32), `z0_m` (float), `exaggeration` (float) | `terrain_version = 0` nebo chybí = bez výšek |
| `Chunk` | `terrain` (bytes, 33 × 33 × int16 LE, řádky od jihu) | mřížka po `terrain.grid_m` (8 m), okraje sdílené se sousedy |
| `Chunk` | `shade` (bytes, 33 × 33 × uint8) | stínování svahu 0–255 (128 = rovina), slunce az. 315°, výška 45°; sklony herního terénu násobené `terrain.pipeline.shade_strength` (v2: 3,0) |
| `Node` | `z_dm` (sint32) | výška uzlu |
| `Edge` | `z_dm` (repeated sint32, po vrcholech) | hrany s převýšením zhuštěné na úseky ≤ 16 m; `stairs` (bool) = schody, pro auta neprůjezdné |
| pás silnice | `z_dm` u vrcholů | pásy zhuštěné po 8 m |
| `Building` | `base_z_dm` | nejnižší bod terénu pod půdorysem |
| `Ground` (voda) | `z_dm` | hladina |
| `lod/{x}_{y}.pb` | hrubý terén 32 m + hmoty bloků, po 4 × 4 chuncích | jen šikmý pohled |

Záruky dat (v2, `citypack validate`):
- Terén řídí jen pozemní hrany (ne most, ne tunel, vrstva 0 na obou koncích). Pod mostem, nájezdem
  a v tunelu má terén vlastní tvar, auto tam jede po povrchu hrany (`groundZ` výše). Most, který
  Overture vede ve vrstvě 0 (Mánesův most), je pořád most.
- Most, nájezd a estakáda (netunelová hrana mimo terén) mají spojitou desku: konec hrany má výšku
  svého uzlu, uvnitř hrany žádný skok nad 0,05 m. V jejich půdorysu na zemi neroste strom.
- Ve vodě neleží žádný bod mřížky nad hladinou. Výjimka: body, které nese pás pozemní silnice na
  břehu (buňka 8 m nemůže z vozovky spadnout k vodě; hladina je překryje).
- Na vozovce ponechané pozemní silnice čte bilineární terén profil silnice: odchylka ≤ 0,15 m
  aspoň u 99,5 % vzorků, nikde nad 1,0 m (`terrain.pipeline.road_strip`). Výjimky jsou ostré
  zatáčky serpentin, kde se profil ohne uvnitř jedné buňky. Vzorky, jejichž buňku sdílí jiná
  silnice (nebo jiné rameno téže) v jiné výšce, se nepočítají.

Klient, který výšky nepodporuje, nová pole ignoruje (protobuf).

## Výška pod bodem
```
groundZ(x, y, surface):
  surface = terén   → bilineární interpolace v mřížce chunku (dm → m)
  surface = hrana E → průmět bodu na osu E, lineární interpolace mezi jejími vrcholy
```
Auto si drží `surface`. Na most, do tunelu a na estakádu přechází na nájezdu (hrana s přechodem
vrstvy, `specs/drive.md` krok 6) a jede po povrchu hrany, jinak po terénu. Kolizní vrstvy platí
beze změny. Mimo načtené chunky `groundZ` = výška nejbližšího uzlu.

## Svah (krok jízdy, po kroku 5 „Pneumatiky“ ve `specs/drive.md`)
Na zemi (`airborne = false`):
```
grad   = (groundZ(x+1, y) − groundZ(x−1, y), groundZ(x, y+1) − groundZ(x, y−1)) / 2   (m/m)
k      = 1 / sqrt(1 + |grad|²)
a_svah = −slope_physics.gravity · slope_physics.slope_force_scale · grad · k     (m/s², vektor)
grip   = grip · k
```
- Síla `m · a_svah` působí v těžišti. Pod `drive.stop_speed_mps` (0,5 m/s) bez plynu se
  neuplatní: stojící auto na svahu drží.
- Provoz a hlídky (AI) sílu svahu nepočítají; sledují výšku a do kopce s `grad > 0,08` jedou
  rychlostí × 0,8.

## Skok
Stav auta navíc: `z`, `vz`, `airborne`, `g_prev`. Každý krok **po** vodorovném pohybu:
```
g  = groundZ(poloha, surface)
vg = (g − g_prev) / dt
vz = vz − gravity·dt;  z = z + vz·dt          # karoserie padá volně
když z ≤ g:
    když airborne: dopad = vg − vz             # rychlost dopadu (m/s, kladná)
    z = g;  vz = vg
mezera   = z − g
airborne = mezera > slope_physics.suspension_travel
g_prev   = g
```
- `airborne`: nepůsobí pneumatiky, plyn, brzda, řízení ani síla svahu, jen odpor vzduchu
  (`drive.drag_*`). Úhlová rychlost se zachová.
- Dopad nad `slope_physics.hard_landing` (10 m/s): rychlost × 0,85, otřes kamery 0,3 s. Auto se
  nepoškodí (K4).
- `mezera` řídí oddělení a zmenšení stínu auta (`stín = 1 / (1 + mezera / 4)`).
- Vozidla AI neskáčou (drží `z = g`).
- `dopad` se hlásí při prvním dotyku (`z ≤ g`) poté, co auto bylo `airborne`: příznak `airborne`
  spadne už při `mezera ≤ suspension_travel`, tedy o krok či několik dřív než samotný dotyk.
- Pod `drive.stop_speed_mps` „bez plynu“ (síla svahu se neuplatní) = motor v tom kroku nedává
  žádnou sílu (zrychlení z kroku 2 `drive.md` je 0: ruční brzda na místě, vstup `coast`).
- Při přechodu na jiný `surface` (nájezd) se `g_prev` přepočítá na novém povrchu, aby přechod
  nevytvořil falešné `vg`.

### Kontrolní hodnoty (akceptace, krok 1/60 s, `gravity` 20, `suspension_travel` 0,5)
| Situace | Výsledek |
|---|---|
| 30 m/s, hrana ze stoupání 15 % do klesání 15 % | 0,77 s a 23 m ve vzduchu, dopad 8,7 m/s |
| 40 m/s, hrana 20 % / 20 % | 1,53 s a 61 m, dopad 15,7 m/s (tvrdý) |
| 15 m/s, hrana 5 % / 5 % | žádný skok (mezera 0,04 m) |
| 30 m/s, schod dolů 5 cm | žádný skok |
| 30 m/s, zvlněná silnice ±0,3 m s periodou 19 m | žádný skok |

Tabulka platí pro čistý model skoku (vodorovná rychlost konstantní, bez odporu). Klient ji
ověřuje unit testem nad samotnou funkcí kroku skoku s tolerancí ±2 %.

## Scénáře P1 (`scenarios/terrain/`, tolerance ±5 %, auto `sedan_regent`)
Plán uvádí `sedan_01`; v repu takové auto není, referenční sedan je `sedan_regent`.
Scénáře běží na syntetické trati (rovina, rampy, hrana), kterou klient postaví z popisu níže,
ne na balíčku města.
1. `downhill_coast` – sjezd 200 m při 10 % bez plynu z 0 m/s: rychlost na konci.
2. `uphill_launch` – rozjezd do kopce 15 % s plným plynem: čas na 20 m/s.
3. `jump_30_15` a `jump_40_20` – skoky z tabulky: doba letu, délka letu, rychlost dopadu.
4. `hold_20` – stání na svahu 20 % bez plynu 5 s: posun 0 (tolerance 0,05 m).
5. `bridge_7` – přejezd mostu s nájezdy 7 % plynem do `cruise`: rychlost na vrcholu a za mostem.

**Syntetická trať:** balíček s `terrain_version` 1, `chunk_m` 256, `exaggeration` 1, `z0` 0;
silnice podél osy x (y = 0), `primary`, 2 pruhy, obousměrná, `kept`, šířka 20 m. Terén všech
chunků x −3…2, y −1…0 je profil `z(x)` (stejný pro každé y, vzorky po 8 m). Hrany mají body po
16 m a výšky lineárně mezi uzly. Pozemní trať: uzly po 64 m od −512 do 512 m ve výšce profilu,
všechny ve vrstvě 0. Bez budov, mobiliáře a provozu (`solid = false`), krok `drive.step_hz`.
Start = (x, 0), natočení 0 (na východ), rychlost ve směru jízdy; vstupy podle souboru scénáře
(`throttle`, `steer`, `brake` a `coast` od času `t`; `coast` = motor vypnutý: žádný automatický
plyn ani brzdění motorem). Testy W: `web/test/terrainScenarios.test.ts`.

| scénář | profil `z(x)` / trať | start x, rychlost | délka | metriky |
|---|---|---|---|---|
| `downhill_coast` | −0,1·x | −100, 0,5 m/s (= `stop_speed`, z klidu by auto drželo) | do x = 100 | `end_speed_mps`, `time_s` při x ≥ 100 |
| `uphill_launch` | 0,15·x | −100, 0 | 30 s | `t_20_mps_s` = čas, kdy rychlost ≥ 20 |
| `jump_30_15` | 0,15·x pro x < 0, jinak −0,15·x | −2, 30,3 m/s | 3 s | `takeoff_mps` (rychlost v 1. kroku `airborne`), `air_s` (součet kroků `airborne`), `air_m` (dráha v nich), `landing_mps` (`dopad`) |
| `jump_40_20` | 0,2 / −0,2 | −2, 40,4 m/s | 3 s | jako výše + `after_mps` (rychlost na konci) |
| `hold_20` | 0,2·x | 0, 0 | 5 s | `drift_m` = vzdálenost od startu |
| `bridge_7` | terén 0; uzly (−400, 0) (−100, 0) (0, 7) (100, 7) (200, 0) (500, 0), hrany ve vrstvách 0→0, 0→1 most, 1→1 most, 1→0 most, 0→0 | −300, 25 m/s | 30 s | `v_at_m100_mps`, `v_at_0_mps`, `v_at_100_mps`, `v_at_200_mps`, `v_at_300_mps` = rychlost při prvním x ≥ −100, 0, 100, 200, 300 |

Kontrolní tabulka skoků platí pro čistý model; skutečné auto ve scénářích ztrácí ve vzduchu
rychlost odporem (`drag_*`), proto je let o několik procent kratší (40 m/s: délka −10 %).

Hodnoty nahraje vedoucí klient (web), druhý je musí trefit (DUALSTACK 5.5).

## Jednotná zobrazená výška a kamera shora
Každý bod světa má zobrazenou výšku `z`: terén svou herní výšku, střecha `base_z + zobrazená výška
budovy`. Kamera shora je kolmo nad autem ve výšce `z_ref + H`, `z_ref` = výška země pod autem
vyhlazená exponenciálně (rate 2/s), `H = camera.topdown.height_m`.
- **W** staví sítě ve skutečné zobrazené výšce.
- **F** promítá každý bod: `s = H / (H − (z − z_ref))`, `p' = VP + (p − VP) · s`, kde `VP` je
  bod pod kamerou; `z − z_ref` se ořízne na `[−2H, 0,8H]`. Pro budovu na rovině dává vzorec
  totéž co dosavadní extruze.
- Kontrola: kopec o 30 m výš ve vzdálenosti 100 m se posune o 13,6 m od středu (H = 250).

### Nápovědy reliéfu shora (oba klienti)
- stínování z `shade` násobí barvu terénu i silnic (`c × (0,75 + 0,5 × shade / 255)`)
- šipky na vozovce u úseků se sklonem nad 8 %, mířící do kopce (barva `marking`, každých 24 m)
- stín auta se při skoku oddělí a zmenší (viz Skok)
- HUD: sklon v % (zaokrouhlený, jen nad 2 %) a nadmořská výška `z0 + z / exaggeration` v m
- krátké oddálení kamery (× 1,15 na 0,4 s) na hraně (začátek `airborne`) a při tvrdém dopadu

## Šikmý pohled (jen W, P2)
Kamera `camera.chase`: `distance_m` za autem, `height_m` nad ním, míří `look_ahead_m` před auto,
`fov_deg`. Plynulé dotáčení za autem, budovy mezi kamerou a autem zprůhlední (alfa 0,3). Vzdálený
prstenec do 1,5 km z `lod/`, mlha, obloha, slunce shodné se stínováním. Přepínač v nastavení a
gestem (dvojí klepnutí dvěma prsty); výchozí je pohled shora (K1 = A). Rozpočet navíc nejvýš
40 draw calls a 60 tisíc trojúhelníků.

### Upřesnění T2 (klient W, F-074)
- **Kamera:** směr za autem se vyhlazuje jako shora (`camera.heading_follow_rate`, při couvání se
  nedotáčí); kamera stojí `distance_m` za autem ve výšce `z_ref + height_m`, cíl je `look_ahead_m`
  před autem ve výšce `z_ref`. `fov_deg` platí pro kratší stranu obrazovky (na výšku vodorovně).
  Oddálení na hraně a při tvrdém dopadu násobí `distance_m` i `height_m`, třes posouvá kameru i cíl.
- **Zprůhlednění:** fragment budovy nebo mostovky, který je blíž kameře než auto a nejvýš 6 m od
  úsečky kamera–auto, se kreslí rastrem 4 × 4 s pokrytím 0,3 (alfa 0,3 bez řazení průhledných ploch);
  stejně i v hloubkovém průchodu risografu, aby auto bylo vidět.
- **Prstenec:** dlaždice `lod/`, jejichž obdélník zasahuje do 1,5 km od auta, jedna síť a jeden
  draw call na dlaždici; kreslí se jen mimo načtené chunky (maska chunků v shaderu). Terén z mřížky
  33 × 33 v barvě `land` × stínování ze sklonu mřížky se sluncem jako `shade` (az. 315°, výška 45°);
  hmoty bloků od `base_z` do zobrazené výšky budovy (`extrusion`) v barvách fasád; `wood` a
  `parkland` jako zelené hmoty `color.green.wood` / `color.green.parkland` do `height_m`; voda jako
  jedna plocha v barvě `water` ve výšce hladiny okolní mřížky.
- **Mlha a obloha:** lineární mlha od 0,5 do 1,5 km do barvy `color.world.sky.horizon` (v noci
  `nightHorizon`), obloha přechodem od horizontu k `color.world.sky.zenith` (`nightZenith`). Shora
  mlha ani obloha nejsou.
- **Přepínač:** kulaté tlačítko v HUD, dvojí klepnutí dvěma prsty (druhé do 0,35 s)
  a aplikace Nastavení v telefonu (`cameraTopdown` / `cameraChase`). Přepnutí za jízdy je okamžité,
  dlaždice prstence se načítají na pozadí a staví po jedné za snímek. Volba se pamatuje jen ve W v
  `localStorage` (`metro:camera`); uložení hry (`specs/save.md`, P0) se nemění. Ladění `?camera=chase`.

## Hraniční případy
- Balíček bez výšek: `groundZ = 0`, `grad = 0`, nikdy `airborne`; vše jako před v1.
- Hrana `stairs`: pro auta zeď (jako budova ve vrstvě 0), chodci po ní chodí.
- Teleport (metro, vyproštění, přesun města): `z = g`, `vz = 0`, `airborne = false`.
- Chunk se načte pod letícím autem: `g` skočí, auto dosedne podle pravidla `z ≤ g`.
- Ruční brzda ve vzduchu nemá účinek.

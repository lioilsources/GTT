# Plynulá jízda – nárazy, měkké stromy, vyproštění

**version: 2** · P1 (±5 %, scénáře `scenarios/flow/`) · plán `Prompts/04-METROPOLE_FLOW_PLAN.md`
· pod-plán `plans/M5_TEREN_PRIRODA.md` · parita F-069 (nárazy a vyproštění), F-073 (les a stromy)

## Účel
Hráč se nezasekne (F2). Strom auto zpomalí a odkloní, nikdy nezastaví (F3). Náraz do zdi vede
podél zdi nebo odrazí, a když přesto auto stojí, hra ho sama vrátí na jeho stopu. Zaseknutí se
měří (F4). Čísla `content/tuning.yaml` → `flow`, hustota lesa `nature.trees_per_ha.wood`.
Rozhodnutí Ol1na (defaulty): P1 = všechny stromy měkké, P2 = les zpomaluje na 60 %, P3 = limit
1 zaseknutí za 10 minut.

## Změny ve v2 (FL1, upřesnění z klienta W, F-069)
- Odraz s odlepením 1 m jen na začátku kontaktu a jen „nabitý“ (níže); klouzání v každém kroku kontaktu.
- Série vyproštění: každé do 5 s od **předchozího** (v1: „posledních 5 s“ od teď – nejkratší rozestup je
  1,4 + 1,5 s, takže třetí pokus by nikdy nenastal).
- Stopa drží body mladší 5 s (čas vzorku), návrat po stopě stopu za zvoleným bodem zkrátí.
- Kontextové tlačítko automatické vyproštění neblokuje (blokuje jen otevřená nabídka, a ta pauzuje).
- Syntetická trať a metriky scénářů FL1.

## Stav (navíc k `specs/drive.md`)
```
trail:   [{x, y, heading, t}] # body mladší 5 s, nejvýš 20 (po 0,25 s), nejnovější na konci
stuckT:  s                    # jak dlouho je auto pomalé bez brzdy
slowT:   s                    # jak dlouho je auto pomalé (tlačítko „Na silnici“)
rescues: [{t, x, y}]          # současná série automatických vyproštění (t = čas jízdy, x, y = kde stálo)
armed:   bool                 # čelní odraz je nabitý
freeT:   s                    # jak dlouho auto nemá statický kontakt
graceT:  s                    # ochranná doba po přesunu
treeCd:  {treeKey: s}         # cooldown zásahů stromů
```

## Náraz do pevné překážky (budovy, zdi, pilíře, zábradlí; vrstva 0 nebo zábradlí mostu)
Po kroku fyziky, když auto v tomto kroku kontaktovalo statickou geometrii s normálou `n`
(jednotková, od stěny k autu) a rychlost `v` před kontaktem:
```
α = úhel mezi směrem jízdy (v̂) a stěnou = asin(|v̂ · n|)
když α < flow.wall.slide_angle_deg:            # šikmý náraz → klouzání
    t   = jednotkový vektor stěny ve směru v (v − (v·n)n, normalizovaný)
    v'  = t · max(|v − (v·n)n|, |v| · flow.wall.slide_speed_keep · cos α)
    natočení auta se dorovná k t rychlostí 6 rad/s (exponenciálně), úhlová rychlost × 0,5
jinak                                           # čelní náraz → odraz
    v'  = −(v·n)n · flow.wall.restitution + (v − (v·n)n)
    auto se posune o 1,0 m po n (odlepení od stěny), úhlová rychlost 0
```
- **Který kontakt (v2):** ze všech dotýkajících se statických kontaktů po kroku (budovy, sloupky zón,
  zábradlí mostu) se bere normála, do které `v` míří nejvíc (nejmenší `v·n`); `v·n ≥ 0` → nic.
- **Kdy (v2):** klouzání v každém kroku kontaktu. Odraz jen v kroku, kdy kontakt začal (předchozí krok
  bez statického kontaktu), a jen když `armed`; odraz nastaví `armed = false`. `armed = true` po
  `flow.rescue.stuck_time_s` bez statického kontaktu (`freeT`) nebo po vyproštění. Jinak by auto
  s automatickým plynem po každém odlepení narazilo znovu a nikdy by nestálo; takhle druhý náraz
  vyřeší fyzika (tření a restituce níže) a auto se zastaví o stěnu.
- Kontakt se statickou geometrií má tření `flow.wall.friction` (místo `drive.building_friction`)
  a restituci `flow.wall.restitution` (místo `drive.building_restitution`).
- Kontrola: šikmo pod 30° při 20 m/s → po sklouznutí aspoň 14,7 m/s ve směru stěny
  (20 · 0,85 · cos 30° = 14,72).

## Strom jako měkká překážka
Kmen = senzor (bez fyzického tělesa), kruh poloměru `nature.trunk_radius_m`. Kontrola překryvu
středu auta zvětšeného o půlšířku auta. Fyzické zpracování jen u stromů do 80 m od hráče, nejvýš
200 nejbližších. Při začátku překryvu (strom mimo `treeCd`):
- **S (stromek):** `v × flow.tree_hit.sapling_speed_keep`, strom padne ve směru jízdy (kreslení
  ho 60 s mimo záběr nezobrazuje, pak se obnoví), bez vytlačení.
- **M, L:** `v_new = v × speed_keep`; když `|v| > min_speed_mps`, pak `|v_new| ≥ min_speed_mps`.
  Strana `side = sign(cross(v̂, (kmen − auto)))` (kmen vlevo = +1). Po dobu překryvu se k rychlosti
  přičítá boční složka `−side · push_mps` kolmo na `v̂` (auto se odsune od kmene) a jednorázově
  se natočí o `−side · yaw_kick_deg`. Zatřesení koruny, listí, zvuk (P2).
- `treeCd[strom] = flow.tree_hit.cooldown_s`. Bez náhody (shodné v obou klientech).
- Klíč stromu = `"<cx>_<cy>/<index v Chunk.trees>"`.

## Les
Povrch `forest`: `grip × flow.forest.grip`, cílová i maximální rychlost a síla motoru ×
`flow.forest.speed_factor`. Les nemá kolizi, jen stromy výše. Hlídky a AI zůstávají na silnicích
(les je úkryt, pravidlo úniku `specs/police.md` beze změny).

## Vyproštění
**Stopa:** každých 0,25 s, když `|v| > 3 m/s` a auto není `airborne` (`specs/terrain.md`) a neběží
animace přesunu, přidá se `{x, y, heading, t}` na konec `trail`; každý krok se zahodí body starší 5 s
(auto, které se dlouho plouží podél zdi, tak nemá stopu daleko za sebou), nejvýš 20 bodů.

**Automaticky** – každý krok, mimo `graceT`, bez otevřené kontextové nabídky, pauzy, minihry
(v2: zobrazené kontextové *tlačítko* – „Přesednout“, „Hrát“ … – neblokuje; stát bez brzdy znamená, že
auto něco drží, automatický plyn by jinak jel dál. „Brzdí“ = brzda/couvání nebo ruční brzda):
- když `|v| < flow.rescue.stuck_speed_mps` a hráč nebrzdí: `stuckT += dt`, jinak `stuckT = 0`
- při `stuckT ≥ flow.rescue.stuck_time_s`:
  1. když je `rescues` prázdné, poslední je starší než 5 s nebo je auto dál než 25 m od prvního
     z nich: `rescues = []`; `n = len(rescues)`
  2. `n = 0`: návrat po stopě o `rewind_m[0]`; `n = 1`: o `rewind_m[1]`; `n ≥ 2`: přesun na silnici
  3. návrat po stopě: bod `trail` nejbližší (po délce stopy od konce) vzdálenosti `rewind_m[i]`
     od aktuální polohy (délka = od auta k nejnovějšímu bodu a dál mezi body); když je stopa kratší,
     nejstarší bod; když je prázdná, přesun na silnici. Auto dostane polohu a natočení bodu,
     `trail` se zkrátí na body do zvoleného včetně.
  4. přidat `{t, x, y}` do `rescues`, `stuckT = slowT = 0`, `graceT = 1,4 s` (0,4 s animace + 1 s)
- **Přesun na silnici:** nejbližší uzel ponechané silnice ve vrstvě 0 (`hop` hledání jako
  spawn, `layers.spawn_search_m`), čelem ve směru trasy GPS, bez trasy ve směru první hrany
  uzlu; `trail` se vyprázdní. (v2: uzel = konec hrany s `kept` a vrstvou 0 na obou koncích, nejbližší
  vzdušnou čarou, při shodě menší index. Trasa GPS = lomená čára zbývající trasy; platí, když její
  nejbližší úsek je od uzlu do `layers.search_m`, směr toho úseku. Jinak první hrana uzlu
  v `nodeEdges` s `kept` a vrstvou 0, směr od uzlu podél ní.)
- Přesun = animace 0,4 s (auto zprůhlední a objeví se), rychlost 0, `z = groundZ`.
  Vyproštění je zdarma. (v2: auto je na novém místě od začátku animace a 0,4 s stojí – rychlost
  i úhlová rychlost 0, vstup se ignoruje; kreslení ho během animace zviditelňuje z 0 na 1. Totéž
  těleso, bez respawnu; vrstva se znovu určí jako při spawnu, `armed = true`.)

**Ručně:** když `|v| < stuck_speed_mps` déle než `flow.rescue.button_after_s` (`slowT`, počítá se
i s brzdou), HUD ukáže tlačítko „Na silnici“ (`flowToRoad`). Je vždy i v nabídce pauzy. Provede
přesun na silnici. Zdarma. (v2: stejná animace a `graceT`; do `rescues` se nepočítá. Ve W je
nabídkou pauzy domovská obrazovka telefonu.)

Poplatek zůstává jen u pádu do vody (`specs/nature.md`) a u rozbitého auta.

## Měření zaseknutí
- Zaseknutí = každé automatické vyproštění a každé použití „Na silnici“.
- Ladicí overlay: počet zaseknutí za posledních 10 minut jízdy (čas jízdy = čas mimo pauzu a
  minihry).
- Ladicí build zapisuje každé zaseknutí jako řádek `{"t": unix_s, "city", "x", "y", "kind":
  "auto1"|"auto2"|"road"|"button"}` do místního `stuck.log` (F: dokumenty aplikace, W:
  `localStorage` klíč `metro.stuck` + tlačítko Kopírovat v ladicím panelu). Nic se neodesílá.
- `metro stuckmap <city> <stuck.log>` vykreslí body na náhled balíčku a vypíše deset nejhorších
  míst (shluky 25 m).

## Scénáře (`scenarios/flow/`, ±5 %, `sedan_regent`, syntetická trať)
**Syntetická trať (v2):** graf `0 (−200, 0) ─e0─ 1 (0, 0) ─e1─ 2 (200, 0)`, obě hrany `primary`,
2 pruhy, obousměrné, `kept`, šířka 20 m, vrstva 0. Budovy (kolize, výška 10 m): stěna W = obdélník
x −100…60, y 40…60 (líc y = 40), blok B = x 60…80, y 15…60 (líc x = 60); kout W/B v (60, 40).
Bez mobiliáře, provoz nepevný (`solid = false`), bez počasí, krok `drive.step_hz`. Start = poloha,
natočení a počáteční rychlost ve směru natočení; vstupy podle souboru scénáře (`throttle`, `steer`,
`brake` od času `t`). Kontakt = statický kontakt po kroku (výše). Testy W: `web/test/flow.test.ts`.

| scénář | start (x, y, natočení, rychlost) | délka | metriky |
|---|---|---|---|
| `wall_30` | (0, 33,8), 30°, 20 m/s | 2 s | `along_wall_mps` = vx v kroku prvního kontaktu; `along_wall_min_1s_mps` = nejmenší vx v 1 s od něj; `rescues` |
| `wall_head_on` | (0, 5), 90°, 0 | 8 s | `rescue_after_contact_s` = čas 1. vyproštění − čas 1. kontaktu; `rescue_kind` (1 = auto1, 2 = auto2, 3 = silnice); `rewind_m` = vzdálenost polohy před a po přesunu |
| `corner_3x` | (20, 0), 47°, 0 | 20 s | `rescueN_kind` prvních tří vyproštění; `rescue3_on_road` = 1, když je auto po 3. přesunu na ponechané hraně (do 1 m); `rescue3_t_s` = čas jízdy 3. vyproštění |

1. `forest_200` – 200 m lesem (stromy M po 11 m v pruhu) plnou rychlostí: min. rychlost ≥
   `min_speed_mps`, 0 vyproštění.
2. `tree_head_on` – čelně do stromu M při 20 m/s: rychlost po nárazu 15 m/s, auto mine kmen.
3. `wall_30` – šikmo do zdi pod 30° při 20 m/s: ≥ 14,7 m/s ve směru stěny.
4. `wall_head_on` – čelně do zdi s plynem: do 2,5 s automatické vyproštění, auto stojí 8 m zpět
   na vlastní stopě.
5. `corner_3x` – třikrát po sobě do téhož kouta: třetí vyproštění skončí na silnici.

## Data bez pastí (pipeline, FL0)
- Mezera mezi budovami užší než `flow.gap_close_m` se v kroku `buildings` uzavře (buffer
  `+gap/2`, sjednocení, buffer `−gap/2`). Platí pro vykreslení i kolizi.
- Ulička užší než `gap_close_m` dostane `Edge.micro_only = true` a na obou koncích sloupky
  (`Chunk.barriers`). Projede jen mikrovozidlo (třída `micro`).
- `validate` vypíše počet uzavřených štěrbin a zúžených uliček.

## Hraniční případy
- Náraz při `airborne`: platí stejně (auto ve vzduchu do zdi narazí).
- Vyproštění během policejní honičky: povoleno, hledanost se nemění.
- Vyproštění na mostě (vrstva ≠ 0): přesun na silnici hledá jen ve vrstvě 0.
- Strom padlý (S) neblokuje nic.

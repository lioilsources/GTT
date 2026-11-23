# Plynulá jízda – nárazy, měkké stromy, vyproštění

**version: 1** · P1 (±5 %, scénáře `scenarios/flow/`) · plán `Prompts/04-METROPOLE_FLOW_PLAN.md`
· pod-plán `plans/M5_TEREN_PRIRODA.md` · parita F-069 (nárazy a vyproštění), F-073 (les a stromy)

## Účel
Hráč se nezasekne (F2). Strom auto zpomalí a odkloní, nikdy nezastaví (F3). Náraz do zdi vede
podél zdi nebo odrazí, a když přesto auto stojí, hra ho sama vrátí na jeho stopu. Zaseknutí se
měří (F4). Čísla `content/tuning.yaml` → `flow`, hustota lesa `nature.trees_per_ha.wood`.
Rozhodnutí Ol1na (defaulty): P1 = všechny stromy měkké, P2 = les zpomaluje na 60 %, P3 = limit
1 zaseknutí za 10 minut.

## Stav (navíc k `specs/drive.md`)
```
trail:   [{x, y, heading}]   # nejvýš 20 bodů (5 s po 0,25 s), nejnovější na konci
stuckT:  s                    # jak dlouho je auto pomalé bez brzdy
slowT:   s                    # jak dlouho je auto pomalé (tlačítko „Na silnici“)
rescues: [{t, x, y}]          # automatická vyproštění za posledních 5 s
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
**Stopa:** každých 0,25 s, když `|v| > 3 m/s` a auto není `airborne` (`specs/terrain.md`),
přidá se `{x, y, heading}` na konec `trail`; drží se posledních 5 s (20 bodů).

**Automaticky** – každý krok, mimo `graceT`, bez otevřené kontextové nabídky, pauzy, minihry:
- když `|v| < flow.rescue.stuck_speed_mps` a hráč nebrzdí: `stuckT += dt`, jinak `stuckT = 0`
- při `stuckT ≥ flow.rescue.stuck_time_s`:
  1. `rescues` vyčistit na posledních 5 s; `n = len(rescues)`
  2. `n = 0`: návrat po stopě o `rewind_m[0]`; `n = 1` (do 5 s od prvního, do 25 m od něj):
     o `rewind_m[1]`; `n ≥ 2`: přesun na silnici (níže)
  3. návrat po stopě: bod `trail` nejbližší (po délce stopy od konce) vzdálenosti `rewind_m[i]`
     od aktuální polohy; když je stopa kratší, nejstarší bod; když je prázdná, přesun na silnici
  4. přidat `{t, x, y}` do `rescues`, `stuckT = 0`, `graceT = 1,4 s` (0,4 s animace + 1 s)
- **Přesun na silnici:** nejbližší uzel ponechané silnice ve vrstvě 0 (`hop` hledání jako
  spawn, `layers.spawn_search_m`), čelem ve směru trasy GPS, bez trasy ve směru první hrany
  uzlu; `trail` se vyprázdní.
- Přesun = animace 0,4 s (auto zprůhlední a objeví se), rychlost 0, `z = groundZ`.
  Vyproštění je zdarma.

**Ručně:** když `|v| < stuck_speed_mps` déle než `flow.rescue.button_after_s` (`slowT`, počítá se
i s brzdou), HUD ukáže tlačítko „Na silnici“ (`flowToRoad`). Je vždy i v nabídce pauzy. Provede
přesun na silnici. Zdarma.

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

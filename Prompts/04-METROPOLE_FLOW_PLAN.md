# METROPOLE_FLOW_PLAN.md

**Stav:** inkrement. Starší plány se nemění, tento dokument je doplňuje.
**Datum:** 2026-11-23
**Pro:** kódovací model (Opus, střední effort). Kapitola 8 = rozhoduje Ol1n, do té doby platí default.

**Pořadí platnosti** (novější má při rozporu přednost):

1. `METROPOLE_PLAN.md`
2. `METROPOLE_DUALSTACK_PLAN.md`
3. `METROPOLE_TERRAIN_PLAN.md`
4. `METROPOLE_NATURE_PLAN.md`
5. tento dokument

**Co mění:**

| Plán | Místo | Změna |
|---|---|---|
| voda a zeleň | N5, otázka V1 | rozhodnuto: les je průjezdný |
| voda a zeleň | 3.2, řádek `wood` | jednotlivé stromy, povrch `forest`, průjezdné |
| voda a zeleň | kap. 4 bod 3 | lesní hmota s kolizí ani koridory cest se nevytvářejí |
| voda a zeleň | „Co přibude v citypacku" | pole `woods` se do chunků nezapisuje (hmoty zůstávají jen v `lod/`) |
| voda a zeleň | 5.3, 5.4 | les se nekreslí jako nízká budova, ale jako hustší stromy |
| voda a zeleň | kap. 6, Stromy a Les | strom je měkká překážka; les nemá kolizi |
| voda a zeleň | validate | kontrola „každá cesta lesem má koridor" odpadá |
| hlavní | 5.3 bod 4 | úzké štěrbiny mezi budovami se uzavírají |
| hlavní | 7.2 | odezva na náraz, vyproštění |

---

## 1. Rozhodnutí

| # | Rozhodnutí | Proč |
|---|---|---|
| F1 | Les je celý průjezdný. | Ol1n: nechce se zasekávat. |
| F2 | **Hráč se nezasekne.** Žádná situace nesmí skončit tak, že auto stojí a hráč neví, jak dál. Platí všude, nejen v lese. | Zaseknutí je nejrychlejší způsob, jak zabít radost z jízdy. |
| F3 | Strom auto nikdy nezastaví. Zpomalí ho a odkloní. | Průjezdný les s pevnými kmeny by zasekával víc než neprůjezdný. |
| F4 | Zaseknutí se měří a má limit. | Aby šlo poznat, jestli se to zlepšuje. |

## 2. Konfigurace

```yaml
# content/tuning.yaml
nature:
  trees_per_ha: {wood: 80}        # přibývá k hodnotám z plánu vody a zeleně
flow:
  forest: {grip: 0.7, speed_factor: 0.6, crown_fade_radius_m: 22}
  tree_hit:
    speed_keep: 0.75              # střední a velký strom
    sapling_speed_keep: 0.9       # stromek velikosti S
    min_speed_mps: 4              # pod tuhle rychlost náraz nezpomalí
    push_mps: 8                   # boční vytlačení od kmene
    yaw_kick_deg: 6
    cooldown_s: 0.5
  wall:
    slide_angle_deg: 45
    slide_speed_keep: 0.85
    restitution: 0.15
    friction: 0.05
  rescue:
    stuck_speed_mps: 1.0
    stuck_time_s: 1.5
    rewind_m: [8, 20]             # první a druhý pokus
    button_after_s: 3
  gap_close_m: 7
```

Hodnoty z plánu vody a zeleně `wood.inset_m`, `wood.edge_tree_step_m` a `wood.path_clear_m` se přestávají používat. `wood.canopy_height_m` platí už jen pro `lod`.

## 3. Průjezdný les

### 3.1 Data (krok `nature`)

- Polygon lesa zůstává jako zeleň třídy `wood` s povrchem `forest`.
- Stromy se v něm rozmisťují stejně jako v parkové zeleni, jen hustotou `trees_per_ha.wood`. To je asi 520 stromů na chunk plný lesa, pod limitem 600.
- Cesty lesem zůstávají uličkami z hlavního plánu. Na cestě stromy nejsou (pravidlo o vzdálenosti od silnic), takže je cesta v lese vidět jako průsek.
- Vzdálený prstenec `lod` se nemění: les je tam dál zelená hmota.

### 3.2 Vykreslení

- lesní půda tmavší zelenou z tokenů (`color.green.wood`), koruny hustší a tmavší než v parku
- koruny do `flow.forest.crown_fade_radius_m` od hráčova auta zprůhlední (v lese větší poloměr než jinde), takže hráč vidí auto i kmeny před sebou
- kmeny jako tmavé tečky jsou vidět vždy, i pod průhlednou korunou
- pořadí kreslení z plánu vody a zeleně platí bez lesních hmot

### 3.3 Jízda lesem

- Povrch `forest`: přilnavost × `grip`, maximální rychlost a zrychlení × `speed_factor`. Les zpomaluje, nezastavuje.
- Hlídky a ostatní auta AI zůstávají na silnicích. Les je tedy i úkryt: pravidlo úniku z hlavního plánu 7.4 platí beze změny.

## 4. Strom jako měkká překážka

Platí pro všechny stromy, v lese i mimo něj. Kmen není pevné těleso, ale senzor o poloměru `trunk_radius_m`.

Když se auto s kmenem překryje:

- **Stromek (S):** padne ve směru jízdy, rychlost × `sapling_speed_keep`. Po 60 s mimo záběr se obnoví (jako mobiliář v hlavním plánu 7.2).
- **Střední a velký strom (M, L):** rychlost × `speed_keep`, ale neklesne pod `min_speed_mps`, pokud byla před nárazem vyšší. Po dobu překryvu se auto vytlačuje do strany od kmene rychlostí `push_mps` a pootočí se o `yaw_kick_deg` na stejnou stranu. Koruna se zatřese, padá listí, zvuk nárazu.
- Stejný strom zasáhne znovu nejdřív za `cooldown_s`.

Reakce je bez náhody, aby se v obou klientech chovala stejně.

## 5. Plynulá jízda všude

### 5.1 Náraz do pevné překážky

Pevné zůstávají budovy, zdi, mostní pilíře a zábradlí.

- **Šikmý náraz** (úhel mezi směrem jízdy a stěnou pod `slide_angle_deg`): auto po stěně sklouzne, zachová aspoň `slide_speed_keep` rychlosti ve směru stěny a jeho směr se ke stěně plynule dorovná.
- **Čelní náraz:** auto se odrazí zpět (`restitution`) a odlepí se od stěny o 1 m, aby šlo hned zatočit.
- Kontakt auta se statickou geometrií má tření `friction`.

### 5.2 Vyproštění

Auto si každých 0,25 s ukládá polohu a směr, pokud jede rychleji než 3 m/s a není ve vzduchu. Drží posledních 5 s.

**Automaticky:** hráč nebrzdí, není otevřená kontextová nabídka a rychlost je pod `stuck_speed_mps` déle než `stuck_time_s`:

1. poprvé: auto se vrátí po uložené stopě o `rewind_m[0]`, se směrem, jaký tam mělo
2. podruhé na stejném místě do 5 s: o `rewind_m[1]`
3. potřetí: přesun na nejbližší uzel silnice, čelem ve směru trasy GPS (bez trasy ve směru silnice)

Přesun je krátká animace (0,4 s), 1 s po něm se nové zaseknutí nepočítá. Je zdarma.

**Ručně:** po `button_after_s` pomalé jízdy se objeví tlačítko „Na silnici" (stejný přesun jako v bodě 3). Je vždy i v nabídce pauzy. Je zdarma.

Poplatek zůstává jen u pádu do vody a u rozbitého auta, jak je v hlavním plánu a v plánu vody a zeleně.

### 5.3 Data bez pastí (pipeline)

- **Štěrbiny:** mezera mezi budovami užší než `gap_close_m` se v kroku `buildings` uzavře (rozšíření obrysů o polovinu této hodnoty a zpětné zúžení). Platí pro vykreslení i kolizi, žádné neviditelné zdi.
- **Úzké uličky:** ulička užší než `gap_close_m` dostane `micro_only: true` a na obou koncích viditelné sloupky. Projede jí jen mikrovozidlo.
- `validate` vypíše počet uzavřených štěrbin a zúžených uliček.

### 5.4 Měření

- Zaseknutí = každé automatické vyproštění a každé použití tlačítka „Na silnici".
- Ladicí overlay ukazuje počet zaseknutí za posledních 10 minut jízdy.
- Ladicí build zapisuje každé zaseknutí s polohou do místního souboru `stuck.log` (nic se neodesílá). `metro stuckmap <city>` z něj vykreslí mapu míst, kde se hráč zasekává, a vypíše deset nejhorších. Ta se pak opravují v datech.

## 6. Parita a scénáře

Odezva na strom, na stěnu i vyproštění jsou P1 (tolerance ±5 %). Scénáře z nahraných vstupů, auto `sedan_01`:

- 200 m lesem plnou rychlostí: rychlost nikdy neklesne pod `min_speed_mps`, žádné vyproštění
- čelně do středního stromu při 20 m/s: rychlost po nárazu 15 m/s, auto mine kmen
- šikmo do zdi pod 30° při 20 m/s: po sklouznutí aspoň 14,7 m/s ve směru stěny
- čelně do zdi s plynem: do 2,5 s automatické vyproštění, auto stojí 8 m zpět na vlastní stopě
- třikrát po sobě do téhož kouta: třetí vyproštění skončí na silnici

## 7. Fáze

| Fáze | Obsah | Kdy | Akceptace |
|---|---|---|---|
| **FL1 – Nárazy a vyproštění** | 5.1, 5.2, 5.4 v `drive_core` klienta F; ve W s fází D1 | hned po rozdělaném bodu; samostatná feature | scénáře se zdí projdou; Ol1n při dogfoodingu naměří nejvýš 1 zaseknutí za 10 minut jízdy v oblasti M1 |
| **FL0 – Data** | 5.3 a 3.1 v pipeline | s fází N0 | `validate` projde; na náhledu nejsou štěrbiny pod 7 m; les má stromy místo hmoty |
| **FL2 – Les a stromy v klientech** | kap. 3 a 4 | s fází N1 | scénáře lesa a stromu projdou; průjezd Central Parkem napříč lesem bez jediného vyproštění |

Položky zapiš do `plans/progress.yaml`, pokud se postup měří. Počet zaseknutí za 10 minut přidej mezi sledovaná počítadla.

## 8. Otevřené otázky pro Ol1na

| # | Otázka | Default |
|---|---|---|
| P1 | Stromy měkké všechny, nebo velké stromy pevné (auto po nich sklouzne jako po stěně)? | všechny měkké |
| P2 | Má les zpomalovat na 60 %, nebo méně? | 60 %, doladit při dogfoodingu |
| P3 | Limit zaseknutí pro akceptaci | 1 za 10 minut |

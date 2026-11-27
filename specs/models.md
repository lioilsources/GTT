# Modely památek

**version: 1** · P2 (vzhled), data v citypacku · plán `Prompts/06-METROPOLE_LANDMARKS3D_PLAN.md` ·
pod-plán `plans/M7_PAMATKY.md` · parita F-085 · bez vektorů

## Účel
Hlavní památky (`hero: true`) mají skutečný tvar: věže, střechy, nádvoří. Ve W v šikmém pohledu
model, v pohledu shora (W, později F) střešní plán. Tvar je jen obraz: kolize, trasy, pravidla a
uložení se nemění, auto dál naráží do půdorysů vrstvy 0 v chuncích. Čísla `content/tuning.yaml` →
`models`, barvy `design/tokens.json` → `color.model`, výběr a zdroj
`content/cities/<id>/models.yaml`.

## Stav (data, `models.pb`)
`Models.models[]`, jeden `Model` na památku (`tools/citypack/proto/citypack.proto`):
- `landmark_id` = `Landmarks.items[].id`; `source` (enum) → řádek atribuce v `Manifest.attribution`.
- `parts[]` = budovy zdroje, každá stojí na terénu sama (`ModelPart`):
  `anchor_x/y` (dm, těžiště půdorysu), `base_z_dm` (herní výška paty), `positions` (x, y, z po
  vrcholech; x, y dm od kotvy, z dm nad patou), `triangles` (CCW zvenku), `roles` (bajt `ModelRole`
  na trojúhelník), `foot` (vrcholy na zemi zdroje), `source_id`.
- `replaces[]` = budovy balíčku (`chunk_x`, `chunk_y`, `index` do `Chunk.buildings`), které
  trojúhelníky modelu při pohledu shora zakrývají aspoň z `models.replace_share` (vzorky po ≤ 1 m),
  a vždy všechny budovy samotné památky (`Building.landmark`).
- `roof_plan[]` = `PlanPoly`: prstence jako `Building` (`points` dm absolutně, `ring_ends`, vnější
  CCW, díry CW), `triangles`, `height_m` (nejvyšší bod střechy nad patou), `shade` 0–3,
  `base_z_dm` části.
- `tris` = součet trojúhelníků.
`Manifest.models_version` = 1; 0 nebo chybějící soubor = žádné modely.

## Pravidla
**Pata.** Terén je převýšený (`Manifest.exaggeration`), zdroj ne. Pipeline proto zvedne každý
vrchol části o (`exaggeration` − 1) × výšku roviny proložené zemí zdroje nad patou: reliéf pod
částí je převýšený jako terén, výšky nad zemí zůstávají skutečné. `base_z_dm` = nejmenší
(terén − pata) přes vrcholy země, takže žádný vrchol země nevisí. Bez terénu `base_z_dm` = 0.

**Výška vrcholu (oba klienti):** `z = base_z + displayHeight(extrusionScale(z_v))` jako u střech
budov (`specs/terrain.md` „Jednotná zobrazená výška“).

**Role a barvy.** `wall` = barva `landmark` palety města; ostatní `color.model.<day|night>.<role>`
(`roof`, `copper`, `stone`, `glass`, `gold`), přepis `color.city.<id>.model<Role>` (jen den).
Světlo po trojúhelnících jako u budov: svislá plocha `ambient + (1 − ambient) × max(0, n · slunce)`,
vodorovná `roofLight`, mezi nimi podle sklonu (váha |n_z|). Pipeline: střecha `roof`, stěna `wall`,
střecha části „vyznacna vez na strese“ (IPR) `copper`, přepis `models.yaml` `roles` podle id budovy
nebo části zdroje.

**Šikmý pohled (W).** Model se kreslí, když je auto blíž než `models.near_m` k nejbližšímu bodu
střešního plánu; zpátky na půdorysy až za `near_m + hysteresis_m` (bez probliknutí). Naráz nejvýš
`models.max_full` modelů, vyhrají nejbližší. Při kresleném modelu se budovy z `replaces` nekreslí
(kolize zůstávají) a nevrhají stín; stín vrhají polygony střešního plánu jako hranoly do `height_m`
(stejný postup jako budovy, `specs/style.md` „Vržené stíny“). Síť se staví, když je načtený chunk
s kotvou první části, a uvolní se s ním. Model se nezprůhledňuje (`occluderFade` jen budovy).

**Pohled shora (W; F po bráně L).** Místo budov z `replaces` se kreslí střešní plán: každý polygon
jako hranol od `base_z` do zobrazené výšky `height_m`, střecha v barvě `roof` × odstín
`0,7 + 0,1 × shade`, stěny `landmark`. Pořadí podle `height_m` (2D klient).

**Odstín** (`shade`): normála střechy `n` proti pevnému světlu (azimut 315°, výška 45°),
`d = n · l`: `d < 0,25` → 0, `< 0,55` → 1, `< 0,85` → 2, jinak 3.

## Pipeline (`citypack models`, po `landmarks`, `pack` doplní `replaces`)
1. Výběr: budovy zdroje, jejichž těžiště země leží v `select.area` (lon, lat) nebo v půdorysu
   budovy památky / do `select.buffer_m` od něj; `include`, `exclude` podle `gml:id`.
2. Čtení CityGML (Building, BuildingPart, BuildingInstallation; Roof/Wall/GroundSurface; LOD2 i
   LOD3; solidy jsou odkazy a přeskočí se). Souřadnice zdroje → místní metry kvadratickým
   polynomem proloženým PROJ (DuckDB `ST_Transform`) na mřížce 5 × 5 přes obálku souboru
   (reziduum nad 5 cm = chyba).
3. Čištění: bez podlah a plochy na úrovni paty, svaření na `weld_m`, bez kolineárních vrcholů,
   skupiny (část, instalace) menší než `min_detail_m` pryč.
4. Rozpočet: nad `max_tris` (`models.yaml` výjimka do `max_tris_exception`) zvedá `min_detail_m`
   po `detail_step_m` do `max_detail_m`, pak chyba s počtem navíc.
5. Střešní plán: střechy s normálou nahoru, sloučené po části a odstínu; slučují se jen polygony se
   společnou hranou (ta se zruší, T-spoje se rozdělí), překryvy v jiné výšce zůstanou zvlášť; zjednodušené na `plan_simplify_m`; přes `roof_plan_max_polys` hrubší
   odstíny (páry, pak jeden), pak největší polygony.
6. Výstup `models.pb`, náhled `preview/models/<id>.png` (plán shora, šikmo z jihozápadu).

**Validate:** rozpočty (památka, město, `city_max_bytes` po gzipu), `roof_plan_max_polys`, indexy a
role v rozsahu, žádný vrchol `foot` nad terénem víc než `foot_tolerance_m` (skutečné metry);
zahrabání (medián) nad toleranci je jen varování (hrubý DEM proti zemi zdroje), těžiště modelu do
`max_offset_m` od bodu památky, atribuce zdroje v manifestu, `replaces` ukazují na budovy.

## Hraniční případy
- Balíček bez `models.pb` nebo `models.enabled: false`: kreslí se půdorysy jako dosud.
- Chunk s budovou z `replaces` ještě není načtený: model se kreslí, skrytí doběhne s chunkem.
- Plochý balíček: `base_z_dm` = 0, pata bez převýšení.
- Teleport: přepnutí model ↔ půdorys proběhne v dalším snímku podle nové polohy.

## Scénář
Žádné vektory (P2). Ruční kontrola (`plans/verify.yaml`): u Hradu v šikmém pohledu je model,
1 km od něj půdorys, přepnutí bez probliknutí; shora střešní plán.

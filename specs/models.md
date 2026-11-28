# Modely památek

**version: 5** · P2 (vzhled), data v citypacku · plán `Prompts/06-METROPOLE_LANDMARKS3D_PLAN.md` ·
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
  na trojúhelník: materiál), `surfaces` (v2, bajt `ModelSurface` na trojúhelník: třída plochy
  CityGML `WallSurface` → `SURFACE_WALL`, `RoofSurface` → `SURFACE_ROOF`; `GroundSurface` se nekreslí
  a do sítě nejde), `foot` (vrcholy na zemi zdroje), `source_id`.
- `replaces[]` = budovy balíčku (`chunk_x`, `chunk_y`, `index` do `Chunk.buildings`), které
  trojúhelníky modelu při pohledu shora zakrývají aspoň z `models.replace_share` (vzorky po ≤ 1 m),
  a vždy všechny budovy samotné památky (`Building.landmark`).
- `roof_plan[]` = `PlanPoly`: prstence jako `Building` (`points` dm absolutně, `ring_ends`, vnější
  CCW, díry CW), `triangles`, `height_m` (nejvyšší bod střechy nad patou), `shade` 0–3,
  `base_z_dm` části.
- `tris` = součet trojúhelníků.
`Manifest.models_version` = 2 (v1 bez `surfaces` a bez role `slate`); 0 nebo chybějící soubor =
žádné modely. Klient v1 čte balíček v2 dál (nové pole ignoruje, neznámou roli kreslí jako stěnu).
V3 formát nemění (`models_version` zůstává 2): mění pipeline (mosty, převod souřadnic, `towers`,
pořadí částí) a validate. V4 také ne (`models_version` 2): přidává jen `parts` v `models.yaml`.
V5 také ne (`models_version` 2): zdroj PLATEAU (Tokio), výběr LOD, `max_offset_m` a výběr jen
podle `include` (viz „Pipeline“). Části jsou seřazené podle vzdálenosti kotvy od bodu památky (první je
nejblíž; klient staví sítě s chunkem první části). Část mostu má `source_id` = `bridge:<ID_BUD>`.

## Pravidla
**Pata.** Terén je převýšený (`Manifest.exaggeration`), zdroj ne. Pipeline proto zvedne každý
vrchol části o (`exaggeration` − 1) × výšku roviny proložené zemí zdroje nad patou: reliéf pod
částí je převýšený jako terén, výšky nad zemí zůstávají skutečné. `base_z_dm` = medián
(terén − pata) přes vrcholy země zdroje; vrcholy `foot`, pod kterými je terén níž, se pak sníží
až na terén (z může být záporné), takže žádná stěna nevisí a do svahu se zahrabe jen horní strana.
Bez terénu `base_z_dm` = 0 a pata zůstane rovná.
V4: plocha `GroundSurface`, jejíž nejnižší bod je víc než `models.ground_float_m` nad nejnižší zemí
budovy, je podhled (kabiny Žižkovské věže 70–130 m nad zemí), ne pata: nedává kotvu, rovinu země
ani vrcholy `foot`. Dřív věž stála 58 m pod terénem.

**Výška vrcholu (oba klienti):** `z = base_z + displayHeight(extrusionScale(z_v))` jako u střech
budov, pro `z_v ≤ 0` přímo `base_z + z_v` (`specs/terrain.md` „Jednotná zobrazená výška“).

**Role a barvy (v2).** Každá role má barvu `color.model.<day|night>.<role>` (`wall` omítka,
`roof` taška, `copper` měděná patina, `stone` tmavý pískovec, `glass`, `gold`, `slate` břidlice
nebo olovo), přepis `color.city.<id>.model<Role>` (jen den). V5 první přepisy: Tokio `modelWall`
cihla (nádraží), `modelCopper` rumělka (Sensō-ji), `modelGold` mezinárodní oranžová (Tokijská věž),
`modelGlass` bílá ocel (Skytree); `roof` se nepřepisuje (barva střešního plánu obou klientů). V4: `wall` teplá světlá omítka
(#EBD6B0) a `copper` sytější patina (#5FA083), aby omítka nebyla bílá a kopule z ní vystoupila. V1 kreslila `wall` barvou `landmark`
palety města, celý model pak byl zelený.
Světlo po trojúhelnících jako u budov: svislá plocha `ambient + (1 − ambient) × max(0, n · slunce)`,
vodorovná `roofLight`, mezi nimi podle sklonu (váha |n_z|).

**Role v pipeline (v2), po pořadí, pozdější vyhrává.** Stěna (`WallSurface`): `wall` → `models.yaml`
`walls` podle id budovy zdroje → `walls` podle id části. Střecha (`RoofSurface`): `roof` →
`roles` podle id budovy → `copper`, je-li část věž („vyznacna vez na strese“, IPR) nebo štíhlá
a vysoká, a místo mědi `towers` podle id budovy (v3: břidlicové špice Týna, mostecké věže; části
IPR nemají `gml:id`) → `roles` podle id části (jen id různé od budovy) → v4 `parts`. Štíhlá a vysoká část: ne instalace
(`BuildingInstallation`), vrchol aspoň `models.copper_min_top_m` nad patou budovy a delší strana
obálky půdorysu části nejvýš `models.copper_slender` × výška části (vrchol − nejnižší bod části).
Stěny věží zůstávají stěnami své budovy (kámen katedrály), měď dostanou jen střechy a špice.

**Části bez id (v4).** Části IPR nemají `gml:id`, proto `models.yaml` `parts: [{at: [lon, lat],
walls: <role>, roof: <role>}]`: položka vybere skupinu (budova nebo část, ne instalace) s nejmenší
obálkou půdorysu, která bod obsahuje, a její stěny dostanou `walls`, střechy `roof` (prázdné =
beze změny); vyhrává nad vším výše. IPR odvozuje stěny od okapů a často je vede pod celou budovou,
proto přepis platí i pro plochy jiných skupin (ne instalací), které celé leží v obálce vybrané
skupiny rozšířené o `models.part_box_slack_m`. Bod mimo všechny skupiny = varování. Použití: Prašná brána jako část
Obecního domu (kámen, břidlice), věž Staroměstské radnice, kopule Národního muzea (měď; na
pravidlo štíhlosti je široká).

**Fasáda (W, v2).** Bez fotografií, procedurálně v enginu (dynamická textura, kreslí se násobením
barvy vrcholu, bílá = beze změny, barvy `color.modelFacade.<day|night>`):
- Stěny `stone`: pole `models.facade_bay_m` široké, `models.facade_storey_m` vysoké; na levém
  okraji pole opěrák (`buttress`), uprostřed lomené (gotické) okno (`window`, kružba `tracery`,
  v noci část oken `lit`), dole římsa (`course`). Souřadnice: u = (x, y) · t / bay, t vodorovná
  tečna stěny (−n_y, n_x)/|n_xy|, v = (z − base_z) / storey (zobrazená výška).
- Stěny ostatních rolí: okenní textura budov (`specs/style.md`), u = (x, y) · t, v = z − base_z
  v metrech jako zdi budov.
- Střechy (každá role): svislé pruhy po spádnici (plechové nebo tašková drážka, `seam`) po
  `models.roof_seam_m`; u = (x, y) · t / (4 × roof_seam_m), pro vodorovnou střechu u = x / (4 ×
  roof_seam_m).
Tři sítě na model (okenní stěny, kamenné stěny, střechy), všechny s materiálem budov (průhlednost
před autem, hloubkový průchod risografu, tunel). Rozpočet: čas snímku p99 v šikmém pohledu na Hrad
nejvýš +10 % proti pohledu bez modelu.

**Šikmý pohled (W).** Model se kreslí, když je auto blíž než `models.near_m` k nejbližšímu bodu
střešního plánu; zpátky na půdorysy až za `near_m + hysteresis_m` (bez probliknutí). Naráz nejvýš
`models.max_full` modelů, vyhrají nejbližší. Při kresleném modelu se budovy z `replaces` nekreslí
(kolize zůstávají) a nevrhají stín; stín vrhají polygony střešního plánu jako hranoly do `height_m`
(stejný postup jako budovy, `specs/style.md` „Vržené stíny“). Síť se staví, když je načtený chunk
s kotvou první části, a uvolní se s ním. Model má materiál budov: zprůhledňuje se mezi kamerou a
autem a jde do hloubkového průchodu risografu jako ony.

**Pohled shora (W; F po bráně L).** Místo budov z `replaces` se kreslí střešní plán: každý polygon
jako hranol od `base_z` do zobrazené výšky `height_m`, střecha v barvě `roof` × odstín
`0,7 + 0,1 × shade`, stěny `landmark` (beze změny ve v2). Pořadí podle `height_m` (2D klient).

**Odstín** (`shade`): normála střechy `n` proti pevnému světlu (azimut 315°, výška 45°),
`d = n · l`: `d < 0,25` → 0, `< 0,55` → 1, `< 0,85` → 2, jinak 3.

## Pipeline (`citypack models`, po `landmarks`, `pack` doplní `replaces`)
1. Výběr: budovy zdroje, jejichž těžiště země leží v `select.area` (lon, lat) nebo v půdorysu
   budovy památky / do `select.buffer_m` od něj; `include`, `exclude` podle `gml:id`. V5: památka
   bez budovy a bez `select.area` (náměstí, Kaminarimon) smí vybírat jen přes `include`; zdroj se
   čte do `max_offset_m` od bodu památky.
2. Čtení CityGML (Building, BuildingPart, BuildingInstallation; Roof/Wall/GroundSurface; LOD2 i
   LOD3; solidy jsou odkazy a přeskočí se). Souřadnice zdroje → místní metry kvadratickým
   polynomem proloženým PROJ (DuckDB `ST_Transform`) na mřížce 5 × 5 přes obálku souboru
   (reziduum nad 5 cm = chyba). V3: zdroj → EPSG:4326 a pak projekce balíčku (`origin`) jako
   u Overture. V2 převáděla přímo do sférické projekce města: PROJ bez datumu vynechal posun
   S-JTSK → WGS84 a modely Prahy ležely ~117 m na severovýchod (Hrad v balíčku do v3).
   V5 PLATEAU (`source: plateau`): EPSG:6697, JGD2011 zeměpisná **šířka, délka** (v tomto pořadí)
   a výška T.P.; JGD2011 ≈ WGS84 (centimetry), vrcholy se promítají přímo projekcí balíčku, bez
   PROJ a polynomu. Budova nese plochy ve více LOD (PLATEAU: LOD2 všude, LOD3 u několika): zdroj
   určuje jednu (`plateau` LOD2, není-li, nejvyšší; IPR beze změny všechny, má jen LOD3).
   `OuterCeilingSurface` (podhledy střech a bran) se čte jako střecha (`SURFACE_ROOF`; míří dolů,
   do střešního plánu nejde).
3. Čištění: bez podlah a plochy na úrovni paty, svaření na `weld_m`, bez kolineárních vrcholů,
   skupiny (část, instalace) menší než `min_detail_m` pryč.
4. Rozpočet: nad `max_tris` (`models.yaml` výjimka do `max_tris_exception`) zvedá `min_detail_m`
   po `detail_step_m` do `max_detail_m`, pak chyba s počtem navíc.
5. Střešní plán: střechy s normálou nahoru, sloučené po části a odstínu; slučují se jen polygony se
   společnou hranou (ta se zruší, T-spoje se rozdělí), překryvy v jiné výšce zůstanou zvlášť; zjednodušené na `plan_simplify_m`; přes `roof_plan_max_polys` hrubší
   odstíny (páry, pak jeden), pak největší polygony.
6. Výstup `models.pb`, náhled `preview/models/<id>.png` (plán shora, šikmo z jihozápadu).

## Mosty (v3)
Most je dopravní stavba, ale model je jen obraz: graf, zóny, kolize a hladina se nemění (Karlův
most zůstává pěší zónou, auto na něj nesmí). Zdroj IPR „Mosty 3D“ (`mosty_shp`, polygonZ v
S-JTSK, jeden řádek na plochu, `ID_BUD` na most; CC BY 4.0 jako 3D model budov, stejná
atribuce), `models.yaml` `bridges: {file, ids}` u památky; věže mostu jsou budovy CityGML
(`include`). Pipeline:
- Plochy bez spolehlivé orientace: vodorovné (|n_z| > 0,9) otočené nahoru a jednou, ostatní
  z obou stran (dva trojúhelníky). Plochy menší než `min_detail_m` ve všech rozměrech pryč.
- Výšky skutečné, bez zobrazovací škály: z = 0 je vrchol mostu, vše ostatní z < 0. Mostovka na
  každém konci (vodorovné plochy do `models.bridge_end_m` od konce podél hlavní osy, nejvýš 2 m
  pod nejvyšší z nich) sedí v mediánu na terénu; mezi konci se posun mění lineárně (smyk, protože
  převýšené břehy se liší). `base_z` = vyšší konec.
- Všechny plochy mostu mají `SURFACE_ROOF` (textura spár, ne okna) a role `walls` / `roles` podle
  `bridge:<ID_BUD>`. Střešní plán z vodorovných ploch.
- `pack`: trojúhelník mostu, pod kterým je vzorek silnice (osa a oba okraje po 1 m, každá hrana
  grafu mimo tunely) v rozsahu od `models.bridge_below_m` pod povrchem silnice do
  `models.bridge_clear_m` nad ním, se zahodí: silnice vyhraje (konec mostovky na ulici, pata
  oblouku nad úzkou uličkou).

**Validate:** rozpočty (památka, město, `city_max_bytes` po gzipu), `roof_plan_max_polys`, indexy a
role v rozsahu, žádný vrchol `foot` nad terénem víc než `foot_tolerance_m` (skutečné metry);
zahrabání (medián) nad toleranci je jen varování, těžiště modelu do
`max_offset_m` od bodu památky (v3: model s mostem nejbližší kotvou části, most je delší; v5
`models.yaml` `max_offset_m` u památky, nejvýš `near_m`: chrámový areál podél osy, Sensō-ji od
brány k hlavní síni 400 m),
atribuce zdroje v manifestu, `replaces` ukazují na budovy. V3: žádný trojúhelník mostu nad
silnicí v rozsahu `bridge_below_m` … `bridge_clear_m` (zakrytí, boj o hloubku).

## Hraniční případy
- Balíček bez `models.pb` nebo `models.enabled: false`: kreslí se půdorysy jako dosud.
- Chunk s budovou z `replaces` ještě není načtený: model se kreslí, skrytí doběhne s chunkem.
- Plochý balíček: `base_z_dm` = 0, pata bez převýšení.
- Teleport: přepnutí model ↔ půdorys proběhne v dalším snímku podle nové polohy.

## Scénář
Žádné vektory (P2, vzhled bez pravidel; vektory `vectors/` jsou jen P0). Pravidla rolí a
štíhlosti hlídají tabulkové testy `tools/citypack` (`TestSurfaceRole`, v3 `TestSurfaceRoleTowers`,
mosty `TestBuildBridgePart`, `TestClipBridgeRoads`, v4 `TestBuildPartPartRoles`, `TestBuildPartFloatingGround`), UV a barvy testy W
(`web/test/models.test.ts`). V5: čtečka `TestReadLOD` (výběr LOD, podhled jako střecha). Ruční kontrola (`plans/verify.yaml`): u Hradu v šikmém pohledu je model,
1 km od něj půdorys, přepnutí bez probliknutí; shora střešní plán.

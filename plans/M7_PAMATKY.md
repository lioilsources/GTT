# M7 – Památky ve 3D (pod-plán)

Plán: `Prompts/06-METROPOLE_LANDMARKS3D_PLAN.md`. Spec: `specs/models.md` v1. Parita F-085.
Rozsah tohoto kola: jen `prague_castle` (areál Hradu s katedrálou sv. Víta, K4), fáze H0 → H2 ve W.
Defaulty kap. 11: bez textur (K2), F až po vystřelení (K3, K6).

## H0 – ověření dat (Praha, 2026-11-27)

| OVĚŘ | Zjištění |
|---|---|
| Kde se stahuje | ArcGIS Online, uživatel `opendatapraha` (portál opendata.geoportalpraha.cz). Každý mapový list 1 : 5000 má položku `BD3_Prah_<list>` typu GML (CityGML), vedle ní `_shp`, `_mp` (multipatch), `_dwg`, `_dgn`. Bez přihlášení, bez captchy: `https://www.arcgis.com/sharing/rest/content/items/<id>/data`. |
| Licence | CC BY 4.0, „data base © IPR Praha“ (stránka otevřených dat geoportalpraha.cz, `licenseInfo: CC BY` u položek). **Lze.** |
| List s Hradem | **Praha 7-1** (číslo 57-1; klad `MAP_CUR_MAP_ML_5000_P`), S-JTSK x −745 006 … −742 506, y −1 044 008 … −1 042 008. Celý areál včetně Pohořelce a Hradčanského náměstí leží v tomto jednom listu. Položka `88dc83fcd48c4ac9aec3532c19395d72`, upravená 2023-11-20. |
| Velikost | `BD3_Prah_7-1.gml` 172 481 904 B (172 MB, nekomprimované XML ISO-8859-1), sha256 `5d356c0a…dd04d50`. V `run/citypack/prague/raw/models/`, ne v gitu. |
| Souřadnice | S-JTSK / Křovák East North (EPSG:5514; v souboru `srsName="unknown"`), x, y záporné. Výšky Bpv (184–380 m v listu). WGS84 verze ke stažení není. Převod: polynom 2. stupně proložený PROJ (DuckDB `ST_Transform(..., 'EPSG:5514', <místní eqc>)`) na mřížce 5 × 5 přes obálku listu, reziduum 1 mm (afinní převod by měl 0,28 m). |
| Formát | Export CityGRID Manager 16. Plochy pod `lod3MultiSurface` (podrobné střechy), `lod3Solid` jsou jen odkazy xlink na tytéž polygony. List: 3 266 budov, 5 347 částí (`BuildingPart`), 3 220 instalací (`BuildingInstallation`: komíny, vikýře), 46 115 střešních, 77 128 stěnových a 8 092 základových ploch. `bldg:usage` na části: „sikma stresni plocha“, „vodorovna stresni plocha“, „vyznacna vez na strese“ (231×). |
| Jak je Hrad a katedrála | Katedrála je jedna budova `_70215` (pata 256,4–257,3 m Bpv, nejvyšší bod 90,3 m nad patou), věže a fiály jako části „vyznacna vez na strese“, střechy podrobně, stěny svisle od terénu. Areál Hradu = desítky samostatných budov (palác `_70087` s 1 498 trojúhelníky, západní křídlo `_70263`, Zlatá ulička, Černá věž …), každá s vlastní patou ve svahu. |
| Trojúhelníky Hradu | Výběr `content/cities/prague/models.yaml` (oblast areálu + budova památky + 2 m): 48 budov zdroje. Surově 6 702 trojúhelníků, po čištění (svaření 0,1 m, bez podlah, bez skupin pod 1,5 m) **6 231** – pod výjimkou 12 000 z kap. 8, nad výchozími 4 000 (proto `max_tris: 12000` v `models.yaml`). |
| `models.pb` Prahy | 56,8 kB po gzipu (limit 1,5 MB). Střešní plán 296 polygonů (limit 400), `replaces` 28 budov Overture. |
| Pata vs terén | Terén Prahy je zatím AWS Terrain Tiles (EU-DEM ~25 m, povrchový model) se silnicemi zarovnanými `conform`. Proti zemi zdroje (laser IPR) se na hraně hradního ostrohu rozchází o metry: pod katedrálou zdroj 256,4–257,3 m, DEM 248–253 m, na Hradčanském náměstí naopak výš. První verze stavěla patu na nejnižší terén pod půdorysem (jako budovy): 12 z 48 částí bylo zahrabaných víc než 2 m (nejvíc 10,1 m) a katedrála ve hře „seděla v jámě“. Teď pata = medián (terén − země zdroje) a spodní vrcholy stěn sjedou po terénu dolů: žádná stěna nevisí, `validate` bez varování. Přesnost zlepší DMR 5G (M5-S4). |
| Karlův most | Mimo rozsah tohoto kola (mosty jsou v IPR samostatná sada „Mosty 3D“ za celou Prahu). |

Licence ostatních měst (kap. 4.1): v tomto kole neověřováno – New York **nejasné**, Tokio (PLATEAU,
PDL 1.0) **lze podle plánu, neověřeno v datech**, Moskva **nelze** (úřední model není, záloha Overture).
Doloží H0 pro H5/H6. Tokio ověřené v H5 (níže): **lze**.

## H1 – pilot v datech

Krok `citypack models` (`tools/citypack/internal/steps/models.go`, čtečka `internal/citygml`),
`models.pb` v balíčku (`Manifest.models_version` 1, atribuce IPR), `validate` (rozpočty, indexy,
pata, vzdálenost od bodu památky, atribuce, `replaces`), náhled
`run/citypack/prague/preview/models/prague_castle.png` (plán shora a šikmo z jihozápadu).
Balíček bez `models.pb` dál funguje (klienti ho berou jako volitelný).

## H2 – šikmý pohled ve W

W PR #325 (`web/src/world/models.ts`, `web/src/render/modelGeometry.ts`, `worldView`), viz
`specs/models.md`: model do `near_m` 600 m s hysterezí 50 m, `replaces` (57 budov Overture včetně
~40 částí katedrály) ve vlastních sítích, stíny z hranolů střešního plánu, plán shora.

Čas snímku (headless Chromium se SwiftShaderem, tedy CPU – jen poměr): Hradčanské náměstí, šikmý
pohled, p50 77 ms s modelem proti 70,7 ms bez (+9 %, limit +10 %), +10,7 tis. trojúhelníků
(model 6,2 tis. + stíny plánu, minus skryté budovy), +2 draw cally. Na telefonech měří Ol1n
(`plans/verify.yaml` M7-H2). Scéna `prague-landmarks` v `bench` zatím není: `web/test/pragueHills.test.ts`
pevně hlídá seznam pražských tras, přidá se se změnou testu ve W.

## H2b – materiály a fasáda (specs/models.md v2)

Podnět Ol1n: „katedrále chybí správná textura“ – v1 kreslila všechny stěny barvou `landmark` (zelená).
Pipeline už čte `WallSurface` / `RoofSurface` (`GroundSurface` jen pro patu) a teď třídu ukládá do
`ModelPart.surfaces`; role: omítka `wall`, katedrála `_70215` kámen `stone` a břidlice `slate`
(`models.yaml` `walls` / `roles`), měď na věžích IPR a na štíhlých vysokých částech
(`models.copper_min_top_m` 30 m, `copper_slender` 0,4: v areálu jen věže katedrály a dvě ploché
střechy hlavní věže). Barvy `color.model.*`, `color.modelFacade.*`. W: procedurální fasáda (lomená
okna a opěráky na kameni, okenní textura budov na omítce, pruhy po spádnici na střechách), tři sítě
na model. Fotorealistický mesh IPR (CC BY, OBJ + JPG po listech, list Hradu 1,25 GB) zatím ne:
objem, souvislá síť bez budov a značky na fotkách (R10).

## H1b – pilotní pětice (specs/models.md v3, brána K1 schválena)

Ol1n schválil K1 nad snímky Hradu: pokračuje se zbytkem pilotu (kap. 11 K4). Staroměstská radnice
v pilotu není (K4: Hrad, Karlův most s věží, Týn, sv. Mikuláš, Národní divadlo), přijde s H4.

**Data.** Všechny čtyři nové památky leží ve stejném listu **Praha 7-1** jako Hrad, jiné listy
CityGML nejsou potřeba. Karlův most v 3D modelu budov není: IPR ho vede v sadě „Mosty 3D“
(`mosty_shp`, ArcGIS položka `622e66a29f3d459a8dbc57939954db8c`, 1,7 MB zip, polygonZ v S-JTSK,
21 406 ploch za celou Prahu, `ID_BUD`; Karlův most = `1000484`, 854 ploch, 466 m). Stažené do
`run/citypack/prague/raw/models/mosty_shp/`, ne do gitu. CityGRID nedává plochám mostu orientaci
ani třídu (střecha/stěna), proto v3 kreslí svislé plochy mostu z obou stran.

| Památka | Zdroj | Materiály | Trojúhelníky |
|---|---|---|---|
| `tyn_church` | `_79878` | kámen, břidlicová střecha i špice (`towers`, IPR je značí jako věže → jinak měď) | 584 |
| `st_nicholas` | `_76469` kostel, `_77005` zvonice | omítka, měděná kopule a střechy | 368 |
| `national_theatre` | `_89947` | omítka, tmavá střecha `slate` (modrozlatá by chtěla novou roli; barva `color.model.*.slate` stačí) | 419 |
| `bridge_tower` | most `bridge:1000484` + věže `_81184`, `_78361`, `_78667` | kámen, břidlicové střechy věží; most textura spár (`SURFACE_ROOF`) | 4 239 (most 3 767 po ořezu) |
| `prague_castle` | beze změny výběru | – | 6 106 (85 budov, viz níže) |

Celkem **11 716 trojúhelníků** (limit města 120 000), `models.pb` **85,8 kB** po gzipu (limit 1,5 MB).
**Výjimka:** `bridge_tower` `max_tris: 6000` (výchozí 4 000): svislé plochy mostu jsou dvakrát
(neorientované prstence), most sám ~3 800, tři věže ~500. Pod stropem výjimek 12 000.

**Oprava souřadnic (v3).** Převod S-JTSK šel přímo do sférické projekce města; PROJ k ní nemá
datum a vzal „ballpark“ převod bez posunu S-JTSK → WGS84. Všechny modely tak ležely **~117 m na
severovýchod** (Týn: model v (199, 120) místo (121, 33)), včetně publikovaného Hradu (v2 vybíral
48 budov z posunuté oblasti, teď 85 budov skutečného areálu, 6 106 trojúhelníků, `replaces` 96).
V3 převádí přes EPSG:4326 a projekci balíčku jako Overture; věž mostu sedí na bodu památky
(< 4 m), Mikuláš < 1 m.

**Most v balíčku.** Karlův most je ve hře pěší zóna nad vodou (sloupky zóny, žádná hrana grafu,
auto na něm „potopí“ a odtáhne se) a tak zůstává: model je jen obraz, kolize ani graf se nemění.
Výška: skutečná, bez zobrazovací škály; mostovka na obou koncích na terénu (medián v pásu
`bridge_end_m` 15 m). Převýšené břehy se liší o 23,5 m (Malá Strana 39,2 m, Staré Město 15,7 m
herní výšky), proto lineární smyk mezi konci (~5 % podél mostu). Pod mostem jsou na Kampě
uličky Na Kampě / U Lužického semináře a Saská u Malostranských věží: `pack` zahodí 46
trojúhelníků mostu, které by v pásu −0,3 … +4,5 m nad silnicí zakryly cestu nebo bojovaly
o hloubku; `validate` to pak hlídá (0 vzorků). Model se vybírá od nejbližší části k bodu
památky (staroměstská věž), takže síť mostu vzniká s chunkem věže.

**Nasazení a čas snímku** (PR #332, balíček `f51c0132458b`, nasazený web, headless Chromium se
SwiftShaderem, tedy CPU – jen poměr; dvě kola model zapnutý / vypnutý `tuning.models.enabled`,
po 9 s):

| Místo | model zapnutý p50 / p90 | vypnutý p50 / p90 | trojúhelníky scény |
|---|---|---|---|
| Hrad s mostem (Mostecká u Malostranského náměstí, Hrad + most + Mikuláš) | 80,8 / 88,9 a 83,5 / 88,7 ms | 80,8 / 91,3 a 85,4 / 98,8 ms | +5,5–8 tis., +4–6 draw callů |
| Staroměstské náměstí (Týn, most) | 87,9 / 100 a 88,0 / 96,2 ms | 87,9 / 99,3 a 89,2 / 97,8 ms | +0,8–0,9 tis., +1–2 draw cally |

Rozdíl je v šumu (SwiftShader drží snímek u stropu 100 ms, p99 je saturované). Na telefonech
měří Ol1n (`plans/verify.yaml` M7-H1b).

## H2c – fotografická textura (zkouška, odložená)

**Rozhodnutí Ol1na 2026-11-28:** zůstává kreslená procedurální fasáda (H2b); fotografická textura
z IPR „Fotorealistický 3D model“ (CC BY 4.0) je odložená.

- **Zkouška:** bake fotografií na LOD2 katedrály sv. Víta, textura 1024² a 2048²; balíček +0,3–1 MB,
  paměť GPU 5,6–22 MB, čas snímku v šumu.
- **Proč odloženo:** tmavé a zrnité, jiné slunce než ve hře, nesedí stylem města, věže bez mědi,
  v noci bez oken.
- **Kód:** větve `web/photo-texture-trial` a `shared/photo-texture-bake`, bez PR.
- **Případné zavedení:** jen hero památky, 1024² v KTX2, auto-expozice a míchání s barvou role,
  krok `citypack models-photo` s vlastní specifikací.

## H1c – oprava sv. Mikuláše (specs/models.md v4, 2026-11-28)

Podnět Ol1n: „Chrám svatého Mikuláše je mimo, je to budova celá v bílé.“ **Ověřeno:** výběr je
správný (kostel `_76469` a zvonice `_77005`, jezuitská kolej `_75652` a sousední domy ve výběru
nejsou), model sedí na bodu památky (kotva < 1 m, střešní plán proti půdorysům Overture posun 3,5 m,
tj. v šumu kreslení Overture). **Příčina:** materiály. `roles: {_76469: copper}` dávalo měď všem
střechám, takže střecha lodi i kopule byly jedna světle zelená plocha a světlá stěna `#E8E0CE`
s okenní texturou ve hře vypadala bíle; z Mostecké (pozice snímků H1b) je navíc kopule nad horním
okrajem obrazu a vidět je jen loď. **Oprava:** střecha lodi `slate` (tmavá), kopule (věž IPR)
a zvonice dál měď z pravidla věží, `color.model.day.wall` teplá světlá omítka `#EBD6B0`,
`color.model.day.copper` sytější patina `#5FA083` (platí pro všechny modely: paláce Hradu, Národní
divadlo jsou také omítka). Snímky před a po z Karmelitské (−1217, −201), odkud je kopule vidět.

## H4 – druhá dávka (specs/models.md v4, 2026-11-28)

Plán 06 další pořadí neuvádí (H4: „ostatní hero památky“), dávka = nejviditelnější hero památky.
**Data:** listy IPR **6-1** (Obecní dům), **6-2** (Národní muzeum, Žižkovská věž) a **7-2** (Tančící
dům, Vyšehrad) vedle 7-1 (radnice, Rudolfinum, Petřín), `docs/citypack.md`. Rozhledna i vysílač
**jsou** ve 3D modelu budov (žádná jiná sada ani ruční popis): rozhledna jako plný osmiboký
komolý jehlan (mřížku zdroj nemá), věž jako tři tubusy s kabinami.

| Památka | Zdroj | Materiály | Trojúhelníky |
|---|---|---|---|
| `old_town_hall` | `_80697` (7-1) | domy omítka, taškové střechy; věž kámen, tmavá střecha a vížky (`parts`, `towers`) | 466 |
| `municipal_house` | `_80330` (6-1), **včetně Prašné brány** | omítka, tmavé střechy, měděné kopulky; brána kámen, břidlice, 4 vížky (`parts`) | 1 750 |
| `rudolfinum` | `_74123` (7-1) | světlý pískovec (omítka), tmavá střecha | 417 |
| `national_museum` | `_95801` (6-2) | světlé zdi, tmavé střechy a nárožní kopulky, měděná hlavní kopule a lucerna (`parts`) | 1 248 |
| `dancing_house` | `_100345` (7-2) | světlé zdi, kovová střecha (`slate`); jen architektura (R10) | 441 |
| `zizkov_tower` | `_95923` (6-2) | kovově šedé tubusy (role `glass`), tmavé střechy kabin | 836 |
| `petrin_tower` | `_82876` (7-1) | rezavě hnědá (role `roof` na stěnách), tmavý vrchol | 166 |
| `vysehrad` | `_121789` (7-2) | kámen, tmavá střecha, tmavé věže (`towers`) | 190 |

Celkem s pilotem **13 modelů, 17 230 trojúhelníků** (limit města 120 000), `models.pb`
**134,2 kB** po gzipu (limit 1,5 MB). Žádná nová výjimka z `max_tris` (výjimky dál jen Hrad 12 000
a Karlův most 6 000, zdůvodněné výše).

**Prašná brána a Obecní dům** jsou ve zdroji jedna budova `_80330` (brána je její `BuildingPart`
„vyznacna vez na strese“), výběr jde po budovách. Model nese id `municipal_house`; `powder_tower`
vlastní model nemá, je jeho součástí. Bod `powder_tower` v `landmarks.yaml` ležel 19 m západně
od brány a `buildings` mu přiřadil sousední blok v Celetné (72 × 55 m), který pak stál jako 65m
zelená věž; bod je teď na bráně (50,08724, 14,42776 podle IPR, souhlasí s částmi Overture brány).

**Nové v pipeline (v4, formát beze změny):** `models.yaml` `parts` přepíše role jedné části budovy
podle bodu (části IPR nemají `gml:id`; stěny vede IPR často pod celou budovou, proto i plochy jiných
skupin v obálce části); podhledy `GroundSurface` výš než `ground_float_m` (20 m) nad nejnižší zemí
nejsou pata – Žižkovská věž dřív stála 58 m pod terénem.

**Co ve zdroji chybí:** orloj (fasádní detail, LOD2 ho nemá), mřížka rozhledny, sochy a zábradlí
Rudolfina; Tančící dům je v Overture jen 6 × 5 m úlomek, model ho poprvé ukazuje celý.
Zbývající hero památky s budovou přidala třetí dávka (H4c níže); plochy Staroměstského
a Václavského náměstí model nepotřebují.

**Poloha** (posun střešního plánu proti půdorysům Overture s největším překryvem, rastr 0,5 m):
Rudolfinum 0,5 m, Vyšehrad 0,5 m, Národní muzeum 1,1 m, radnice 2,2 m, Žižkov 0,7 m, Obecní dům
0,5 m (Overture ho pokrývá jen z 22 %), rozhledna 4,2 m (malý půdorys, kraj rastru), Tančící dům
bez srovnání (Overture ho nemá; bod památky 11 m od těžiště, budova je správná: roh Rašínova
nábřeží a Resslovy, 24 × 33 m).

**Nasazení a čas snímku** (PR #334, balíček `8ddc88702eee`, nasazený web, headless Chromium se
SwiftShaderem, tedy CPU – jen poměr; dvě kola model zapnutý / vypnutý `tuning.models.enabled`,
po 9 s):

| Místo | model zapnutý p50 / p90 | vypnutý p50 / p90 | trojúhelníky scény |
|---|---|---|---|
| Celetná u Prašné brány (Obecní dům s bránou, radnice, Týn) | 72,1 / 84,9 a 76,7 / 87,3 ms | 70,7 / 76,4 a 72,4 / 99,2 ms | +1,4–2,7 tis., +1–2 draw cally |
| Staroměstské náměstí (radnice, Týn, Rudolfinum) | 100 / 100 ms (strop) | 100 / 100 ms (strop) | v šumu provozu (208–235 tis.) |

U Celetné p50 +2–6 %, p90 kolísá víc mezi koly vypnutého modelu než mezi stavy; na Staroměstském
náměstí drží SwiftShader snímek na stropu 100 ms v obou stavech. Na telefonech měří Ol1n
(`plans/verify.yaml` M7-H4).

## H4c – třetí dávka (specs/models.md v4, 2026-11-28)

Poslední hero památky s budovou. **Data:** listy, které už balíček čte (6-1 nádraží a Vítkov, 7-1
synagoga a Klementinum), formát ani spec beze změny, jen `models.yaml` a dva body v `landmarks.yaml`.

| Památka | Zdroj | Materiály | Trojúhelníky |
|---|---|---|---|
| `main_station` | `_88777` (6-1): historická Fantova budova – kupolová hala, dvě věže, křídla, koncové pavilony | světlá omítka, tmavé střechy, kupole a věže (`roles`, `towers` slate) | 906 |
| `old_new_synagogue` | `_75255` (7-1): samostatná síň se strmou sedlovou střechou a nízkými přístavky | tmavý kámen (`stone`), tmavá tašková střecha (`roof`) | 41 |
| `klementinum` | `_80023`, `_80104` (s Astronomickou věží), `_81330` (sv. Salvátor), `_81335` (sv. Kliment), `_81581` (Vlašská kaple) | omítka, taškové střechy, měděné střechy věží (pravidlo věží) | 1 748 |
| `vitkov` | `_82507` památník, `_82623` terasa jezdecké sochy před ním | světlý kámen: barva `wall` na zdech i plochých střechách (`roles`) | 337 |

Celkem **17 modelů, 20 262 trojúhelníků** (limit města 120 000), `models.pb` **162,7 kB** po
gzipu (limit 1,5 MB), Klementinum 231 polygonů střešního plánu (limit 400). Žádná nová výjimka
z `max_tris`.

**Co výběr nebere:** u nádraží nástupištní haly (`_88812`, `_89138`, ~1 300 ploch) a plochou
markýzu podél křídla (`_89197`, `exclude`); u synagogy dům v Pařížské (`_74917`, `exclude`),
Židovskou radnici a Vysokou synagogu; u Klementina domy přes Karlovu a dvě drobné stavby na
nádvoří pod 8 m; u Vítkova dva sloupky před terasou a nízký objekt severně. Socha Žižky ve zdroji
není (jen terasa s podstavcem).

**Body památek.** `buildings` přiřazuje památce nejbližší budovu Overture do 40 m a `replaces` ji
pak vždy skryje. Bod synagogy ležel v Pařížské (33 m od síně) a vybral sousední dům, bod Vítkova
20 m severně od památníku; oba jsou teď na budově (synagoga 50,09007 / 14,41859, Vítkov
50,08850 / 14,44994 podle IPR).

**Poloha** (posun střešního plánu proti vlastním půdorysům Overture, rastr 0,5 m, `lmpb/fit.py`
jen s budovami Overture krytými modelem z poloviny): Staronová synagoga 0 m (IoU 0,93),
Klementinum 0 m (IoU 0,78), Vítkov 0,7 m (Overture pokrývá jen půlku), Hlavní nádraží 2,1 m
(IoU 0,83 → 0,90).

**Snímky** před / po z nasazeného webu (šikmý pohled, auto stojí): nádraží z Vrchlického sadů
(790, −660), synagoga z Pařížské (−200, 370), Klementinum z Křižovnické u Mánesova mostu
(−425, 150), Vítkov z Husitské (2050, 10). Balíček `pack-prague-8a8b3c940ff0` (3,6 MB tar.gz).

## H5 – Tokio, první dávka z PLATEAU (specs/models.md v5, 2026-11-28)

**Zdroj a licence.** MLIT Project PLATEAU, 3D model měst Tokio 23 obvodů, data FY2025 (spec 5.0),
CityGML 2.0 + i-UR, soubory budov po 3. stupni sítě (1 km), stažené jen čtyři potřebné meshe
(110 + 60 + 143 + 166 MB) přes katalog `api.plateauview.mlit.go.jp/datacatalog/citygml/m:<mesh>`
do `run/citypack/tokyo/raw/models/` (`docs/citypack.md`). Licence **PDL 1.0** (podmínky webu
PLATEAU kap. 3), výslovně kompatibilní s **CC BY 4.0** (PDL §1.7.3); práva drží obvody. Atribuce
„出典：国土交通省 PLATEAUウェブサイト（https://www.mlit.go.jp/plateau/open-data/）“ a u upravených dat
„…を加工して作成“; v `NOTICE`, `docs/citypack.md`, v manifestu anglicky (hra nemá písmo CJK).
**Lze.**

**Souřadnice (v5).** EPSG:6697: JGD2011 **šířka, délka** a výška T.P. JGD2011 ≈ WGS84 (centimetry),
vrcholy se promítají rovnou projekcí balíčku jako Overture, bez PROJ (pražskou chybu 117 m tím nelze
zopakovat). Výška T.P. se bere jen relativně (pata = medián terén − země zdroje).
**Poloha** proti vlastním půdorysům Overture (rastr 0,5 m, `lmpb/fit_own.py`): Kaminarimon 0 m
(IoU 0,91), nádraží 0 m (IoU 0,88), Tokijská věž 0,7 m (Overture kreslí širší půdorys, IoU 0,50),
Skytree 3 m (Overture kryje jen čtvrtinu komplexu, IoU 0,23).

**Pipeline (v5, formát beze změny).** Čtečka bere jen LOD2 (PLATEAU má u každé budovy LOD0–2,
u několika i LOD3/4; IPR dál vše, má jen LOD3), `OuterCeilingSurface` (podhledy bran) jako střecha,
památka bez budovy (Kaminarimon je náměstí) vybírá jen přes `include`, `models.yaml` `max_offset_m`
(nejvýš `near_m`) pro areál podél osy.

| Památka | Zdroj PLATEAU | Materiály (Tokio, `color.city.tokyo.model*`) | Trojúhelníky |
|---|---|---|---|
| `tokyo_tower` | `bldg_7aff4a51…` (Minato 53393599) | celá v mezinárodní oranžové (`gold`) | 426 |
| `skytree` | `bldg_58ab8c46…` (Sumida 53394654) | bílá ocel (`glass`), tmavé střechy | 2 043 |
| `kaminarimon` | brána `bldg_aeed40a6…`, Hōzōmon `bldg_8760bd58…`, hlavní síň `bldg_89e579d5…`, pagoda `bldg_b9141e64…` (Taitō 53394653) | rumělkové zdi (`copper`), tmavé taškové střechy (`slate`) | 274 |
| `tokyo_station` | `bldg_6af58cef…` (Chiyoda 53394611): budova Marunouchi | cihla (`wall`), tmavé břidlicové střechy a kopule | 784 |

Celkem **4 modely, 3 527 trojúhelníků** (limit města 120 000), `models.pb` **29,1 kB** po gzipu
(limit 1,5 MB), žádná výjimka z `max_tris`. Balíček `pack-tokyo-e9d119a89a37` (8,1 MB tar.gz);
proti předchozímu `db6c28d4d458` se liší jen `models.pb` a manifest.

**Jak jsou modelované.** *Tokijská věž:* žádná příhradová konstrukce – čtyři nohy na zemi (33
ploch `GroundSurface`), nad nimi **plný uzavřený zužující se plášť** (ve 25–50 m 72 m široký,
v 75–150 m 38 m, horní plošina 15 m, anténa) s oběma vyhlídkovými plošinami; budova Foot Town
pod věží je součástí téže budovy PLATEAU. Pruhy oranžová/bílá nejdou (role na trojúhelník, ne
pruh), celá věž je oranžová. *Skytree:* PLATEAU vede věž s podnožím (nákupní křídla a East Tower,
397 × 136 m) jako **jednu budovu**; jsou stavebně spojené, model je nechává (bílá ocel, sklo).
*Sensō-ji:* LOD2 je hrubé – hlavní síň krabice s valbou (34 trojúhelníků), pagoda zužující se hranol
s jehlanovou střechou bez pater a špice (52 m), Hōzōmon a brána s podhledy. Model nese id
`kaminarimon` („Kaminarimon (Sensō-ji)“), brána je nejblíž bodu a jde první; nákupní ulice
Nakamise mezi nimi zůstává z Overture. *Nádraží:* jen budova Marunouchi (cihlová, 314 m),
nástupiště a strana Yaesu jsou jiné budovy PLATEAU; nástupištní střecha v půdorysu Overture
(`bldg_2b101e06…`) je v `exclude`. Kopule jsou v LOD2 osmiboké bubny s jehlanovou střechou.

**Co nejde.** *Národní sněmovna (`national_diet`):* budova v PLATEAU **není** (mesh 53394519 má
v okruhu 270 m od bodu jen strážní budky; vládní objekt vynechaný), soubor stažený, nepoužitý.
*Tokijská metropolitní vláda (Shinjuku), svatyně Meiji (Shibuya), Rainbow Bridge:* leží **mimo
oblast balíčku** (lon 139,725–139,815, lat 35,65–35,722), nejsou v `landmarks.yaml` a nové body
by neměly terén ani chunky; Rainbow Bridge je navíc silniční most (graf, vrstvy), model by byl jen
obraz nad vozovkou. Nové body památek nepřibyly.

**R10.** LOD2 nemá textury ani nápisy; barvy jsou jen role.

**Snímky** (šikmý pohled, auto stojí, `scratchpad/shots/tkshoot.sh`, `tkpair.sh`): kamera hry vysoké
věže nepobere, proto jednotně před i po `camera.chase` výška 10–60 m, vzdálenost 40–90 m, FOV
55–60°; Tokijská věž ze Sakurada-dōri (−2160, −2490; kamera 25 m), Skytree z Asakusa-dōri
(3692, 3061), Kaminarimon z Namiki-dōri (2625, 3255), nádraží z Gyōkō-dōri (−319, 58). Kaminarimon
a nádraží: „před“ z webu před vydáním, „po“ z nasazeného webu. Tokijská věž a Skytree: snímky před
vydáním měly jiný směr kamery (auto se po teleportu natáčí), proto pár z jedné stránky nasazeného
webu s modelem a pak s `tuning.models.enabled = false` – to je stav před vydáním (balíček se liší
jen `models.pb`). Před: červená krabice Overture (věž), lomená tyčová značka (Skytree), šedý blok
(brána), šedé bloky (nádraží); po: modely na místě, sousední domy beze změny.

**Nasazení a čas snímku** (PR #339, balíček `e9d119a89a37`, nasazený web, headless Chromium se
SwiftShaderem, tedy CPU – jen poměr; výchozí kamera hry, dvě kola model zapnutý / vypnutý, po 9 s):

| Místo | model zapnutý p50 / p90 | vypnutý p50 / p90 | trojúhelníky scény |
|---|---|---|---|
| Asakusa-dōri ke Skytree (3692, 3061) | 64,1 / 75,3 a 85,7 / 100 ms | 100 / 100 (17 snímků, zásek) a 59,7 / 70,0 ms | +2,6 tis., +1 draw call |
| Gyōkō-dōri k nádraží (−319, 58) | 64,6 / 76,6 a 73,3 / 92,6 ms | 66,5 / 73,9 a 67,0 / 76,0 ms | +1,5 tis., ±1 draw call |

U nádraží p50 v šumu (−3 až +9 %), u Skytree mezi koly kolísá víc než mezi stavy (SwiftShader drží
strop 100 ms). Na telefonech měří Ol1n (`plans/verify.yaml` M7-H5).

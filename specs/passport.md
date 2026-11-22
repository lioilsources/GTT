# Pas turisty

**version: 1** · P0 (pravidla) + P1 (objevování za jízdy) · vektory `vectors/passport.json` ·
plán: METROPOLE_PLAN 4 („Pas turisty“), 5.5 (pohlednice), M1 body 9 a 12 · parita F-019, F-020

## Účel

Hlavní progres hráče ve městě. Za objevené památky, projeté čtvrti, minihry na 3★ a (později)
fotomísta dostane razítko do Pasu; Pas ukazuje procento dokončení města. Objevená památka vysune
kartu „pohlednice“ (obrázek + 2 věty vlastního textu).

## Katalog razítek

Katalog města skládá klient z dat města, stejně v obou klientech:

| Druh (`kind`) | Odkud | `id` |
|---|---|---|
| `landmark` | `landmarks.pb`: `hero = true` **a** v `i18n/en.json` existuje klíč `lm_<id>_title` | `Landmark.id` |
| `district` | `Manifest.districts` (pořadí balíčku) | `districtId(name)`, viz níže |
| `minigame` | `spots.pb`: neprázdné `Spot.minigame` (pořadí spotů) | id minihry |
| `photo` | fotomísta (zatím žádná, pole je prázdné) | – |

- Památka s pohlednicí má v `i18n/` klíče `lm_<id>_title` (jméno jako v `landmarks.yaml`, obchodní
  věže adresou podle R10) a `lm_<id>_text` (2 krátké věty vlastními slovy). V M1 je jich 20.
- `districtId(name)`: malá písmena, písmena s diakritikou se přepíšou na základní podle tabulky
  níže (M3, Praha), apostrofy (`'`, `’`) a tečky se vypustí, každý úsek jiných znaků než `a–z0–9`
  se nahradí jedním `_`, `_` na krajích se ořízne. Tabulka (po převodu na malá písmena):
  `á→a ä→a à→a â→a č→c ç→c ď→d é→e ě→e è→e ê→e ë→e í→i î→i ï→i ľ→l ĺ→l ň→n ñ→n ó→o ô→o ö→o
  ő→o ř→r ŕ→r š→s ť→t ú→u ů→u ü→u ű→u û→u ý→y ÿ→y ž→z ß→ss`. Jiný znak mimo `a–z0–9` je oddělovač.
  „Žižkov“ → `zizkov`, „Malá Strana“ → `mala_strana`. Jména bez diakritiky (New York) dávají
  stejné id jako dřív, uložená razítka platí dál. „Hell's Kitchen“ →
  `hells_kitchen`, „DUMBO“ → `dumbo`. Stejné jméno dvakrát (Kips Bay) = jedno razítko.
- V každém druhu se duplicity vypustí, platí první výskyt.

Razítko je řetězec `<kind>:<id>` (např. `landmark:empire_state`, `district:soho`). Tak se ukládá
do `Save.stamps` (`schema/save.schema.json`).

## Stav

```
{
  catalog: {landmark: [id…], district: [id…], minigame: [id…], photo: [id…]},
  weights: [w_landmark, w_district, w_minigame, w_photo],
  starsForStamp: int,
  stamps: ["kind:id", …],   // v pořadí získání
  points: int,              // součet vah získaných razítek
  total: int,               // součet vah celého katalogu
  last: "kind:id" | ""      // razítko přidané posledním apply, jinak ""
}
```

Jen celá čísla, řetězce a pole; bez náhody (seed se nepoužívá).

## Akce

- `{"by": "player", "op": "visit", "kind": K, "id": I}` – hráč objevil památku / vjel do čtvrti /
  vyfotil fotomísto.
- `{"by": "player", "op": "visit", "kind": "minigame", "id": I, "stars": S}` – výsledek minihry
  (`S` 0–3).

## Pravidla

- `init(config, seed)`: `config = {landmarks, districts, minigames, photos, weights, starsForStamp,
  stamps}`; `weights` a `starsForStamp` z `passport.weights`, `passport.stars_for_stamp`
  (`content/tuning.yaml`). `stamps` je uložený stav (`Save.stamps`, může chybět = `[]`):
  ponechají se jen razítka z katalogu, bez duplicit, v původním pořadí; neznámá (obsah města se
  změnil) se tiše zahodí. `total = Σ_kind w_kind × |catalog[kind]|`, `points` podle `stamps`,
  `last = ""`.
- `legalActions(state)`: pro každý druh v pořadí `landmark, district, minigame, photo` a každé id
  katalogu bez razítka jedna akce `visit` (u minihry se `stars = 3`).
- `apply(state, action)`:
  - neznámý `op` nebo `kind`, `id` mimo katalog, u minihry `stars` mimo 0–3 → `IllegalAction`;
  - razítko už je, nebo minihra má `stars < starsForStamp` → stav beze změny až na `last = ""`;
  - jinak se `kind:id` přidá na konec `stamps`, `points += w_kind`, `last = kind:id`.
- `aiAction`: modul nemá soupeře (volání je chyba).
- `result(state)` (nikdy `null`, Pas nekončí):

  ```
  {percent, points, total, stamps: |stamps|, of: Σ|catalog[kind]|,
   kinds: {landmark: [mám, z], district: [mám, z], minigame: [mám, z], photo: [mám, z]}}
  ```

  `percent = total == 0 ? 0 : floor(100 × points / total)` (celočíselné dělení). 100 % je jen
  při plném katalogu.

## Hvězdy

Modul hvězdy nedává; razítko za minihru dostane jen výsledek s `stars ≥ starsForStamp` (3★).

## Objevování za jízdy (P1, jen klient)

Klient volá sledovač Pasu v HUD intervalu (~10× za sekundu) s polohou auta v metrech:

- **Památka:** objevená, když je auto do `passport.discover_radius_m` (eukleidovsky, metry) od
  kotvy popisku (`Landmark.x, y` v dm / 10). Víc památek v dosahu = v pořadí katalogu, za jedno
  volání nejvýš jedna nová (další přijde příští tick).
- **Čtvrť:** objevená, když `districtAt(x, y)` vrátí jméno; `kind = district`, `id = districtId(jméno)`.
- **Minihra:** po skončení minihry klient předá `stars` z `MinigameResult` (napojení přijde s feedem).
- **Fotomísto:** později (M2, Foťák).

Novou památku ukáže karta pohlednice; nová čtvrť krátký štítek „Razítko: <čtvrť>“. Obojí zmizí po
`passport.postcard_s` sekundách nebo klepnutím.

## Pohlednice (karta)

Karta 3 : 2 s obrázkem nahoře, pod ním `lm_<id>_title`, `lm_<id>_text` a značka razítka. Barvy jen
z `design/tokens.json` (`color.passport.*`).

**Hotová ilustrace má přednost** (`assets/postcards/<city>/<id>.png`, `specs/art.md`). **Jinak je obrázek zástupný.** Kreslí ho klient z výšky památky (`Landmark.height_m`) na plátno 300 × 200
jednotek (y dolů); skutečné ilustrace ve stylu hry přijdou později z ComfyUI (`tools/artgen`,
METROPOLE_PLAN 14: vlastní stylizované ilustrace, žádné fotky) a nahradí tento výkres:

1. Obloha `passportSky` přes celou plochu.
2. Kulisa: 6 bloků `passportSkyline`, šířka 44, x = 6 + 50·i, výška `30 + ((fnv1a(id) >> 4·i) & 31)` (posun bez znaménka)
   (`fnv1a` = 32bitový FNV-1a nad UTF-8 bajty `id`), stojí na y = 170.
3. `height_m > 0` (budova): zem `passportGround` od y = 170 dolů, výška těla `bh = round(30 + 120 × min(h, 541) / 541)`, šířka
   `bw = h ≥ 150 ? 56 : 110`, střed x = 150, spodek y = 170, barva `passportTower`. Okna
   `passportWindow` 6 × 6 na `(left + 9 + 12c, top + 9 + 12r)`, kreslí se jen okna s
   `x + 6 ≤ left + bw − 3` a `y + 6 ≤ 164`. Při `h ≥ 300` špice: trojúhelník `passportTower` se základnou
   `bw / 3` na vrchu těla a výškou 22. Pořadí kreslení = pořadí bodů.
4. `height_m = 0` (park, náměstí, most): zem od y = 130 `passportPark`; 5 korun stromů
   `passportTree`, kruhy r = 14 se středem (60 + 45·i, 128).

## Pas (obrazovka)

Mřížka razítek po druzích (`passportLandmarks`, `passportDistricts`, `passportMinigames`,
`passportPhotos`) s počtem `mám / z`, nahoře procento města (`passportProgress`). Získané razítko je
plné (`passportStamp`), chybějící obrys (`passportStampEmpty`). Památka se jménem z `lm_<id>_title`,
čtvrť jménem z balíčku, minihra `mg_<id>`. Klepnutí na získanou památku znovu ukáže pohlednici.
Dole tlačítko „O mapách“. Obrazovka je samostatná komponenta (F widget, W DOM), zatím otevíraná
z HUD, později z herního telefonu (aplikace Pas).

## O mapách (M1-S12)

Obrazovka s výčtem zdrojů a licencí, texty `about*` v `i18n/`. Znění Overture podle
<https://docs.overturemaps.org/attribution/> (ověřeno 2026-11): témata transportation, buildings,
base a divisions jsou pod ODbL; places převážně CDLA Permissive 2.0 (Foursquare Apache 2.0,
AllThePlaces CC0 1.0); doporučená atribuce „© OpenStreetMap contributors, Overture Maps Foundation“.
Městská open data ani GHSL balíček NYC zatím nepoužívá (`height_sources: [overture]`), obrazovka to
říká. Verze Overture se bere z `Manifest.overture_release`. Odkaz na zdrojový repozitář
(`aboutRepoUrl`).

## Hraniční případy

- Prázdný katalog → `total = 0`, `percent = 0`.
- Opakovaná návštěva → žádné nové razítko, `last = ""`.
- Uložené razítko, které už v katalogu není → zahozeno při `init`.
- Minihra na 2★ → bez razítka; pozdější 3★ razítko dá.

## Vektory

`vectors/passport.json` nahrává web (`metro vectors record --client web --module passport`), Dart je
přehrává přes `checkVectors`. Katalogy ve vektorech jsou syntetické (nezávislé na balíčku města).

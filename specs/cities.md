# Města a přepínání mezi nimi

**version: 1** · P2 (UI, kdy se přepíná, poslední město) · plán: METROPOLE_PLAN 15 (M3 „přepínání
měst“), `plans/M3_PRAHA.md` bod 3 · parita F-028

## Účel

Od M3 má hra víc měst (New York, Praha). Hráč se mezi nimi přesouvá z telefonu; každé město má
vlastní postup (`specs/save.md`: jedno uložení na `cityId`) a hra si pamatuje, kde hráč skončil.

## Seznam měst

- Města jsou složky `content/cities/<id>/` s `city.yaml`; `metro gen` z nich dělá `CityId`
  (pořadí podle id) a jméno z `city.yaml` `name` (`CityId.<id>.name`, TS `cityIdNames`).
- Balíček města nese `manifest.pb`; klient ho načte stejně pro každé město. Aplikace má v sobě
  všechna města z `metro.yaml` `bundle_cities`, web je stahuje z `packs/<id>/<verze>/`.

## Výchozí město

Při startu hry (pořadí, první platné vyhrává):

1. W: parametr `?city=<id>`, pokud je to známé `CityId`.
2. Poslední město: W `localStorage` klíč `metropole:city`; F soubor `city.json`
   (`{"city": "<id>"}`) v adresáři dokumentů aplikace. Neznámé id nebo nečitelný soubor = bez
   posledního města.
3. První město z `bundle_cities` (`nyc`).

Poslední město se zapíše při každém startu města (po načtení balíčku), ne až při odchodu.

## Aplikace Cesty

- Telefon má aplikaci **Cesty** (id `travel`, `specs/phone.md` v2) mezi Peněženkou a Nastavením.
- Obrazovka: seznam měst v pořadí `CityId`. Řádek = jméno města, pod ním „Pas N %“ (procento
  dokončení Pasu z uložení toho města, `specs/passport.md`; město bez uložení = 0 %). Aktuální
  město má štítek „Tady jsi“ a nejde vybrat.
- Klepnutí na jiné město: telefon se zavře, aktuální město se uloží (stejně jako při pozastavení,
  `specs/save.md`), pak se načte vybrané město od svého startu (`city.yaml` `start`) s jeho
  uložením. Rozehraná smyčka (minihra, taxi, cesta GPS) se zahodí bez výsledku.
- W přepíná znovunačtením stránky s `?city=<id>` (zachová ostatní parametry kromě `city`).
  F nahradí obrazovku hry novou pro vybrané město (`Navigator.pushReplacement`); stará uvolní
  svět, fyziku a ovladače.

## Co je po městech

| Věc | Kde | Poznámka |
|---|---|---|
| uložení | `save:<cityId>` / `save-<cityId>.json` | hotovost, auta, Pas, feed, NPC, nastavení |
| Galerie miniher | `cityId` aktuálního města | Galerie bez hry (W `?gallery`) bere výchozí město |
| dialogy NPC | `city` v `DialogueSession` | skity podle města (`specs/dialogue.md`) |
| benchmark | `content/bench/<cityId>.json` | město bez souboru má tlačítko benchmarku vypnuté |
| minihry podle měst | `content/minigames/catalog.yaml` `cities` | ve Feedu a na spotech jen hry pro město |

## Texty

`i18n/`: `app_travel`, `travelTitle`, `travelHere`, `travelPassport` (`{pct}`).

## Edge cases

- Jediné město v `CityId` (starší build): Cesty ukazují jen ho, nic nejde vybrat.
- Přepnutí během honičky policie: hledanost se zahodí (nová hra v jiném městě), pokuta nepadne.
- Balíček vybraného města se nepodaří načíst (W bez sítě): chybová obrazovka s tlačítkem zpět
  do předchozího města (W odkaz s jeho `?city=`, F návrat na předchozí obrazovku).

## Testy

- W i F: výběr výchozího města podle pořadí výše (čistá funkce `pickStartCity(param, last, bundled)`).
- W i F: přepnutí NYC → Praha → NYC zachová obě uložení (hotovost a razítka každého města).
- Soak (M3-A3): přepnutí měst 10× za sebou bez pádu a bez úniku paměti (F: počet živých těles
  fyziky po návratu je stejný).

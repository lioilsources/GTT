# Ikona aplikace a její barevný režim

**version: 1** · P2 (oba klienti, bez vektorů) · rozhodnutí Ol1na 2026-11-25 · parita F-083 ·
grafika `assets/ui/app_icon/` (`specs/art.md`, dávka gtt-icon) · texty `appIconTitle`,
`appIcon_<režim>`, `appIconLater`, `appIconTab`

## Účel

Hra má vlastní ikonu (auto shora na křižovatce před panoramatem) v pěti barevných režimech.
Hráč si režim vybere ve hře a ikona na ploše telefonu, resp. na panelu prohlížeče se podle toho změní.

## Režimy

| id | text | pozadí |
|---|---|---|
| `day` | `appIcon_day` | denní obloha |
| `night` | `appIcon_night` | noc |
| `sunset` | `appIcon_sunset` | západ slunce, **výchozí** |
| `teal` | `appIcon_teal` | tyrkysová |
| `japan` | `appIcon_japan` | japonská paleta |

Pořadí ve výběru je pořadí tabulky. Ke každému režimu jsou v `assets/ui/app_icon/` tři soubory
1024²: `<id>.png` (celá ikona, neprůhledná, bez zaoblení), `<id>_fg.png` (auto a stín na alfě
v bezpečné zóně adaptivní ikony 66/108; ve všech režimech stejné) a `<id>_bg.png` (pozadí).
Ikony klientů se z nich generují skriptem a výsledek se commituje; ručně se nekreslí nic.

## Výběr ve hře

- Místo: telefon → aplikace **Nastavení** (`specs/phone.md`), oddíl s nadpisem `appIconTitle`.
  Ve W je pod řádky kamery (`specs/terrain.md`), ve F je to první obsah Nastavení (aplikace tím
  přestane být šedá).
- Oddíl je řada pěti dlaždic: náhled ikony se zaoblenými rohy a pod ním název režimu. Vybraná
  dlaždice má zvýrazněný okraj. Klepnutí vybere režim hned, bez potvrzení.
- Pod dlaždicemi je jeden řádek drobného textu: W `appIconTab`, F na Androidu `appIconLater`,
  F na iOS nic.
- Telefon hru zastaví (`specs/pause.md`); výběr ikony na tom nic nemění.

## Uložení volby

Volba je nastavení zařízení, ne postup hry: **není v uložení hry** (`specs/save.md` se nemění,
přepnutí města ani smazání postupu ji nezmění). Stejný přístup jako volba kamery
(`specs/terrain.md`) a nápověda boostu (`specs/controls.md`).

- W: `localStorage` klíč `metro:appIcon`, hodnota id režimu. Čtení i zápis v try/catch; bez
  úložiště volba platí do zavření stránky.
- F: soubor `app_icon.json` (`{"mode": "<id>"}`) v dokumentech aplikace.
- Chybějící, nečitelná nebo neznámá hodnota = `sunset`.

## Chování podle platformy

### W (prohlížeč)

- `index.html` má `<link rel="icon">` (PNG 32 px) a `<link rel="apple-touch-icon">` (PNG 180 px)
  na `sunset` a `<link rel="manifest">` na `manifest.webmanifest` (název, `display: standalone`,
  barvy z `design/tokens.json`, ikony `sunset` 192 a 512 px s účelem `any` i `maskable`).
- Soubory: `web/public/icons/<id>-32.png` a `<id>-180.png` pro všech pět režimů, `sunset-192.png`
  a `sunset-512.png` pro manifest. Náhled ve výběru používá `<id>-180.png`.
- Při startu (před prvním snímkem) a při každém výběru klient přepíše `href` obou odkazů na
  zvolený režim. Mění se tím jen ikona panelu a ikona, kterou si prohlížeč vezme při novém
  přidání na plochu.
- **Nainstalovaná PWA a zástupce na ploše si nechají ikonu z okamžiku instalace** (manifest je
  statický, vždy `sunset`); výběr je nepřekreslí. Říká to text `appIconTab`.
- Ladění: `?icon=<id>` nastaví ikonu pro tohle načtení a volbu neukládá.

### F na iOS

- Hlavní ikona `AppIcon` = `sunset`; ostatní čtyři jsou alternativní ikony `AppIcon-<id>`
  v katalogu assetů.
- Přepíná se přes `UIApplication.setAlternateIconName` (`sunset` = `nil`). **Systém po změně
  ukáže vlastní upozornění**, že se ikona změnila; hra ho neovlivní ani neskryje.
- Když systém změnu odmítne, výběr se vrátí na předchozí režim a volba se neuloží.

### F na Androidu

- Každý režim má adaptivní ikonu (popředí + pozadí, API 26+) a PNG pro starší systémy a jeden
  `activity-alias` hlavní aktivity se spouštěcím filtrem (`MAIN` + `LAUNCHER`). Po instalaci je
  povolený jen alias `sunset`; hlavní aktivita sama spouštěcí filtr nemá, takže v launcheru je
  vždy právě jeden zástupce.
- Přepnutí = povolit alias zvoleného režimu a zakázat ostatní
  (`PackageManager.setComponentEnabledSetting` s `DONT_KILL_APP`). **Provede se, až hra odejde do
  pozadí** (`onStop` aktivity), ne hned: launcher může při změně aliasu běžící úlohu zavřít.
  Do té doby je volba jen uložená a pod dlaždicemi je text `appIconLater`.
- Výběr zpět na režim, který je právě povolený, nic nepřepíná. Launcher může ikonu překreslit
  s prodlevou a zástupce přesunout na konec plochy; připnuté zkratky starého aliasu zmizí.
- Ladicí a profile build má navíc druhého zástupce (hlavní aktivita se spouštěcím filtrem, kterou
  potřebují nástroje Flutteru pro `flutter run`); release má jediného.

### F jinde (desktop, testy)

Bez nativního kanálu se volba jen uloží a zobrazí ve výběru.

## Rozhraní F ↔ nativní část

Kanál `metropole/app_icon`, metoda `set` s argumentem id režimu (text). Vrací `true`, když je
změna provedena nebo naplánována, chybu, když ji systém odmítl. Při startu aplikace klient pošle
uloženou volbu znovu (srovná ikonu po obnově ze zálohy); nativní strana nedělá nic, když už
zvolený režim platí.

## Hraniční případy

- Neznámé id v úložišti nebo v `?icon=` → `sunset`.
- Výběr už vybraného režimu: žádný zápis, žádné volání systému.
- Rychlé přepínání na Androidu: platí poslední volba v okamžiku odchodu do pozadí.
- Reinstalace: úložiště i ikona se vrátí na `sunset`.

## Testy

- W (Vitest): čtení a zápis volby (neznámá hodnota, chybějící úložiště), přepsání obou odkazů,
  výběr v Nastavení změní ikonu a uloží volbu, každý soubor ikony existuje a má rozměr z názvu,
  manifest odkazuje na existující soubory.
- F (widget testy): Nastavení ukáže pět dlaždic, klepnutí uloží volbu a zavolá kanál s id režimu,
  odmítnutí vrátí původní výběr, obsah `app_icon.json` (neznámá hodnota → `sunset`).
- Nativní přepnutí (upozornění iOS, alias Androidu) se ověřuje ručně na zařízení.

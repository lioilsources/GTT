# Herní telefon, mapa a navigace

**version: 2** · P2 · plán: METROPOLE_PLAN 8, M1 body 1 a 7 · navazuje na `specs/feed.md`, `specs/route.md`

## Účel

Herní telefon je rozcestník: Feed nabízí, kam jet hrát, Mapa ukazuje město a trasu. Po přijetí
karty vede hráče GPS navigace. Chování je P2 (UI v reálném čase); čisté části (start a cíl trasy,
lomená čára trasy, postup po ní, formát vzdálenosti, šipka na okraji) mají unit testy v obou klientech.
Čísla jsou v `content/tuning.yaml` (`phone`, `nav`, `route`, `feed`), barvy v `design/tokens.json`
(`color.phone`, `color.ui.route*`), texty v `i18n/`.

## Telefon

- Otevření: tah nahoru od spodního okraje (pruh vysoký `phone.edge_px`, tah aspoň `phone.pull_px`)
  nebo tlačítko v HUD. Zavření: tah dolů po horní liště telefonu, tlačítko ✕ nebo Esc (web).
- Telefon zabírá spodní část obrazovky (`phone.height_pct` % výšky), jízda pod ním běží
  zpomaleně: krok fyziky dostává `dt × phone.time_scale`.
- Domovská obrazovka: mřížka aplikací v pořadí Feed, Mapa, Garáž, Pas, Foťák, Kontakty,
  Peněženka, Cesty, Nastavení. V M1 fungují Feed a Mapa, ostatní jsou šedé. Cesty (v2, M3)
  přepínají města (`specs/cities.md`). Klient má registr aplikací
  (slot): jiná feature později dodá obrazovku pro své id a aplikace zezelená.
- Zpět (šipka v liště) vrací z aplikace na domovskou obrazovku.

## Feed

- Karta přes celou obrazovku telefonu: portrét hostitele (v M1 zástupná silueta s jemným
  pohybem), zvací věta `feedHost1..6`, štítky: typ hry (`engine_<id>`), místo a čtvrť,
  vzdálenost a čas jízdy, odměna, obtížnost; u místní hry štítek `feedLocal`.
- Gesta (práh `phone.swipe_px`): tah nahoru = `next`, tah vpravo nebo „Jedu“ = `accept`,
  dvojité klepnutí (do `phone.double_tap_ms`) = `like`, tah vlevo = `less`. Akce jdou přes pravidla
  `specs/feed.md`; UI jen kreslí stav.
- Po balíčku obrazovka `feedDone` (viz `specs/feed.md` „Po balíčku“).
- `accept` zavře telefon a spustí navigaci ke spotu karty.

## Mapa

Pohled shora na celé město: ponechané silnice (`kept`), body spotů (s minihrou výrazněji),
poloha a směr hráče, aktivní trasa. Měřítko: obrys oblasti města se vejde do plochy s okrajem
`phone.map_padding_px`, sever nahoře.

## Navigace

### Start a cíl

- **Start**: hrana auta (`LayerTracker.hit`). Je-li to ulička (`kept = false`), vezme se nejbližší
  ponechaná hrana do `nav.search_m`. Jednosměrka `oneway = 1` → uzel `to`, `−1` → `from`;
  obousměrná → konec ve směru jízdy: `to`, když `cos(heading)·dirX + sin(heading)·dirY ≥ 0`
  (směr segmentu `from → to` v místě auta), jinak `from`.
- **Cíl**: hrana spotu (`spot.edge`). Jednosměrka `1` → `from`, `−1` → `to` (vjezd), obousměrná →
  konec bližší parkovacímu bodu podél hrany (parametr průmětu `t < 0.5` → `from`, jinak `to`).
- Trasa `findRoute(start, cíl)` ze `specs/route.md`. Nedosažitelný cíl = navigace se nespustí
  (feed kartu přesto přijme a ukáže jen šipku k cíli).

### Lomená čára (metry)

Bod auta promítnutý na jeho hranu → po té hraně do startovního uzlu → hrany trasy (body orientované
po směru jízdy) → po hraně spotu od cílového uzlu k průmětu parkovacího bodu → parkovací bod.
Jede-li auto už po hraně spotu směrem k parkovacímu bodu (jednosměrka to dovoluje a průmět
parkovacího bodu je před autem), čára vede rovnou po hraně.

### Za jízdy

- Postup: auto se promítá na úseky čáry od posledního známého úseku `− 2` dál; nejbližší vyhrává
  (při shodě dřívější). Zbývající vzdálenost = délka čáry od průmětu do konce.
- Přepočet: vzdálenost auta od čáry `> route.reroute_m` déle než `route.reroute_s` → nová trasa
  ze současné polohy.
- Dojezd: auto do `route.arrive_m` od parkovacího bodu → navigace končí, událost
  `arrived(spotId)` (háček pro spuštění minihry v pozdější feature), toast `arrived` na
  `nav.toast_s`.
- Kreslení: čára od průmětu auta do konce barvou `colorUiRoute`, šířka `route.line_width_m`
  v metrech světa, pod budovami (F) / v překryvné vrstvě (W). Je-li parkovací bod mimo obrazovku
  zmenšenou o `nav.arrow_margin_px`, na jejím okraji je šipka (`colorUiRouteArrow`, velikost
  `nav.arrow_px`) na průsečíku paprsku z kotvy auta k cíli s tímto obdélníkem, natočená k cíli.
- HUD: pilulka `routeTo(place, distance)` a tlačítko `routeCancel`.

### Formát vzdálenosti

- Metrické město: pod `nav.km_from_m` → `distanceM` zaokrouhleno na `nav.round_m`, jinak
  `distanceKm` s jedním desetinným místem.
- Imperiální (`units = imperial`): stopy = m × 3,28084, míle = m ÷ 1609,344; pod `nav.mi_from`
  mil → `distanceFt` zaokrouhleno na `nav.round_ft`, jinak `distanceMi` s jedním desetinným místem.
- Čas jízdy na kartě: `max(1, round(driveS ÷ 60))` min (`feedDriveMin`).

## Ladění

- W: `?goto=<spotId>` spustí po načtení navigaci ke spotu; `?feedSeed=<n>` dá prvnímu balíčku seed.

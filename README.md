# Metropole

Volné ježdění autem po skutečném New Yorku, Praze a Tokiu na telefonu na výšku, s minihrami z vertikálního feedu.

**Zahraj si v prohlížeči:** <https://lioilsources.github.io/GTT/> (nejlíp na telefonu).

Bez zbraní a bez zabíjení: chodci vždy uskočí, policie jen honí a pokutuje (R7). Žádné reálné
značky: auta i podniky jsou fiktivní, památky a instituce mají skutečná jména (R10).
Zadání: [Prompts/](Prompts/) (00–05), postup: [plans/PROGRESS.md](plans/PROGRESS.md).

## Stav

<!-- metro:status -->
| | |
|---|---|
| Města s balíčkem | 3 |
| Minihry v katalogu | 33 (web 33, Flutter 29) |
| Auta | 43 |
| Památky | 87 |
| Skity NPC | 50 |
| Testy | 1038 / 1039 prochází (2026-11-23T04:23) |
| Funkce (`parity.yaml`) | 58 v obou klientech, 8 jen web, 0 jen Flutter, 9 rozpracováno |

_Stav k 2026-11-23, generuje `metro progress`._
<!-- /metro:status -->

## Parametry URL (web)

| Parametr | Co dělá |
|---|---|
| `?city=nyc` · `prague` · `tokyo` | start ve městě |
| `?spot=<id>` | start u místa z `content/cities/<id>/spots.yaml` |
| `?gallery` | galerie miniher bez jízdy |
| `?mg=<id>` | rovnou jedna minihra z `content/minigames/catalog.yaml` |
| `?debug` | ladicí panel s hodnotami z `tuning.yaml` |

## Jak přidat město

1. `content/cities/<id>/city.yaml` (jméno, počátek projekce, strana provozu) a `area.geojson`
   s hranicí; vzor je `content/cities/prague/`.
2. `districts.yaml`, `landmarks.yaml` a `spots.yaml`: čtvrti, památky a místa miniher.
3. `run/bin/citypack build <id>`: stáhne Overture a výšky a postaví balíček; `citypack validate <id>`
   musí projít (`docs/citypack.md`).
4. `run/bin/citypack publish <id>` zapíše verzi do `packs.lock`; id přidej do `bundle_cities`
   v `metro.yaml`.
5. `run/bin/metro gen && run/bin/metro sync`, pak `cd web && npm run dev` a `?city=<id>`.

## Spuštění

```sh
run/bin/citypack pull all               # balíčky měst podle packs.lock (nebo citypack build nyc)
run/bin/metro sync                      # sdílené soubory do app/assets/shared a web/public/shared
flutter pub get                         # workspace: app + packages
cd app && flutter run --profile         # telefon / macOS
cd web && npm ci && npm run dev         # webový klient (Babylon.js)
```

Sdílená vrstva (`metro`, generovaný kód, vektory, parita): [docs/metro.md](docs/metro.md).

Ovládání na klávesnici (desktop): šipky / WASD, mezerník = ruční brzda.
Dva klienti nad jednou sdílenou vrstvou: webový ve `web/` (TypeScript, Babylon.js, GitHub Pages)
a Flutter v `app/` (pro obchody), plán `Prompts/01-METROPOLE_DUALSTACK_PLAN.md`.
V aplikaci: ☀︎ přepíná den a noc, ⚙ otevře ladicí panel (schéma ovládání A/B/C, hodnoty z `tuning.yaml`
a parametry auta za běhu, tlačítko „Kopírovat tuning.yaml“).

## Balíček města (`citypack`)

Go CLI v `tools/citypack` staví z Overture Maps balíček města do `build/packs/<city>/` (mimo git;
sdílí se přes GitHub Releases: `citypack publish` / `pull`, verze v `packs.lock`).
Potřebuje `duckdb` (CLI, s rozšířením spatial) a pro změnu schématu `protoc`.

```sh
cd tools/citypack && go build -o ../../run/bin/citypack ./cmd/citypack && cd ../..
run/bin/citypack build nyc         # fetch → roads → widen → buildings → ground → landmarks → spots → pack → validate → preview
run/bin/citypack validate nyc      # jen kontrola hotového balíčku; selhání = nenulový exit code
run/bin/citypack -force pack nyc   # přepočítat jeden krok (stažená data zůstávají, -refetch je stáhne znovu)
```

Mezivýsledky a stažená data jsou v `run/citypack/<city>/` (gitignorováno), přehledka města v
`run/citypack/<city>/preview/index.html` (PNG přes mapu OpenStreetMap s posuvníkem průhlednosti).
Podrobnosti: [docs/citypack.md](docs/citypack.md).

## Struktura

| Cesta | Co tam je |
|---|---|
| `app/` | Flutter aplikace: herní smyčka (Flame), HUD, ladicí panel, lokalizace (ARB cs/en) |
| `packages/world_engine/` | načtení citypacku, streaming chunků, 2,5D renderer, kamera |
| `packages/drive_core/` | čistá logika bez UI: fyzika auta (Box2D v3 přes forge2d), ovládání A/B/C, vrstvy mostů a tunelů, mobiliář |
| `packages/shared_gen/` | generovaný kód ze sdílené vrstvy (`metro gen`) |
| `packages/rules_core/` | čistá deterministická pravidla: PRNG, tvar modulu P0, přehrávání vektorů |
| `web/` | webový klient: TypeScript, Vite, Babylon.js |
| `tools/citypack/` | Go pipeline map, schéma `proto/citypack.proto` |
| `tools/metro/` | Go CLI sdílené vrstvy: gen, sync, validate, guard, vectors, parity |
| `content/` | `tuning.yaml` (jediný zdroj herních čísel), auta, města, katalog miniher |
| `i18n/`, `design/`, `schema/`, `specs/`, `vectors/`, `scenarios/`, `assets/` | sdílená vrstva, viz `docs/metro.md` |
| `plans/` | pod-plány dalších milníků |

## Referenční telefony

Výkon (60 fps, RAM < 600 MB) se měří na:
**Google Pixel 8a** (Android) a **iPhone 12 mini** (iOS).

## Licence a zdroje dat

- Kód a herní data (`content/` mimo `content/npc/`): MIT, viz [LICENSE](LICENSE).
- `assets/` a dialogy `content/npc/`: CC BY-NC 4.0.
- Balíčky měst: odvozená databáze pod ODbL. © OpenStreetMap contributors, Overture Maps Foundation,
  výšky AWS Terrain Tiles. Úplný seznam zdrojů a podmínek: [NOTICE](NOTICE).

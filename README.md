# Metropole

Volné ježdění autem po skutečných metropolích – mobilní hra na výšku, ovládaná jedním palcem.
Úkoly se vybírají ve vertikálním feedu na herním telefonu, každý je minihra na konkrétním místě ve městě.
Zadání a uzavřená rozhodnutí: [Prompts/00-METROPOLE_PLAN.md](Prompts/00-METROPOLE_PLAN.md).

**Stav: M0 – Hračka.** Jezdí se po Midtownu (30.–60. ulice, od řeky k řece). Bez provozu, chodců,
policie, feedu, miniher a ukládání. Co je hotové a co zbývá k akceptaci: [docs/m0.md](docs/m0.md).

## Spuštění

```sh
flutter pub get                         # workspace: app + packages
cd app && flutter run --profile         # telefon / macOS
cd app && flutter build web --profile   # web build k nasdílení (build/web)
```

Ovládání na klávesnici (desktop, web): šipky / WASD, mezerník = ruční brzda.
V aplikaci: ☀︎ přepíná den a noc, ⚙ otevře ladicí panel (schéma ovládání A/B/C, hodnoty z `tuning.yaml`
a parametry auta za běhu, tlačítko „Kopírovat tuning.yaml“).

## Balíček města (`citypack`)

Go CLI v `tools/citypack` staví z Overture Maps balíček města do `app/assets/cities/<city>/`.
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
| `packages/drive_core/` | fyzika auta (Box2D v3 přes forge2d), ovládání A/B/C, vrstvy mostů a tunelů, mobiliář |
| `tools/citypack/` | Go pipeline map, schéma `proto/citypack.proto` |
| `content/` | `tuning.yaml`, auta, konfigurace měst (`city.yaml`, `area.geojson`, `landmarks.yaml`, `spots.yaml`, `districts.yaml`) |
| `plans/` | pod-plány dalších milníků |

## Referenční telefony

Brána M0 (60 fps, příprava bufferu budov ≤ 4 ms, RAM < 600 MB) se měří na:
**Google Pixel 8a** (Android) a **iPhone 12 mini** (iOS).

## Mapová data a licence

© OpenStreetMap contributors (ODbL) · Overture Maps Foundation. Balíčky měst jsou odvozená databáze
a podléhají ODbL – zveřejňují se spolu s konfigurací pipeline.

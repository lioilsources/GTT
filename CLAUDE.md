# Metropole (GTT)

## Účel
Mobilní hra na výšku: volné ježdění po skutečných metropolích + minihry z feedu. Zadání a uzavřená
rozhodnutí R1–R13 jsou v `Prompts/00-METROPOLE_PLAN.md`; neotvírej je. Stav milníku: `docs/m0.md`.

## Build a test
```
flutter pub get                                   # Dart workspace (app, packages/*)
flutter analyze app packages/world_engine packages/drive_core
(cd packages/world_engine && flutter test); (cd packages/drive_core && flutter test); (cd app && flutter test)
(cd tools/citypack && go vet ./... && go test ./...)
(cd app && flutter run --profile)                 # lokálně vždy --profile
run/bin/citypack build nyc                            # postav nejdřív: go build -o ../../run/bin/citypack ./cmd/citypack
```

## Mapa
- `app/` – Flutter shell, Flame smyčka (`lib/game`), HUD a ladicí panel (`lib/ui`), ARB cs/en (`lib/l10n`).
- `packages/world_engine/` – citypack loader, streaming, renderer, kamera; `lib/src/pb` je generované.
- `packages/drive_core/` – auto, ovládání A/B/C, vrstvy, mobiliář (forge2d = Box2D v3, nativně i WASM).
- `tools/citypack/` – Go pipeline, schéma `proto/citypack.proto`.
- `content/` – jediný zdroj laditelných hodnot a obsahu (`tuning.yaml`, `cars/`, `cities/<id>/`).
- `app/assets/cities/<id>/` – výstup `citypack pack` (commitovaný, ODbL).

## Invarianty
- `content/tuning.yaml` a `content/cars/*.json` jsou do `app/assets` symlinkované, nekopíruj je.
- Změna `citypack.proto`: přegeneruj Go i Dart (`protoc --go_out=… --dart_out=packages/world_engine/lib/src/pb`)
  a při nekompatibilní změně zvyš `FormatVersion` v `pack.go` i kontrolu v `model.dart`.
- Souřadnice: metry lokální rovinné projekce od `origin`, y na sever; v protobufu decimetry.
- Ponechaná hrana (`kept`) = silnice s provozem a GPS; ostatní hrany jsou průjezdné uličky.
- Budovy kolidují jen ve vrstvě 0; vrstvu auta mění jen sousední hrana grafu.
- Overture release je připnutý v `city.yaml`; `-refetch` stahuje znovu.
- Žádné reálné značky (R10), žádné LLM za běhu (R9), uživatelský text jen přes ARB.

## Odchylky
Žádné. (Lokální složka je GTT, projekt a Dart balíčky se jmenují `metropole`.)

## Kam dál
`docs/m0.md` (stav, akceptace), `docs/citypack.md` (pipeline, ověřená schémata), `plans/` (pod-plány M1+).

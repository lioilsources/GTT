# Metropole (GTT)

## Účel
Mobilní hra na výšku: volné ježdění po skutečných metropolích + minihry z feedu. Dva klienti:
F (Flutter, story) a W (TypeScript + Babylon.js, GitHub Pages) nad jednou sdílenou vrstvou.
Zadání: `Prompts/00-METROPOLE_PLAN.md`, `Prompts/01-METROPOLE_DUALSTACK_PLAN.md` (při rozporu platí 01);
uzavřená rozhodnutí neotvírej. Stav: `docs/m0.md`, postup: `plans/PROGRESS.md`.

## Build a test
```
(cd tools/metro && go build -o ../../run/bin/metro ./cmd/metro)
(cd tools/citypack && go build -o ../../run/bin/citypack ./cmd/citypack)
run/bin/citypack pull all  # nebo: run/bin/citypack build nyc
run/bin/metro gen && run/bin/metro sync
flutter pub get && flutter analyze app packages
for p in packages/*/ app; do [ -d $p/test ] && (cd $p && flutter test); done
(cd web && npm ci && npm run typecheck && npm test && npm run build)
(cd tools/metro && go test ./...); (cd tools/citypack && go test ./...)
run/bin/metro validate && run/bin/metro vectors check && run/bin/metro gen --check && run/bin/metro parity report
run/bin/metro progress --tests   # po každé dokončené položce plans/progress.yaml (pravidla v PROGRESS.md)
(cd app && flutter run --profile)  # lokálně vždy --profile
```

## Mapa
- `app/` – Flutter shell, Flame smyčka, HUD, ladicí panel, kreslení (`lib/game/paint`).
- `packages/world_engine/` – citypack, streaming, renderer; čistá část v `lib/core.dart`.
- `packages/drive_core/` – čistá logika jízdy (bez Flutteru, `dart:ui`).
- `packages/rules_core/` – PRNG, tvar modulu P0, přehrávání vektorů (čistý Dart).
- `packages/shared_gen/`, `web/src/gen/` – generované `metro gen`, needitovat.
- `web/` – klient W (Vite, Babylon.js 9, Vitest).
- `tools/citypack/` – pipeline map; `tools/metro/` – sdílená vrstva (docs/metro.md).
- `content/`, `i18n/`, `design/`, `schema/`, `specs/`, `vectors/`, `scenarios/`, `assets/`, `parity.yaml`.

## Invarianty
- Herní čísla jen v `content/tuning.yaml`, texty jen v `i18n/`, barvy jen v `design/tokens.json`;
  klienti je čtou přes generovaný kód (`Tuning`, `Tokens`, ARB / `i18n.ts`). Natvrdo nic.
- Typ pole v `Tuning` určuje literál v YAML: `25` int, `25.0` double.
- Pravidla a logika v čistých modulech; test v `drive_core` hlídá importy Flutteru a `dart:ui`.
- Kód bez specifikace v `specs/` se nepíše; změna chování = vyšší `version` + nové vektory.
- P0 kód: jen celá čísla a řetězce, PRNG ze `specs/prng.md`, AI rozpočet v iteracích.
- Balíčky měst nejsou v gitu (`build/packs/`); `app/assets/shared/`, `web/public/shared/` plní `metro sync`.
- Větve `shared/…`, `flutter/…`, `web/…` smí měnit jen své cesty (`metro.yaml`, `metro guard`).
- Souřadnice: metry lokální projekce od `origin`, y na sever; v protobufu decimetry.
- Budovy kolidují jen ve vrstvě 0; vrstvu auta mění jen sousední hrana grafu.
- Žádné reálné značky (R10), žádné LLM za běhu (R9).

## Odchylky
Žádné. (Lokální složka je GTT, projekt a balíčky se jmenují `metropole`.)

## Kam dál
`docs/metro.md` (sdílená vrstva), `docs/m0.md`, `docs/m0-test.md`, `docs/citypack.md`,
`plans/PROGRESS.md` (pravidla měření postupu), `specs/`.
